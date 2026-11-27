import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/features/pdf_tools/data/pdf_encryptor.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart' as pdfium;

import '../helpers/pdf_fixtures.dart';

Future<pdfium.PdfDocument> _open(String path, [String? password]) =>
    pdfium.PdfDocument.openFile(
      path,
      passwordProvider: pdfium.createSimplePasswordProvider(password),
    );

void main() {
  late Directory dir;

  setUpAll(() async {
    await initPdfiumForTests();
    dir = await Directory.systemTemp.createTemp('mds_encryptor_');
  });

  tearDownAll(() => dir.delete(recursive: true));

  group('validatePdfPassword', () {
    test('accepts 1 to 127 UTF-8 bytes', () {
      expect(validatePdfPassword('a'), isNull);
      expect(validatePdfPassword('x' * 127), isNull);
      expect(validatePdfPassword('é' * 63), isNull);
    });

    test('rejects empty and oversized passwords', () {
      expect(
        validatePdfPassword(''),
        const ValidationFailure('pdf_password_empty'),
      );
      expect(
        validatePdfPassword('x' * 128),
        const ValidationFailure('pdf_password_too_long'),
      );
      expect(
        validatePdfPassword('é' * 64),
        const ValidationFailure('pdf_password_too_long'),
      );
    });
  });

  group('PdfAes256Material', () {
    test('builds strings of the lengths required by ISO 32000-2', () {
      final material = PdfAes256Material.generate(
        userPassword: utf8.encode('user'),
        ownerPassword: utf8.encode('owner'),
        random: Random(7),
      );
      expect(material.fileKey, hasLength(32));
      expect(material.u, hasLength(48));
      expect(material.o, hasLength(48));
      expect(material.ue, hasLength(32));
      expect(material.oe, hasLength(32));
      expect(material.perms, hasLength(16));
    });

    test('the user and owner keys both unwrap the same file key', () {
      final material = PdfAes256Material.generate(
        userPassword: utf8.encode('user'),
        ownerPassword: utf8.encode('owner'),
        random: Random(11),
      );
      final zeroIv = Uint8List(16);
      final userKey = pdfHash2B(
        utf8.encode('user'),
        material.u.sublist(40, 48),
        const [],
      );
      final ownerKey = pdfHash2B(
        utf8.encode('owner'),
        material.o.sublist(40, 48),
        material.u,
      );
      expect(Aes(userKey).cbcDecrypt(zeroIv, material.ue), material.fileKey);
      expect(Aes(ownerKey).cbcDecrypt(zeroIv, material.oe), material.fileKey);

      final perms = Aes(material.fileKey).cbcDecrypt(zeroIv, material.perms);
      expect(perms.sublist(0, 4), [0xFC, 0xFF, 0xFF, 0xFF]);
      expect(perms.sublist(4, 8), [0xFF, 0xFF, 0xFF, 0xFF]);
      expect(String.fromCharCodes(perms.sublist(8, 12)), 'Tadb');
    });

    test('never reuses a file key or a salt', () {
      final a = PdfAes256Material.generate(
        userPassword: utf8.encode('same'),
        ownerPassword: utf8.encode('same'),
      );
      final b = PdfAes256Material.generate(
        userPassword: utf8.encode('same'),
        ownerPassword: utf8.encode('same'),
      );
      expect(a.fileKey, isNot(b.fileKey));
      expect(a.u, isNot(b.u));
    });
  });

  group('encryptPdfFile', () {
    late String plainPath;
    late String protectedPath;

    setUpAll(() async {
      final document = pw.Document(title: 'Confidential title 4711');
      for (var i = 1; i <= 3; i++) {
        document.addPage(
          pw.Page(build: (context) => pw.Center(child: pw.Text('Secret $i'))),
        );
      }
      plainPath = p.join(dir.path, 'plain.pdf');
      protectedPath = p.join(dir.path, 'protected.pdf');
      await File(plainPath).writeAsBytes(await document.save(), flush: true);
      final result = encryptPdfFile(
        PdfEncryptRequest(
          inputPath: plainPath,
          outputPath: protectedPath,
          userPassword: 'user-pässword',
          ownerPassword: 'owner-password',
        ),
      );
      expect(result, isA<Success<int>>());
      expect(result.valueOrNull, File(protectedPath).lengthSync());
    });

    test('writes an AES-256 revision 6 encryption dictionary', () {
      final bytes = File(protectedPath).readAsBytesSync();
      expect(countOccurrences(bytes, '/Encrypt'), 1);
      expect(countOccurrences(bytes, '/AESV3'), 1);
      expect(countOccurrences(bytes, '/R 6'), 1);
      expect(countOccurrences(bytes, '/V 5'), 1);
      expect(String.fromCharCodes(bytes.take(8)), '%PDF-1.7');
    });

    test('PDFium opens it with the user password', () async {
      final document = await _open(protectedPath, 'user-pässword');
      addTearDown(document.dispose);
      expect(document.isEncrypted, isTrue);
      expect(document.pages, hasLength(3));
      expect(await readPageTexts(protectedPath, password: 'user-pässword'), [
        'Secret 1',
        'Secret 2',
        'Secret 3',
      ]);
    });

    test('PDFium opens it with the owner password', () async {
      final document = await _open(protectedPath, 'owner-password');
      addTearDown(document.dispose);
      expect(document.pages, hasLength(3));
      expect(document.permissions?.securityHandlerRevision, 6);
    });

    test('PDFium refuses it without or with a wrong password', () async {
      await expectLater(
        _open(protectedPath),
        throwsA(isA<pdfium.PdfPasswordException>()),
      );
      await expectLater(
        _open(protectedPath, 'user-password'),
        throwsA(isA<pdfium.PdfPasswordException>()),
      );
    });

    test('no string of the document is left readable', () {
      final plain = File(plainPath).readAsBytesSync();
      final secured = File(protectedPath).readAsBytesSync();
      final plainDoc = CosDocument.open(plain);
      final info = plainDoc.resolve(plainDoc.trailer['Info']) as CosDictionary;
      final title = (info['Title']! as CosString).text;
      expect(title, 'Confidential title 4711');

      expect(
        () => CosDocument.open(secured),
        throwsA(isA<CosPasswordException>()),
      );
      final opened = CosDocument.open(secured, password: 'user-pässword');
      final openedInfo =
          opened.resolve(opened.trailer['Info']) as CosDictionary;
      expect((openedInfo['Title']! as CosString).text, title);
      // The raw file must not contain the title in any of its encodings.
      expect(countOccurrences(secured, title), 0);
      expect(latin1.decode(secured).contains('4711'), isFalse);
    });

    test('refuses an input that is already encrypted', () {
      final result = encryptPdfFile(
        PdfEncryptRequest(
          inputPath: protectedPath,
          outputPath: p.join(dir.path, 'twice.pdf'),
          userPassword: 'a',
          ownerPassword: 'b',
        ),
      );
      expect(
        result.failureOrNull,
        const PdfFailure(PdfFailureKind.passwordRequired),
      );
    });

    test('reports garbage as corrupted', () {
      final garbage = File(p.join(dir.path, 'garbage.pdf'))
        ..writeAsBytesSync(List<int>.generate(4096, (i) => (i * 7) & 0xFF));
      final result = encryptPdfFile(
        PdfEncryptRequest(
          inputPath: garbage.path,
          outputPath: p.join(dir.path, 'garbage_out.pdf'),
          userPassword: 'a',
          ownerPassword: 'b',
        ),
      );
      final failure = result.failureOrNull;
      expect(failure, isA<PdfFailure>());
      expect((failure! as PdfFailure).kind, PdfFailureKind.corrupted);
    });
  });
}
