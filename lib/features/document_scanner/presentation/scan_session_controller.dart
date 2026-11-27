import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/services/app_logger.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/core/utils/formatters.dart';
import 'package:md_scanner/features/document_scanner/domain/document_capture.dart';
import 'package:md_scanner/features/image_editor/domain/image_adjustments.dart';
import 'package:md_scanner/features/image_editor/domain/image_models.dart';
import 'package:md_scanner/features/image_editor/domain/image_processor.dart';
import 'package:md_scanner/features/image_editor/domain/quad.dart';
import 'package:md_scanner/features/image_editor/domain/scan_mode.dart';
import 'package:md_scanner/features/pdf_tools/domain/pdf_engine.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/repositories/document_repository.dart';
import 'package:uuid/uuid.dart';

/// One page of the scan being assembled. [sourcePath] is the untouched
/// capture; crop and adjustments are applied only when rendering, so every
/// edit stays reversible until the document is saved.
class ScanPage extends Equatable {
  const ScanPage({
    required this.id,
    required this.sourcePath,
    required this.adjustments,
    this.quad,
    this.cropAttempted = false,
  });

  final String id;
  final String sourcePath;
  final ImageAdjustments adjustments;

  /// Document outline found on an imported photo; null keeps the whole image.
  final Quad? quad;

  /// True for imported photos, on which automatic detection was run.
  final bool cropAttempted;

  ScanPage copyWith({
    String? id,
    ImageAdjustments? adjustments,
    Quad? Function()? quad,
  }) => ScanPage(
    id: id ?? this.id,
    sourcePath: sourcePath,
    adjustments: adjustments ?? this.adjustments,
    quad: quad != null ? quad() : this.quad,
    cropAttempted: quad != null ? false : cropAttempted,
  );

  @override
  List<Object?> get props => [id, sourcePath, adjustments, quad, cropAttempted];
}

class ScanSession extends Equatable {
  const ScanSession({
    required this.id,
    required this.mode,
    required this.pages,
  });

  final String id;
  final ScanMode mode;
  final List<ScanPage> pages;

  @override
  List<Object?> get props => [id, mode, pages];
}

/// Maximum number of pages captured in one pass by the camera scanner.
const int kScanPageLimit = 30;

/// Holds the scan in progress and turns it into a library document.
class ScanSessionController extends Notifier<ScanSession?> {
  final Uuid _uuid = const Uuid();

  @override
  ScanSession? build() => null;

  FileStorage get _storage => ref.read(fileStorageProvider);
  ImageProcessor get _images => ref.read(imageProcessorProvider);

  /// Captures pages with the camera scanner and appends them. Returns the
  /// number of pages added.
  Future<Result<int>> addFromCamera(ScanMode mode) async {
    final captured = await ref
        .read(documentCaptureProvider)
        .scanWithCamera(pageLimit: kScanPageLimit);
    return captured.andThen((paths) => _append(mode, paths, detect: false));
  }

  /// Imports photos and looks for a document outline on each of them.
  Future<Result<int>> addFromGallery(ScanMode mode) async {
    final picked = await ref.read(documentCaptureProvider).pickFromGallery();
    return picked.andThen((paths) => _append(mode, paths, detect: true));
  }

  Future<Result<int>> _append(
    ScanMode mode,
    List<String> paths, {
    required bool detect,
  }) => guard(() async {
    final sessionId = state?.id ?? _uuid.v4();
    final sessionMode = state?.mode ?? mode;
    final preset = sessionMode.preset.adjustments;
    final pages = <ScanPage>[];
    for (final path in paths) {
      final relative = await _storage.importFile(
        path,
        StorageArea.sessions,
        group: sessionId,
      );
      final source = _storage.absolutePath(relative);
      Quad? quad;
      if (detect) {
        final detection = await _images.detectDocument(
          source,
          mode: sessionMode,
        );
        quad = detection.valueOrNull;
      }
      pages.add(
        ScanPage(
          id: _uuid.v4(),
          sourcePath: source,
          // Google's scanner already crops and enhances a standard document:
          // re-filtering it would only degrade it.
          adjustments: !detect && sessionMode == ScanMode.document
              ? ImageAdjustments.none
              : preset,
          quad: quad,
          cropAttempted: detect,
        ),
      );
    }
    state = ScanSession(
      id: sessionId,
      mode: sessionMode,
      pages: [...?state?.pages, ...pages],
    );
    ref.read(appLoggerProvider).info('scan.pages_added', {
      'count': pages.length,
      'mode': sessionMode,
      'imported': detect,
    });
    return pages.length;
  });

  void _updatePages(List<ScanPage> Function(List<ScanPage> pages) change) {
    final session = state;
    if (session == null) return;
    state = ScanSession(
      id: session.id,
      mode: session.mode,
      pages: change([...session.pages]),
    );
  }

  void rotate(String pageId) => _updatePages(
    (pages) => [
      for (final page in pages)
        page.id == pageId
            ? page.copyWith(
                adjustments: page.adjustments.copyWith(
                  quarterTurns: (page.adjustments.quarterTurns + 1) % 4,
                ),
              )
            : page,
    ],
  );

  void setFilter(String pageId, ScanFilter filter) => _updatePages(
    (pages) => [
      for (final page in pages)
        page.id == pageId
            ? page.copyWith(
                adjustments: page.adjustments.copyWith(filter: filter),
              )
            : page,
    ],
  );

  /// Applies a manual crop; null keeps the whole page.
  void setQuad(String pageId, Quad? quad) => _updatePages(
    (pages) => [
      for (final page in pages)
        page.id == pageId ? page.copyWith(quad: () => quad) : page,
    ],
  );

  void duplicate(String pageId) => _updatePages((pages) {
    final index = pages.indexWhere((page) => page.id == pageId);
    if (index >= 0) {
      pages.insert(index + 1, pages[index].copyWith(id: _uuid.v4()));
    }
    return pages;
  });

  void remove(String pageId) =>
      _updatePages((pages) => pages..removeWhere((page) => page.id == pageId));

  /// Moves a page from [oldIndex] to [newIndex] (indexes of the final list).
  void reorder(int oldIndex, int newIndex) => _updatePages((pages) {
    if (oldIndex < 0 || oldIndex >= pages.length) return pages;
    final page = pages.removeAt(oldIndex);
    pages.insert(newIndex.clamp(0, pages.length), page);
    return pages;
  });

  /// Renders every page, builds the PDF and registers it in the library.
  Future<Result<DocumentEntity>> exportPdf(
    String name, {
    void Function(int done, int total)? onProgress,
  }) async {
    final session = state;
    if (session == null || session.pages.isEmpty) {
      return const Err(ScanFailure(ScanFailureKind.sessionNotFound));
    }
    final created = <String>[];
    final result = await guard(() async {
      final group = _uuid.v4();
      final pagePaths = await _renderPages(session, group, created, onProgress);
      final pdfPath = _storage.allocate(
        StorageArea.documents,
        extension: 'pdf',
      );
      created.add(pdfPath);
      final pdf = _unwrap(
        await ref
            .read(pdfEngineProvider)
            .imagesToPdf(
              imagePaths: [for (final p in pagePaths) _storage.absolutePath(p)],
              outputPath: _storage.absolutePath(pdfPath),
            ),
      );
      final thumbnail = await _thumbnail(pagePaths.first, created);
      return _unwrap(
        await ref
            .read(documentRepositoryProvider)
            .register(
              NewDocument(
                name: sanitizeFileName(name),
                filePath: pdfPath,
                fileType: DocumentFileType.pdf,
                source: DocumentSource.scan,
                pageCount: pdf.pageCount,
                thumbnailPath: thumbnail,
                pageImagePaths: pagePaths,
              ),
            ),
      );
    });
    await _finish(result.isSuccess, created, session);
    return result;
  }

  /// Saves each page as a separate JPG document. Returns how many were saved.
  Future<Result<int>> exportImages(
    String name, {
    void Function(int done, int total)? onProgress,
  }) async {
    final session = state;
    if (session == null || session.pages.isEmpty) {
      return const Err(ScanFailure(ScanFailureKind.sessionNotFound));
    }
    final created = <String>[];
    final result = await guard(() async {
      final repository = ref.read(documentRepositoryProvider);
      final base = sanitizeFileName(name);
      for (var i = 0; i < session.pages.length; i++) {
        final page = session.pages[i];
        final path = _storage.allocate(StorageArea.documents, extension: 'jpg');
        created.add(path);
        _unwrap(await _render(session, page, path));
        final thumbnail = await _thumbnail(path, created);
        _unwrap(
          await repository.register(
            NewDocument(
              name: session.pages.length == 1 ? base : '$base ${i + 1}',
              filePath: path,
              fileType: DocumentFileType.jpg,
              source: DocumentSource.scan,
              pageCount: 1,
              thumbnailPath: thumbnail,
            ),
          ),
        );
        onProgress?.call(i + 1, session.pages.length);
      }
      return session.pages.length;
    });
    await _finish(result.isSuccess, created, session);
    return result;
  }

  Future<List<String>> _renderPages(
    ScanSession session,
    String group,
    List<String> created,
    void Function(int done, int total)? onProgress,
  ) async {
    final paths = <String>[];
    for (var i = 0; i < session.pages.length; i++) {
      final path = _storage.allocate(
        StorageArea.pages,
        extension: 'jpg',
        group: group,
      );
      created.add(path);
      await File(_storage.absolutePath(path)).parent.create(recursive: true);
      _unwrap(await _render(session, session.pages[i], path));
      paths.add(path);
      onProgress?.call(i + 1, session.pages.length);
    }
    return paths;
  }

  Future<Result<ProcessedImage>> _render(
    ScanSession session,
    ScanPage page,
    String relativeOutput,
  ) => _images.render(
    ImageRenderRequest(
      sourcePath: page.sourcePath,
      outputPath: _storage.absolutePath(relativeOutput),
      quad: page.quad,
      adjustments: page.adjustments,
      mode: session.mode,
    ),
  );

  Future<String?> _thumbnail(String relativeImage, List<String> created) async {
    final path = _storage.allocate(StorageArea.thumbnails, extension: 'jpg');
    final result = await _images.thumbnail(
      _storage.absolutePath(relativeImage),
      _storage.absolutePath(path),
    );
    if (result.isFailure) return null;
    created.add(path);
    return path;
  }

  Future<void> _finish(
    bool success,
    List<String> created,
    ScanSession session,
  ) async {
    if (success) {
      ref.read(appLoggerProvider).info('scan.exported', {
        'pages': session.pages.length,
        'mode': session.mode,
      });
      await discard();
      return;
    }
    for (final path in created) {
      await _storage.delete(path);
    }
  }

  /// Drops the session and its working files.
  Future<void> discard() async {
    final session = state;
    state = null;
    if (session != null) {
      await _storage.deleteGroup(StorageArea.sessions, session.id);
    }
  }

  T _unwrap<T>(Result<T> result) => switch (result) {
    Success<T>(:final value) => value,
    Err<T>(:final failure) => throw FailureException(failure),
  };
}

final scanSessionProvider =
    NotifierProvider<ScanSessionController, ScanSession?>(
      ScanSessionController.new,
    );
