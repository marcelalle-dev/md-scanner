import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/storage/database/app_database.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/features/ocr/data/docx_builder.dart';
import 'package:md_scanner/features/ocr/domain/ocr_service.dart';
import 'package:md_scanner/features/ocr/domain/text_recognition.dart';
import 'package:md_scanner/features/pdf_tools/domain/pdf_engine.dart';
import 'package:md_scanner/features/pdf_tools/domain/pdf_models.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/repositories/sqlite_document_repository.dart';
import 'package:md_scanner/shared/repositories/sqlite_ocr_text_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../helpers/test_database.dart';

class _FakeRecognizer implements TextRecognitionService {
  final Map<String, String> textByFileName = {};
  final List<String> calls = [];

  @override
  Future<Result<OcrPage>> recognize(String imagePath) async {
    calls.add(p.basename(imagePath));
    return Success(OcrPage(text: textByFileName[p.basename(imagePath)] ?? ''));
  }

  @override
  Future<void> dispose() async {}
}

class _MockPdfEngine extends Mock implements PdfEngine {}

String _part(Archive archive, String name) =>
    utf8.decode(archive.findFile(name)!.content as List<int>);

void main() {
  group('TextSearch', () {
    test('ignores case and accents and keeps offsets', () {
      const text = 'Reçu numéro 12. Le RECU est payé.';

      expect(TextSearch.findAll(text, 'recu'), [0, 19]);
      expect(TextSearch.findAll(text, 'NUMERO'), [5]);
      expect(TextSearch.findAll(text, 'absent'), isEmpty);
      expect(TextSearch.findAll(text, '   '), isEmpty);
      expect(TextSearch.fold(text).length, text.length);
    });
  });

  group('buildDocx', () {
    test('produces the required OOXML parts', () {
      final archive = ZipDecoder().decodeBytes(
        buildDocx(text: 'Bonjour', title: 'Facture'),
      );

      for (final name in [
        '[Content_Types].xml',
        '_rels/.rels',
        'word/document.xml',
        'docProps/core.xml',
      ]) {
        expect(archive.findFile(name), isNotNull, reason: name);
        XmlDocument.parse(_part(archive, name));
      }
      expect(
        _part(archive, '[Content_Types].xml'),
        contains('wordprocessingml'),
      );
      expect(_part(archive, '_rels/.rels'), contains('word/document.xml'));
      expect(_part(archive, 'docProps/core.xml'), contains('Facture'));
    });

    test('keeps paragraphs, line breaks, pages and special characters', () {
      const text = 'Tom & Léa <3 "ok"\nligne 2\n\nParagraphe 2 😀\fPage 2';
      final document = XmlDocument.parse(
        _part(
          ZipDecoder().decodeBytes(buildDocx(text: text)),
          'word/document.xml',
        ),
      );

      final paragraphs = document.findAllElements('w:p').toList();
      expect(paragraphs, hasLength(3));
      expect(paragraphs[0].findAllElements('w:t').map((t) => t.innerText), [
        'Tom & Léa <3 "ok"',
        'ligne 2',
      ]);
      expect(paragraphs[0].findAllElements('w:br'), hasLength(1));
      expect(paragraphs[1].innerText, 'Paragraphe 2 😀');
      final pageBreak = paragraphs[2].findAllElements('w:br').single;
      expect(pageBreak.getAttribute('w:type'), 'page');
      expect(paragraphs[2].innerText, 'Page 2');
    });
  });

  group('OcrService', () {
    late AppDatabase database;
    late FileStorage storage;
    late SqliteDocumentRepository documents;
    late _FakeRecognizer recognizer;
    late _MockPdfEngine pdf;
    late OcrService service;

    setUpAll(() => registerFallbackValue(PdfImageFormat.jpeg));

    setUp(() async {
      database = await openTestDatabase();
      storage = await createTestStorage();
      documents = SqliteDocumentRepository(db: database.db, storage: storage);
      recognizer = _FakeRecognizer();
      pdf = _MockPdfEngine();
      service = OcrService(
        recognizer: recognizer,
        pdfEngine: pdf,
        storage: storage,
        texts: SqliteOcrTextRepository(db: database.db),
        documents: documents,
      );
    });

    tearDown(() async {
      await documents.dispose();
      await database.close();
      await storage.root.delete(recursive: true);
    });

    Future<DocumentEntity> register(DocumentFileType type) async {
      final path = await storage.writeBytes(
        StorageArea.documents,
        utf8.encode('x'),
        extension: type.extension,
      );
      return (await documents.register(
        NewDocument(
          name: 'Courrier',
          filePath: path,
          fileType: type,
          source: DocumentSource.scan,
        ),
      )).valueOrNull!;
    }

    test('recognizes an image and stores the corrected text', () async {
      final image = await register(DocumentFileType.jpg);
      recognizer.textByFileName[p.basename(image.filePath)] = ' Bonjour \n';

      final text = (await service.recognize(image)).valueOrNull;
      expect(text, 'Bonjour');

      await service.saveText(image.id, 'Bonjour corrigé');
      await service.saveText(image.id, 'Version finale');
      expect((await service.savedText(image.id)).valueOrNull, 'Version finale');

      final found = await documents.query(
        const DocumentQuery(search: 'finale'),
      );
      expect(found.valueOrNull!.single.id, image.id);
    });

    test('recognizes a PDF page by page and cleans its work files', () async {
      final document = await register(DocumentFileType.pdf);
      when(
        () => pdf.pdfToImages(
          path: any(named: 'path'),
          outputDirectory: any(named: 'outputDirectory'),
          format: any(named: 'format'),
          dpi: any(named: 'dpi'),
          pages: any(named: 'pages'),
          jpegQuality: any(named: 'jpegQuality'),
          password: any(named: 'password'),
          onProgress: any(named: 'onProgress'),
          isCancelled: any(named: 'isCancelled'),
        ),
      ).thenAnswer((invocation) async {
        final directory = invocation.namedArguments[#outputDirectory] as String;
        final pages = <RenderedPage>[];
        for (var i = 0; i < 3; i++) {
          final file = File(p.join(directory, 'page$i.jpg'));
          await file.writeAsBytes([1]);
          pages.add(
            RenderedPage(pageIndex: i, path: file.path, width: 1, height: 1),
          );
        }
        return Success(pages);
      });
      recognizer.textByFileName.addAll({
        'page0.jpg': 'Un',
        'page1.jpg': '',
        'page2.jpg': 'Trois',
      });
      final progress = <int>[];

      final text = (await service.recognize(
        document,
        onProgress: (done, total) => progress.add(done),
      )).valueOrNull!;

      expect(text.split(kOcrPageBreak).map((page) => page.trim()), [
        'Un',
        '',
        'Trois',
      ]);
      expect(recognizer.calls, ['page0.jpg', 'page1.jpg', 'page2.jpg']);
      expect(progress, [1, 2, 3]);
      expect(await storage.usedBytes(StorageArea.temp), 0);
    });

    test('reports when no text was found', () async {
      final image = await register(DocumentFileType.png);

      final result = await service.recognize(image);

      expect(
        result.failureOrNull,
        const OcrFailure(OcrFailureKind.noTextFound),
      );
    });

    test('exports TXT and DOCX documents to the library', () async {
      final txt = (await service.exportTxt(
        'Notes: 1',
        'Ligne\r\nDeux',
      )).valueOrNull!;
      final docx = (await service.exportDocx('Notes', 'Texte')).valueOrNull!;

      expect(txt.fileType, DocumentFileType.txt);
      expect(txt.source, DocumentSource.ocr);
      expect(txt.name, 'Notes 1');
      expect(await storage.file(txt.filePath).readAsString(), 'Ligne\nDeux');
      expect(docx.fileType, DocumentFileType.docx);
      final archive = ZipDecoder().decodeBytes(
        await storage.file(docx.filePath).readAsBytes(),
      );
      expect(_part(archive, 'word/document.xml'), contains('Texte'));
    });
  });
}
