import 'package:equatable/equatable.dart';

enum DocumentFileType {
  pdf('pdf', 'application/pdf'),
  jpg('jpg', 'image/jpeg'),
  png('png', 'image/png'),
  txt('txt', 'text/plain'),
  docx(
    'docx',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  );

  const DocumentFileType(this.extension, this.mimeType);

  /// Canonical extension, also the value stored in SQLite.
  final String extension;
  final String mimeType;

  bool get isImage => this == jpg || this == png;

  /// Accepts `pdf`, `.PDF`, `jpeg`… Returns null for unsupported formats.
  static DocumentFileType? fromExtension(String extension) {
    final normalized = extension.replaceFirst('.', '').toLowerCase();
    if (normalized == 'jpeg') return jpg;
    for (final type in values) {
      if (type.extension == normalized) return type;
    }
    return null;
  }
}

enum DocumentSource {
  scan('scan'),
  import('import'),
  pdfTool('pdf_tool'),
  ocr('ocr'),
  idScan('id_scan'),
  generated('generated');

  const DocumentSource(this.dbValue);

  final String dbValue;

  static DocumentSource fromDb(String value) => values.firstWhere(
    (source) => source.dbValue == value,
    orElse: () => DocumentSource.import,
  );
}

class DocumentEntity extends Equatable {
  const DocumentEntity({
    required this.id,
    required this.name,
    required this.filePath,
    required this.fileType,
    required this.fileSize,
    required this.createdAt,
    required this.updatedAt,
    this.pageCount,
    this.thumbnailPath,
    this.folderId,
    this.source = DocumentSource.import,
    this.isFavorite = false,
    this.isEncrypted = false,
    this.isInVault = false,
    this.deletedAt,
  });

  final String id;

  /// Display name, without extension.
  final String name;

  /// Path relative to the storage root (see FileStorage).
  final String filePath;
  final DocumentFileType fileType;
  final int fileSize;
  final int? pageCount;
  final String? thumbnailPath;
  final String? folderId;
  final DocumentSource source;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isFavorite;
  final bool isEncrypted;
  final bool isInVault;

  /// Non-null when the document sits in the trash.
  final DateTime? deletedAt;

  bool get isInTrash => deletedAt != null;

  String get fileName => '$name.${fileType.extension}';

  DocumentEntity copyWith({
    String? name,
    String? filePath,
    DocumentFileType? fileType,
    int? fileSize,
    int? Function()? pageCount,
    String? Function()? thumbnailPath,
    String? Function()? folderId,
    DateTime? updatedAt,
    bool? isFavorite,
    bool? isEncrypted,
    bool? isInVault,
    DateTime? Function()? deletedAt,
  }) {
    return DocumentEntity(
      id: id,
      name: name ?? this.name,
      filePath: filePath ?? this.filePath,
      fileType: fileType ?? this.fileType,
      fileSize: fileSize ?? this.fileSize,
      pageCount: pageCount != null ? pageCount() : this.pageCount,
      thumbnailPath: thumbnailPath != null
          ? thumbnailPath()
          : this.thumbnailPath,
      folderId: folderId != null ? folderId() : this.folderId,
      source: source,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      isInVault: isInVault ?? this.isInVault,
      deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    filePath,
    fileType,
    fileSize,
    pageCount,
    thumbnailPath,
    folderId,
    source,
    createdAt,
    updatedAt,
    isFavorite,
    isEncrypted,
    isInVault,
    deletedAt,
  ];
}

/// Data needed to register a file that already sits inside the app storage.
class NewDocument extends Equatable {
  const NewDocument({
    required this.name,
    required this.filePath,
    required this.fileType,
    required this.source,
    this.pageCount,
    this.thumbnailPath,
    this.folderId,
    this.pageImagePaths = const [],
  });

  final String name;
  final String filePath;
  final DocumentFileType fileType;
  final DocumentSource source;
  final int? pageCount;
  final String? thumbnailPath;
  final String? folderId;

  /// Relative paths of the page images backing a scanned document, in order.
  final List<String> pageImagePaths;

  @override
  List<Object?> get props => [
    name,
    filePath,
    fileType,
    source,
    pageCount,
    thumbnailPath,
    folderId,
    pageImagePaths,
  ];
}

class DocumentPage extends Equatable {
  const DocumentPage({
    required this.id,
    required this.documentId,
    required this.pageOrder,
    required this.imagePath,
    required this.createdAt,
  });

  final String id;
  final String documentId;
  final int pageOrder;
  final String imagePath;
  final DateTime createdAt;

  @override
  List<Object?> get props => [id, documentId, pageOrder, imagePath, createdAt];
}

class FolderEntity extends Equatable {
  const FolderEntity({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.parentId,
    this.documentCount = 0,
  });

  final String id;
  final String name;
  final String? parentId;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Number of non-deleted documents directly inside the folder.
  final int documentCount;

  @override
  List<Object?> get props => [
    id,
    name,
    parentId,
    createdAt,
    updatedAt,
    documentCount,
  ];
}

class TagEntity extends Equatable {
  const TagEntity({required this.id, required this.name});

  final String id;
  final String name;

  @override
  List<Object?> get props => [id, name];
}

enum DocumentSortField { name, date, size }

class DocumentSort extends Equatable {
  const DocumentSort(this.field, {this.ascending = false});

  static const DocumentSort newestFirst = DocumentSort(DocumentSortField.date);

  final DocumentSortField field;
  final bool ascending;

  @override
  List<Object?> get props => [field, ascending];
}

/// Which documents a list wants. Defaults: every live, non-vault document.
class DocumentQuery extends Equatable {
  const DocumentQuery({
    this.folderId,
    this.restrictToFolder = false,
    this.search,
    this.favoritesOnly = false,
    this.inVault = false,
    this.inTrash = false,
    this.tagId,
    this.types,
    this.sort = DocumentSort.newestFirst,
    this.limit,
  });

  /// Only used when [restrictToFolder] is true; null then means "root".
  final String? folderId;
  final bool restrictToFolder;

  /// Matches the document name and its saved OCR text, case-insensitively.
  final String? search;
  final bool favoritesOnly;
  final bool inVault;
  final bool inTrash;
  final String? tagId;
  final Set<DocumentFileType>? types;
  final DocumentSort sort;
  final int? limit;

  @override
  List<Object?> get props => [
    folderId,
    restrictToFolder,
    search,
    favoritesOnly,
    inVault,
    inTrash,
    tagId,
    types,
    sort,
    limit,
  ];
}
