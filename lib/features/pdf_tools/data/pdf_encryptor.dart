import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:pdf_cos/pdf_cos.dart';

/// Longest password the standard security handler accepts, in UTF-8 bytes.
const int kPdfPasswordMaxBytes = 127;

/// Every permission granted: bits 1-2 are reserved and must be 0.
const int kPdfAllPermissions = -4;

/// ISO 32000-2 Algorithm 2.B: the hardened hash of security handler
/// revision 6. [udata] is empty for the user password and the 48-byte /U
/// string for the owner password.
Uint8List pdfHash2B(List<int> password, List<int> salt, List<int> udata) {
  var k = Uint8List.fromList(
    sha256.convert([...password, ...salt, ...udata]).bytes,
  );
  for (var round = 1; ; round++) {
    final unit = [...password, ...k, ...udata];
    final k1 = Uint8List(unit.length * 64);
    for (var i = 0; i < 64; i++) {
      k1.setRange(i * unit.length, (i + 1) * unit.length, unit);
    }
    final e = Aes(
      Uint8List.sublistView(k, 0, 16),
    ).cbcEncrypt(Uint8List.sublistView(k, 16, 32), k1);
    // The first 16 bytes read as a big-endian number, modulo 3, equal the
    // sum of those bytes modulo 3 because 256 ≡ 1 (mod 3).
    var sum = 0;
    for (var i = 0; i < 16; i++) {
      sum += e[i];
    }
    final Hash hash = switch (sum % 3) {
      0 => sha256,
      1 => sha384,
      _ => sha512,
    };
    k = Uint8List.fromList(hash.convert(e).bytes);
    if (round >= 64 && e.last <= round - 32) break;
  }
  return Uint8List.fromList(Uint8List.sublistView(k, 0, 32));
}

/// Key material of an AES-256 (V5/R6) encryption dictionary.
class PdfAes256Material {
  PdfAes256Material._({
    required this.fileKey,
    required this.o,
    required this.u,
    required this.oe,
    required this.ue,
    required this.perms,
    required this.permissions,
  });

  /// Runs ISO 32000-2 Algorithms 8 (U, UE), 9 (O, OE) and 10 (Perms) with a
  /// fresh random file key and fresh salts.
  factory PdfAes256Material.generate({
    required List<int> userPassword,
    required List<int> ownerPassword,
    int permissions = kPdfAllPermissions,
    bool encryptMetadata = true,
    Random? random,
  }) {
    final rng = random ?? Random.secure();
    Uint8List randomBytes(int length) =>
        Uint8List.fromList([for (var i = 0; i < length; i++) rng.nextInt(256)]);
    final zeroIv = Uint8List(16);
    final fileKey = randomBytes(32);

    final userValidationSalt = randomBytes(8);
    final userKeySalt = randomBytes(8);
    final u = Uint8List(48)
      ..setAll(0, pdfHash2B(userPassword, userValidationSalt, const []))
      ..setAll(32, userValidationSalt)
      ..setAll(40, userKeySalt);
    final ue = Aes(
      pdfHash2B(userPassword, userKeySalt, const []),
    ).cbcEncrypt(zeroIv, fileKey);

    final ownerValidationSalt = randomBytes(8);
    final ownerKeySalt = randomBytes(8);
    final o = Uint8List(48)
      ..setAll(0, pdfHash2B(ownerPassword, ownerValidationSalt, u))
      ..setAll(32, ownerValidationSalt)
      ..setAll(40, ownerKeySalt);
    final oe = Aes(
      pdfHash2B(ownerPassword, ownerKeySalt, u),
    ).cbcEncrypt(zeroIv, fileKey);

    final p = permissions & 0xFFFFFFFF;
    final block = Uint8List(16)
      ..[0] = p & 0xFF
      ..[1] = (p >> 8) & 0xFF
      ..[2] = (p >> 16) & 0xFF
      ..[3] = (p >> 24) & 0xFF
      ..fillRange(4, 8, 0xFF)
      ..[8] = encryptMetadata ? 0x54 : 0x46
      ..[9] = 0x61
      ..[10] = 0x64
      ..[11] = 0x62
      ..setAll(12, randomBytes(4));
    // A single block: CBC with a zero IV is exactly ECB.
    final perms = Aes(fileKey).cbcEncrypt(zeroIv, block);

    return PdfAes256Material._(
      fileKey: fileKey,
      o: o,
      u: u,
      oe: oe,
      ue: ue,
      perms: perms,
      permissions: permissions,
    );
  }

  final Uint8List fileKey;
  final Uint8List o;
  final Uint8List u;
  final Uint8List oe;
  final Uint8List ue;
  final Uint8List perms;
  final int permissions;

  CosDictionary toEncryptDictionary() => CosDictionary({
    'Filter': const CosName('Standard'),
    'V': const CosInteger(5),
    'R': const CosInteger(6),
    'Length': const CosInteger(256),
    'CF': CosDictionary({
      'StdCF': CosDictionary({
        'CFM': const CosName('AESV3'),
        'AuthEvent': const CosName('DocOpen'),
        'Length': const CosInteger(32),
      }),
    }),
    'StmF': const CosName('StdCF'),
    'StrF': const CosName('StdCF'),
    'O': CosString(o, isHex: true),
    'U': CosString(u, isHex: true),
    'OE': CosString(oe, isHex: true),
    'UE': CosString(ue, isHex: true),
    'Perms': CosString(perms, isHex: true),
    'P': CosInteger(permissions),
  });
}

/// Sendable arguments of [encryptPdfFile].
class PdfEncryptRequest {
  const PdfEncryptRequest({
    required this.inputPath,
    required this.outputPath,
    required this.userPassword,
    required this.ownerPassword,
  });

  final String inputPath;
  final String outputPath;
  final String userPassword;
  final String ownerPassword;
}

/// Checks a password before any work starts.
Failure? validatePdfPassword(String password) {
  if (password.isEmpty) return const ValidationFailure('pdf_password_empty');
  if (utf8.encode(password).length > kPdfPasswordMaxBytes) {
    return const ValidationFailure('pdf_password_too_long');
  }
  return null;
}

/// Rewrites the unencrypted PDF at `inputPath` as an AES-256 protected file
/// at `outputPath` and returns its size. Synchronous and CPU-bound: run it
/// in a background isolate.
///
/// Every indirect object is written again under its own number, with its
/// strings and stream payloads encrypted; object streams and cross-reference
/// streams are replaced by plain objects and a classic table, which every
/// reader supports. Fails with `PdfFailure(passwordRequired)` when the input
/// is already encrypted and `PdfFailure(corrupted)` when the pure-Dart
/// parser cannot process it (the caller may retry on a copy rewritten by
/// PDFium).
Result<int> encryptPdfFile(PdfEncryptRequest request) {
  RandomAccessFile? output;
  try {
    final bytes = File(request.inputPath).readAsBytesSync();
    final CosDocument document;
    try {
      document = CosDocument.open(bytes);
    } on CosPasswordException {
      return const Err(PdfFailure(PdfFailureKind.passwordRequired));
    }
    if (document.isEncrypted) {
      return const Err(PdfFailure(PdfFailureKind.passwordRequired));
    }
    final root = document.trailer['Root'];
    if (root is! CosReference) {
      return const Err(PdfFailure(PdfFailureKind.corrupted));
    }

    final ids = _fileIdentifiers(document);
    final material = PdfAes256Material.generate(
      userPassword: utf8.encode(request.userPassword),
      ownerPassword: utf8.encode(request.ownerPassword),
    );
    final encryptDictionary = material.toEncryptDictionary();
    // Reading the dictionary back with both passwords proves it is
    // self-consistent before a single byte is written.
    final handler = StandardSecurityHandler.fromEncrypt(
      encryptDictionary,
      ids.first,
      request.userPassword,
      _direct,
    );
    StandardSecurityHandler.fromEncrypt(
      encryptDictionary,
      ids.first,
      request.ownerPassword,
      _direct,
    );

    final version = _outputVersion(document.version);
    final numbers = document.objectNumbers.where((n) => n > 0).toList()..sort();
    final offsets = <int, int>{};
    final generations = <int, int>{};
    output = File(request.outputPath).openSync(mode: FileMode.write);
    var position = 0;
    void emit(List<int> data) {
      output!.writeFromSync(data);
      position += data.length;
    }

    emit([...'%PDF-$version\n'.codeUnits, 0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);

    void emitObject(int number, int generation, CosObject object) {
      final buffer = BytesBuilder(copy: false);
      CosSerializer(
        buffer,
        preserveRealPrecision: true,
      ).writeIndirectObject(CosIndirectObject(number, generation, object));
      offsets[number] = position;
      generations[number] = generation;
      emit(buffer.takeBytes());
    }

    var highest = 0;
    for (final number in numbers) {
      final entry = document.xrefEntry(number);
      if (entry == null || entry.type == CosXrefEntryType.free) continue;
      final generation = entry.type == CosXrefEntryType.inUse
          ? entry.generation
          : 0;
      var object = document.getObject(number, generation);
      if (object is CosNull || _isFileStructure(object)) continue;
      if (number == root.objectNumber && object is CosDictionary) {
        object = _withExtensionLevel(object, version);
      }
      final encrypted = handler.encryptObjectGraph(
        object,
        number,
        generation,
        resolve: document.resolve,
        keepsFileCiphertext: (_) => false,
      );
      if (encrypted is CosStream) {
        encrypted.dictionary['Length'] = CosInteger(encrypted.rawBytes.length);
      }
      emitObject(number, generation, encrypted);
      if (number > highest) highest = number;
    }
    if (!offsets.containsKey(root.objectNumber)) {
      return const Err(PdfFailure(PdfFailureKind.corrupted));
    }

    // The encryption dictionary itself is never encrypted.
    final encryptNumber = highest + 1;
    emitObject(encryptNumber, 0, encryptDictionary);

    final tail = BytesBuilder(copy: false);
    final xrefOffset = position;
    final info = document.trailer['Info'];
    CosXrefTableWriter(tail)
      ..writeTable(offsets, (n) => generations[n]!, includeFreeHead: true)
      ..writeTrailer(
        CosDictionary({
          'Size': CosInteger(encryptNumber + 1),
          'Root': root,
          if (info is CosReference && offsets.containsKey(info.objectNumber))
            'Info': info,
          'ID': CosArray([
            CosString(ids.first, isHex: true),
            CosString(ids.last, isHex: true),
          ]),
          'Encrypt': CosReference(encryptNumber, 0),
        }),
      )
      ..writeEpilogue(xrefOffset);
    emit(tail.takeBytes());
    output.flushSync();
    return Success(position);
  } on CosPasswordException {
    return const Err(
      PdfFailure(
        PdfFailureKind.operationFailed,
        debugMessage: 'encrypt.self_check',
      ),
    );
  } on FileSystemException catch (error) {
    return Err(failureFromError(error));
  } on Exception catch (error) {
    return Err(_unreadable(error));
  } on Error catch (error) {
    return Err(_unreadable(error));
  } finally {
    output?.closeSync();
  }
}

Failure _unreadable(Object error) => PdfFailure(
  PdfFailureKind.corrupted,
  debugMessage: 'encrypt.${error.runtimeType}',
);

CosObject _direct(CosObject? object) => object ?? CosNull.instance;

/// Object streams, cross-reference streams and the linearization dictionary
/// describe the layout of the source file, not the document: the rewritten
/// file has its own.
bool _isFileStructure(CosObject object) {
  if (object is CosStream) {
    final type = object.dictionary.typeName;
    return type == 'ObjStm' || type == 'XRef';
  }
  return object is CosDictionary && object.containsKey('Linearized');
}

/// The file identifier pair: kept when the source has one, random otherwise
/// (an encrypted file must carry an /ID).
List<Uint8List> _fileIdentifiers(CosDocument document) {
  final id = document.resolve(document.trailer['ID']);
  if (id is CosArray && id.length >= 2) {
    final first = document.resolve(id[0]);
    final second = document.resolve(id[1]);
    if (first is CosString &&
        second is CosString &&
        first.bytes.isNotEmpty &&
        second.bytes.isNotEmpty) {
      return [first.bytes, second.bytes];
    }
  }
  final rng = Random.secure();
  final fresh = Uint8List.fromList([
    for (var i = 0; i < 16; i++) rng.nextInt(256),
  ]);
  return [fresh, fresh];
}

/// AES-256 belongs to PDF 2.0; files declared older than 1.7 are raised to
/// 1.7 and flagged with Adobe's extension level 8, as other writers do.
String _outputVersion(String sourceVersion) {
  final parsed = double.tryParse(sourceVersion);
  return parsed != null && parsed > 1.7 ? sourceVersion : '1.7';
}

CosDictionary _withExtensionLevel(CosDictionary catalog, String version) {
  final parsed = double.tryParse(version) ?? 1.7;
  if (parsed >= 2.0 || catalog.containsKey('Extensions')) return catalog;
  return CosDictionary({
    ...catalog.entries,
    'Extensions': CosDictionary({
      'ADBE': CosDictionary({
        'BaseVersion': const CosName('1.7'),
        'ExtensionLevel': const CosInteger(8),
      }),
    }),
  });
}
