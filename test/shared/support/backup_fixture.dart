import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:md_scanner/core/services/app_logger.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/services/backup_service.dart';
import 'package:path/path.dart' as p;

import 'library_harness.dart';

typedef SeededLibrary = ({
  FolderEntity house,
  FolderEntity works,
  DocumentEntity lease,
  DocumentEntity note,
  DocumentEntity old,
  DocumentEntity secret,
});

/// Two nested folders, a scanned and tagged favorite with page-level OCR, a
/// text note, a trashed document and a vault document carrying everything a
/// backup must leave behind (tag, favorite, OCR text, thumbnail, page).
Future<SeededLibrary> seedLibrary(LibraryHarness lib) async {
  final repository = lib.repository;
  final house = valueOf(await repository.createFolder('Maison'));
  final works = valueOf(
    await repository.createFolder('Travaux', parentId: house.id),
  );

  final lease = await lib.addDocument(
    'Bail',
    folderId: house.id,
    size: 300,
    pages: 2,
    thumbnail: true,
  );
  await repository.setFavorite(lease.id, favorite: true);
  await repository.setTags(lease.id, ['Logement', 'Banque']);
  await lib.ocr.save(
    documentId: lease.id,
    text: 'Entre les soussignés',
    pageIndex: 0,
  );
  await lib.ocr.save(
    documentId: lease.id,
    text: 'Fait à Cotonou',
    pageIndex: 1,
  );

  final note = await lib.addDocument(
    'Note',
    type: DocumentFileType.txt,
    size: 50,
    source: DocumentSource.ocr,
  );
  await repository.setTags(note.id, ['Banque']);
  await lib.ocr.save(
    documentId: note.id,
    text: 'Penser au virement',
    language: 'fr',
  );

  final old = await lib.addDocument('Vieux', folderId: works.id, size: 70);
  await repository.moveToTrash([old.id]);

  final secret = await lib.moveToVault(
    await lib.addDocument(
      'Secret',
      folderId: works.id,
      size: 90,
      pages: 1,
      thumbnail: true,
    ),
  );
  await repository.setTags(secret.id, ['Privé']);
  await repository.setFavorite(secret.id, favorite: true);
  await lib.ocr.save(documentId: secret.id, text: 'code du coffre 4521');

  return (
    house: house,
    works: works,
    lease: valueOf(await repository.getById(lease.id)),
    note: note,
    old: valueOf(await repository.getById(old.id)),
    secret: valueOf(await repository.getById(secret.id)),
  );
}

BackupService backupServiceFor(LibraryHarness lib, {AppLogger? logger}) =>
    BackupService(
      db: lib.db,
      storage: lib.storage,
      logger: logger ?? AppLogger(),
      clock: () => DateTime.utc(2026, 11, 27, 9, 30),
      onLibraryChanged: lib.repository.notifyChanged,
    );

String exportPathOf(LibraryHarness lib, [String name = 'backup.zip']) =>
    p.join(lib.storage.directoryOf(StorageArea.exports).path, name);

/// Everything a restore must bring back, described without storage paths
/// (a restore allocates new ones): rows, relations and the bytes themselves.
Future<Map<String, Object?>> snapshotOf(LibraryHarness lib) async {
  final repository = lib.repository;
  final folders = <String, String>{};
  Future<void> walk(String? parentId) async {
    for (final folder in valueOf(
      await repository.folders(parentId: parentId),
    )) {
      folders[folder.id] =
          '${folder.name}|${folder.parentId}|${folder.createdAt}|'
          '${folder.updatedAt}|${folder.documentCount}';
      await walk(folder.id);
    }
  }

  await walk(null);
  final documents = [
    ...valueOf(await repository.query(const DocumentQuery())),
    ...valueOf(await repository.query(const DocumentQuery(inTrash: true))),
  ]..sort((a, b) => a.id.compareTo(b.id));

  Future<List<int>> bytes(String path) => lib.storage.file(path).readAsBytes();
  return {
    'folders': folders,
    'documents': [
      for (final document in documents)
        {
          'id': document.id,
          'name': document.name,
          'type': document.fileType,
          'size': document.fileSize,
          'pageCount': document.pageCount,
          'folder': document.folderId,
          'source': document.source,
          'createdAt': document.createdAt,
          'updatedAt': document.updatedAt,
          'favorite': document.isFavorite,
          'encrypted': document.isEncrypted,
          'deletedAt': document.deletedAt,
          'bytes': await bytes(document.filePath),
          'thumbnail': document.thumbnailPath == null
              ? null
              : await bytes(document.thumbnailPath!),
          'pages': [
            for (final page in valueOf(await repository.pagesOf(document.id)))
              await bytes(page.imagePath),
          ],
          'tags': [
            for (final tag in valueOf(await repository.tagsOf(document.id)))
              tag.name,
          ],
          'ocr': valueOf(await lib.ocr.textOf(document.id)),
        },
    ],
  };
}

/// Every stored file a row points at, to prove no row dangles and no file
/// is left behind.
Future<Set<String>> referencedFilesOf(LibraryHarness lib) async {
  final rows = await lib.db.rawQuery(
    'SELECT file_path AS path FROM documents '
    'UNION SELECT thumbnail_path FROM documents '
    'WHERE thumbnail_path IS NOT NULL '
    'UNION SELECT image_path FROM document_pages',
  );
  return {for (final row in rows) row['path']! as String};
}

Future<Set<String>> storedLibraryFilesOf(LibraryHarness lib) async => {
  for (final area in const [
    StorageArea.documents,
    StorageArea.pages,
    StorageArea.thumbnails,
    StorageArea.vault,
  ])
    ...await lib.filesIn(area),
};

Archive readArchive(String path) =>
    ZipDecoder().decodeBytes(File(path).readAsBytesSync());

String textOfEntry(Archive archive, String name) =>
    utf8.decode(archive.find(name)!.content);

int _tamperedArchives = 0;

/// Writes a copy of the archive at [path] after applying [edit] to it, next
/// to the original and under a name of its own.
String tamperArchive(
  String path,
  void Function(Archive archive) edit, {
  String? name,
}) {
  final archive = readArchive(path);
  edit(archive);
  final target = p.join(
    p.dirname(path),
    name ?? 'tampered_${_tamperedArchives++}.zip',
  );
  File(target).writeAsBytesSync(ZipEncoder().encodeBytes(archive));
  return target;
}

void rewriteEntry(
  Archive archive,
  String name,
  String Function(String text) change,
) => archive.add(ArchiveFile.string(name, change(textOfEntry(archive, name))));
