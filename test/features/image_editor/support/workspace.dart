import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';

import 'synthetic.dart';

/// Temporary directory of one test, with helpers to drop files in it.
class Workspace {
  Workspace._(this.directory);

  static Future<Workspace> create() async => Workspace._(
    await Directory.systemTemp.createTemp('md_scanner_image_test_'),
  );

  final Directory directory;

  String path(String name) => '${directory.path}${Platform.pathSeparator}$name';

  Future<String> write(String name, List<int> bytes) async {
    final file = File(path(name));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Names of every file currently in the directory, sorted.
  List<String> get fileNames {
    final names = [
      for (final entity in directory.listSync())
        if (entity is File) entity.uri.pathSegments.last,
    ]..sort();
    return names;
  }

  Decoded decode(String filePath) =>
      Decoded.bytes(File(filePath).readAsBytesSync());

  Future<void> dispose() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
  }
}

/// Unwraps a success, failing the test with the failure otherwise.
T valueOf<T>(Result<T> result) => switch (result) {
  Success<T>(:final value) => value,
  Err<T>(:final failure) => fail('expected a success, got $failure'),
};

Matcher failsWithImage(ImageFailureKind kind) => isA<Err<Object?>>().having(
  (r) => r.failure,
  'failure',
  isA<ImageFailure>().having((f) => f.kind, 'kind', kind),
);

Matcher failsWithStorage(StorageFailureKind kind) => isA<Err<Object?>>().having(
  (r) => r.failure,
  'failure',
  isA<StorageFailure>().having((f) => f.kind, 'kind', kind),
);

const List<int> pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
const List<int> jpegSignature = [0xFF, 0xD8, 0xFF];

bool hasSignature(List<int> bytes, List<int> signature) {
  if (bytes.length < signature.length) return false;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return false;
  }
  return true;
}

/// A well-formed PNG (signature, 8-bit RGB header, end marker) announcing
/// [width] x [height] without any pixel data: a few bytes claiming to be a
/// huge image.
Uint8List pngHeaderClaiming(int width, int height) {
  final chunk = BytesBuilder()
    ..add('IHDR'.codeUnits)
    ..add(_uint32(width))
    ..add(_uint32(height))
    ..add(const [8, 2, 0, 0, 0]);
  final body = chunk.toBytes();
  return (BytesBuilder()
        ..add(pngSignature)
        ..add(_uint32(13))
        ..add(body)
        ..add(_uint32(_crc32(body)))
        ..add(_uint32(0))
        ..add('IEND'.codeUnits)
        ..add(_uint32(_crc32('IEND'.codeUnits))))
      .toBytes();
}

List<int> _uint32(int value) => [
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}
