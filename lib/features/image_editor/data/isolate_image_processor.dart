import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/services/app_logger.dart';
import 'package:md_scanner/features/image_editor/data/image_pipeline.dart';
import 'package:md_scanner/features/image_editor/data/raster.dart';
import 'package:md_scanner/features/image_editor/domain/image_models.dart';
import 'package:md_scanner/features/image_editor/domain/image_processor.dart';
import 'package:md_scanner/features/image_editor/domain/quad.dart';
import 'package:md_scanner/features/image_editor/domain/scan_mode.dart';

/// [ImageProcessor] in pure Dart. Every call reads, processes and writes
/// inside a short-lived worker isolate (`Isolate.run`), so the UI isolate
/// never touches a pixel.
///
/// At most [maxConcurrentJobs] workers run at once; further calls wait their
/// turn. A full-size page needs tens of megabytes while it is processed, and
/// saving a multi-page scan must not multiply that by the number of pages.
///
/// The only state is the reduced copy of the last previewed source (a few
/// megabytes), which is what makes successive previews of a page fast. It is
/// tied to the file's size and modification time, replaced when another
/// source is previewed and can be dropped with [clearPreviewCache].
class IsolateImageProcessor implements ImageProcessor {
  IsolateImageProcessor({this.logger, int maxConcurrentJobs = 2})
    : assert(maxConcurrentJobs > 0),
      _gate = _Gate(maxConcurrentJobs);

  /// Receives durations and failure kinds only, never paths.
  final AppLogger? logger;
  final _Gate _gate;
  _PreviewBase? _previewBase;

  @override
  Future<Result<ImageInfo>> inspect(String path) =>
      _run('inspect', runInspect, path, logSuccess: false);

  @override
  Future<Result<Quad?>> detectDocument(
    String path, {
    ScanMode mode = ScanMode.document,
  }) async {
    // Reuse the preview copy when this very file is already loaded; never
    // load it just for detection, which only needs a much smaller decode.
    Raster? base;
    final cached = _previewBase;
    if (cached != null && cached.key == await _SourceKey.of(path)) {
      base = (await cached.raster).valueOrNull;
    }
    return _run('detect', runDetect, DetectJob(path, mode, base));
  }

  @override
  Future<Result<ProcessedImage>> render(ImageRenderRequest request) =>
      _run('render', runRender, request);

  @override
  Future<Result<Uint8List>> preview(ImagePreviewRequest request) async {
    final base = await _loadPreviewBase(request.sourcePath);
    return switch (base) {
      Err<Raster>(:final failure) => Err<Uint8List>(failure),
      Success<Raster>(:final value) => _run(
        'preview',
        runPreview,
        PreviewJob(value, request),
        logSuccess: false,
      ),
    };
  }

  @override
  Future<Result<String>> thumbnail(
    String sourcePath,
    String outputPath, {
    int maxSize = 512,
  }) => _run(
    'thumbnail',
    runThumbnail,
    ThumbnailJob(sourcePath, outputPath, maxSize),
    logSuccess: false,
  );

  /// Releases the reduced copy kept for previews, for instance when the
  /// editor closes or the system reports memory pressure.
  void clearPreviewCache() => _previewBase = null;

  Future<Result<Raster>> _loadPreviewBase(String path) async {
    final key = await _SourceKey.of(path);
    final cached = _previewBase;
    if (key != null && cached != null && cached.key == key) {
      return cached.raster;
    }
    final loading = _run('preview_base', runLoadPreviewBase, path);
    if (key == null) return loading;
    // Cached as a future: concurrent previews of a new page share one decode.
    final entry = _PreviewBase(key, loading);
    _previewBase = entry;
    final result = await loading;
    if (result.isFailure && identical(_previewBase, entry)) {
      _previewBase = null;
    }
    return result;
  }

  Future<Result<R>> _run<M, R>(
    String operation,
    Result<R> Function(M message) job,
    M message, {
    bool logSuccess = true,
  }) async {
    await _gate.acquire();
    final watch = Stopwatch()..start();
    Result<R> result;
    try {
      result = await _spawn(job, message);
    } catch (error) {
      // The worker itself could not run (isolate spawn failure, worker
      // killed by the system): jobs never throw, they return an `Err`.
      result = Err<R>(
        ImageFailure(
          ImageFailureKind.processingFailed,
          debugMessage: error.runtimeType.toString(),
        ),
      );
    } finally {
      _gate.release();
    }
    final failure = result.failureOrNull;
    if (failure != null) {
      logger?.failure('image.$operation.failed', failure);
    } else if (logSuccess) {
      logger?.info('image.$operation', {'ms': watch.elapsedMilliseconds});
    }
    return result;
  }
}

/// Kept at top level so that the closure sent to the worker captures [job]
/// and [message] only, not the processor and its cached pixels.
Future<Result<R>> _spawn<M, R>(Result<R> Function(M message) job, M message) =>
    Isolate.run(() => job(message), debugName: 'image-processor');

/// Identity of a source file's content, cheap to obtain.
final class _SourceKey extends Equatable {
  const _SourceKey(this.path, this.size, this.modified);

  final String path;
  final int size;
  final DateTime modified;

  /// Null when the file does not exist or cannot be examined.
  static Future<_SourceKey?> of(String path) async {
    try {
      final stat = await File(path).stat();
      if (stat.type != FileSystemEntityType.file) return null;
      return _SourceKey(path, stat.size, stat.modified);
    } on FileSystemException {
      return null;
    }
  }

  @override
  List<Object?> get props => [path, size, modified];
}

final class _PreviewBase {
  const _PreviewBase(this.key, this.raster);

  final _SourceKey key;
  final Future<Result<Raster>> raster;
}

/// Counting semaphore, first come first served.
final class _Gate {
  _Gate(this._free);

  int _free;
  final Queue<Completer<void>> _waiting = Queue<Completer<void>>();

  Future<void> acquire() {
    if (_free > 0) {
      _free--;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _waiting.add(completer);
    return completer.future;
  }

  void release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _free++;
    }
  }
}
