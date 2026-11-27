/// Ordered schema migrations. The database version is `kMigrations.length`.
///
/// Rules:
/// - never edit a migration that has shipped: append a new one;
/// - every statement must be idempotent-safe inside a transaction;
/// - timestamps are stored as UTC epoch milliseconds (INTEGER);
/// - file paths are stored RELATIVE to the app storage root (see FileStorage),
///   so they stay valid across restarts, updates and backup restores.
const List<List<String>> kMigrations = [_v1];

const List<String> _v1 = [
  '''
  CREATE TABLE folders (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL CHECK (length(trim(name)) > 0),
    parent_id TEXT REFERENCES folders(id) ON DELETE CASCADE,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE UNIQUE INDEX idx_folders_parent_name
    ON folders (IFNULL(parent_id, ''), name COLLATE NOCASE)
  ''',
  '''
  CREATE TABLE documents (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL CHECK (length(trim(name)) > 0),
    file_path TEXT NOT NULL,
    file_type TEXT NOT NULL
      CHECK (file_type IN ('pdf', 'jpg', 'png', 'txt', 'docx')),
    file_size INTEGER NOT NULL DEFAULT 0 CHECK (file_size >= 0),
    page_count INTEGER CHECK (page_count IS NULL OR page_count >= 0),
    thumbnail_path TEXT,
    folder_id TEXT REFERENCES folders(id) ON DELETE SET NULL,
    source TEXT NOT NULL DEFAULT 'import'
      CHECK (source IN ('scan', 'import', 'pdf_tool', 'ocr', 'id_scan', 'generated')),
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    is_favorite INTEGER NOT NULL DEFAULT 0 CHECK (is_favorite IN (0, 1)),
    is_encrypted INTEGER NOT NULL DEFAULT 0 CHECK (is_encrypted IN (0, 1)),
    is_in_vault INTEGER NOT NULL DEFAULT 0 CHECK (is_in_vault IN (0, 1)),
    deleted_at INTEGER
  )
  ''',
  'CREATE INDEX idx_documents_folder ON documents (folder_id)',
  'CREATE INDEX idx_documents_deleted ON documents (deleted_at)',
  'CREATE INDEX idx_documents_updated ON documents (updated_at DESC)',
  'CREATE INDEX idx_documents_name ON documents (name COLLATE NOCASE)',
  'CREATE INDEX idx_documents_vault ON documents (is_in_vault)',
  '''
  CREATE TABLE document_pages (
    id TEXT PRIMARY KEY NOT NULL,
    document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    page_order INTEGER NOT NULL CHECK (page_order >= 0),
    image_path TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    UNIQUE (document_id, page_order)
  )
  ''',
  '''
  CREATE TABLE ocr_results (
    id TEXT PRIMARY KEY NOT NULL,
    document_id TEXT REFERENCES documents(id) ON DELETE CASCADE,
    page_index INTEGER,
    extracted_text TEXT NOT NULL,
    language TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )
  ''',
  'CREATE INDEX idx_ocr_results_document ON ocr_results (document_id)',
  '''
  CREATE TABLE scan_history (
    id TEXT PRIMARY KEY NOT NULL,
    document_id TEXT REFERENCES documents(id) ON DELETE SET NULL,
    scan_type TEXT NOT NULL,
    page_count INTEGER NOT NULL DEFAULT 1 CHECK (page_count >= 0),
    created_at INTEGER NOT NULL
  )
  ''',
  'CREATE INDEX idx_scan_history_created ON scan_history (created_at DESC)',
  '''
  CREATE TABLE scan_sessions (
    id TEXT PRIMARY KEY NOT NULL,
    mode TEXT NOT NULL,
    payload TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE qr_history (
    id TEXT PRIMARY KEY NOT NULL,
    content TEXT NOT NULL,
    format TEXT NOT NULL,
    kind TEXT NOT NULL DEFAULT 'scanned' CHECK (kind IN ('scanned', 'generated')),
    scanned_at INTEGER NOT NULL
  )
  ''',
  'CREATE INDEX idx_qr_history_scanned ON qr_history (scanned_at DESC)',
  '''
  CREATE TABLE favorites (
    id TEXT PRIMARY KEY NOT NULL,
    document_id TEXT NOT NULL UNIQUE REFERENCES documents(id) ON DELETE CASCADE,
    created_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TRIGGER trg_favorites_insert AFTER INSERT ON favorites
  BEGIN
    UPDATE documents SET is_favorite = 1 WHERE id = NEW.document_id;
  END
  ''',
  '''
  CREATE TRIGGER trg_favorites_delete AFTER DELETE ON favorites
  BEGIN
    UPDATE documents SET is_favorite = 0 WHERE id = OLD.document_id;
  END
  ''',
  '''
  CREATE TABLE tags (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL UNIQUE COLLATE NOCASE CHECK (length(trim(name)) > 0),
    created_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE document_tags (
    document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (document_id, tag_id)
  )
  ''',
  'CREATE INDEX idx_document_tags_tag ON document_tags (tag_id)',
  '''
  CREATE TABLE app_settings (
    key TEXT PRIMARY KEY NOT NULL,
    value TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE subscription_cache (
    product_id TEXT PRIMARY KEY NOT NULL,
    state TEXT NOT NULL,
    verification_source TEXT NOT NULL,
    purchase_token_hash TEXT,
    expiration_date INTEGER,
    last_verified_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE ai_usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    feature TEXT NOT NULL,
    created_at INTEGER NOT NULL
  )
  ''',
  'CREATE INDEX idx_ai_usage_created ON ai_usage (created_at)',
];
