import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';

/// Authenticated file encryption, AES-256-GCM in chunks so a large PDF is
/// never held in memory.
///
/// Container layout:
/// ```
/// header : "MDSV" | version (1) | chunk size (4, big endian) | base nonce (8)
/// chunk  : ciphertext | GCM tag (16)        repeated, the last one is "final"
/// ```
/// The nonce of chunk `i` is `base nonce | i` (4 bytes). The associated data
/// of each chunk binds the header, the chunk index and a "final chunk" flag,
/// so tampering, reordering and truncation all fail authentication.
class FileCipher {
  FileCipher({this.chunkSize = 1 << 20, Random? random})
    : _random = random ?? Random.secure();

  /// Plaintext bytes per chunk.
  final int chunkSize;
  final Random _random;

  static const List<int> _magic = [0x4D, 0x44, 0x53, 0x56];
  static const int _version = 1;
  static const int _headerLength = 17;
  static const int _tagLength = 16;

  final AesGcm _aes = AesGcm.with256bits();

  Future<Result<void>> encryptFile({
    required String sourcePath,
    required String destinationPath,
    required List<int> key,
    void Function(double fraction)? onProgress,
  }) => _atomic(destinationPath, SecurityFailureKind.encryptionFailed, (
    output,
  ) async {
    final source = File(sourcePath);
    final total = await source.length();
    final header = Uint8List(_headerLength)
      ..setAll(0, _magic)
      ..[4] = _version;
    ByteData.sublistView(header).setUint32(5, chunkSize);
    for (var i = 9; i < _headerLength; i++) {
      header[i] = _random.nextInt(256);
    }
    await output.writeFrom(header);

    final secretKey = SecretKey(key);
    final input = await source.open();
    try {
      var index = 0;
      var done = 0;
      while (true) {
        final chunk = await input.read(chunkSize);
        done += chunk.length;
        final isFinal = done >= total;
        final box = await _aes.encrypt(
          chunk,
          secretKey: secretKey,
          nonce: _nonce(header, index),
          aad: _aad(header, index, isFinal),
        );
        await output.writeFrom(box.cipherText);
        await output.writeFrom(box.mac.bytes);
        onProgress?.call(total == 0 ? 1 : done / total);
        index++;
        if (isFinal) break;
      }
    } finally {
      await input.close();
    }
  });

  Future<Result<void>> decryptFile({
    required String sourcePath,
    required String destinationPath,
    required List<int> key,
    void Function(double fraction)? onProgress,
  }) => _atomic(destinationPath, SecurityFailureKind.decryptionFailed, (
    output,
  ) async {
    final source = File(sourcePath);
    final total = await source.length();
    final input = await source.open();
    try {
      final header = await input.read(_headerLength);
      if (header.length != _headerLength ||
          !_startsWithMagic(header) ||
          header[4] != _version) {
        throw const _Corrupted();
      }
      final size = ByteData.sublistView(header).getUint32(5);
      if (size == 0 || size > (64 << 20)) throw const _Corrupted();

      final secretKey = SecretKey(key);
      var position = _headerLength;
      var index = 0;
      while (true) {
        final sealed = await input.read(size + _tagLength);
        if (sealed.length < _tagLength) throw const _Corrupted();
        position += sealed.length;
        final isFinal = position >= total;
        final split = sealed.length - _tagLength;
        final clear = await _aes.decrypt(
          SecretBox(
            Uint8List.sublistView(sealed, 0, split),
            nonce: _nonce(header, index),
            mac: Mac(Uint8List.sublistView(sealed, split)),
          ),
          secretKey: secretKey,
          aad: _aad(header, index, isFinal),
        );
        await output.writeFrom(clear);
        onProgress?.call(position / total);
        index++;
        if (isFinal) break;
      }
    } finally {
      await input.close();
    }
  });

  bool _startsWithMagic(List<int> header) {
    for (var i = 0; i < _magic.length; i++) {
      if (header[i] != _magic[i]) return false;
    }
    return true;
  }

  Uint8List _nonce(List<int> header, int index) {
    final nonce = Uint8List(12)..setRange(0, 8, header, 9);
    ByteData.sublistView(nonce).setUint32(8, index);
    return nonce;
  }

  Uint8List _aad(List<int> header, int index, bool isFinal) {
    final aad = Uint8List(_headerLength + 5)..setAll(0, header);
    ByteData.sublistView(aad).setUint32(_headerLength, index);
    aad[_headerLength + 4] = isFinal ? 1 : 0;
    return aad;
  }

  /// Writes to a temporary name, then renames: a failure never leaves a
  /// partial file at [destinationPath].
  Future<Result<void>> _atomic(
    String destinationPath,
    SecurityFailureKind failureKind,
    Future<void> Function(RandomAccessFile output) body,
  ) async {
    final partial = File('$destinationPath.part');
    try {
      await partial.parent.create(recursive: true);
      final output = await partial.open(mode: FileMode.write);
      try {
        await body(output);
        await output.flush();
      } finally {
        await output.close();
      }
      await partial.rename(destinationPath);
      return const Success(null);
    } catch (error) {
      if (await partial.exists()) await partial.delete();
      if (error is SecretBoxAuthenticationError || error is _Corrupted) {
        return Err(SecurityFailure(failureKind));
      }
      if (error is FileSystemException) return Err(failureFromError(error));
      return Err(
        SecurityFailure(
          failureKind,
          debugMessage: error.runtimeType.toString(),
        ),
      );
    }
  }
}

class _Corrupted implements Exception {
  const _Corrupted();
}
