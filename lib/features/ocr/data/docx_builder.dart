import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Builds a minimal, valid Word document (OOXML) from plain text.
///
/// Blank lines separate paragraphs, single line breaks are preserved, and
/// a form feed (`\f`) starts a new page — the OCR service puts one between
/// the pages of a multi-page document.
Uint8List buildDocx({required String text, String title = ''}) {
  final archive = Archive()
    ..addFile(ArchiveFile.string('[Content_Types].xml', _contentTypes))
    ..addFile(ArchiveFile.string('_rels/.rels', _rootRelationships))
    ..addFile(ArchiveFile.string('docProps/core.xml', _coreProperties(title)))
    ..addFile(ArchiveFile.string('word/document.xml', _document(text)));
  return ZipEncoder().encodeBytes(archive);
}

String _escape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    // Control characters are illegal in XML 1.0 (tab and newline are handled
    // by the caller before escaping).
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

String _document(String text) {
  final body = StringBuffer();
  final pages = text.replaceAll('\r\n', '\n').split('\f');
  for (var p = 0; p < pages.length; p++) {
    final paragraphs = pages[p].trim().split(RegExp(r'\n\s*\n'));
    for (var i = 0; i < paragraphs.length; i++) {
      body.write('<w:p>');
      if (p > 0 && i == 0) body.write('<w:r><w:br w:type="page"/></w:r>');
      final lines = paragraphs[i].split('\n');
      for (var l = 0; l < lines.length; l++) {
        body.write('<w:r>');
        if (l > 0) body.write('<w:br/>');
        body.write(
          '<w:t xml:space="preserve">${_escape(lines[l].replaceAll('\t', ' '))}</w:t></w:r>',
        );
      }
      body.write('</w:p>');
    }
  }
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>$body<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
      '<w:pgMar w:top="1417" w:right="1417" w:bottom="1417" w:left="1417" '
      'w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body></w:document>';
}

String _coreProperties(String title) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<cp:coreProperties '
    'xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
    'xmlns:dc="http://purl.org/dc/elements/1.1/">'
    '<dc:title>${_escape(title)}</dc:title><dc:creator>MD SCANNER</dc:creator>'
    '</cp:coreProperties>';

const String _contentTypes =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
    '</Types>';

const String _rootRelationships =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
    '</Relationships>';
