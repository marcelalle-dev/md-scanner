# Base de données et stockage

MD SCANNER sépare strictement deux choses :

- **SQLite** (`md_scanner.db`) ne contient que des **métadonnées** : noms, chemins, relations, réglages.
- **Le système de fichiers privé** de l'application contient les **octets** : PDF, images, fichiers chiffrés.

Aucun document n'est stocké en BLOB dans SQLite.

## Arborescence des fichiers

Racine : `<documents de l'application>/md_scanner/` (voir `lib/core/storage/file_storage.dart`).

| Zone | Contenu | Durée de vie |
| --- | --- | --- |
| `documents/` | Documents finaux visibles dans la bibliothèque | Jusqu'à suppression définitive |
| `pages/` | Images de pages d'un document numérisé (ré-édition) | Liée au document |
| `thumbnails/` | Vignettes d'aperçu | Liée au document |
| `vault/` | Fichiers chiffrés du coffre-fort | Jusqu'à sortie du coffre ou suppression |
| `sessions/` | Fichiers d'une numérisation en cours (récupérable) | Jusqu'à l'export ou l'abandon |
| `exports/` | Fichiers produits pour un partage | Purgés après 7 jours |
| `temp/` | Fichiers de travail | Purgés au démarrage après 1 jour |

### Chemins relatifs

Les chemins enregistrés en base sont **relatifs à la racine**, toujours avec des barres obliques : `documents/3f2a….pdf`.

La racine absolue peut changer (mise à jour du système, réinstallation, restauration) ; un chemin relatif reste valide. `FileStorage.absolutePath()` refuse tout chemin qui sortirait de la racine (base corrompue ou sauvegarde malveillante).

Les noms de fichiers sur disque sont des UUID : le nom choisi par l'utilisateur ne vit que dans la colonne `documents.name`.

## Schéma (version 1)

Les horodatages sont des entiers : millisecondes depuis l'époque Unix, en UTC. Les identifiants sont des UUID v4 (`TEXT`), sauf `ai_usage.id`.

### `folders`

| Colonne | Type | Contraintes |
| --- | --- | --- |
| `id` | TEXT | PK |
| `name` | TEXT | non vide |
| `parent_id` | TEXT | FK → `folders(id)` `ON DELETE CASCADE` |
| `created_at`, `updated_at` | INTEGER | non nuls |

Index unique `(IFNULL(parent_id, ''), name COLLATE NOCASE)` : deux dossiers frères ne peuvent pas porter le même nom, sans tenir compte de la casse.

### `documents`

| Colonne | Type | Contraintes |
| --- | --- | --- |
| `id` | TEXT | PK |
| `name` | TEXT | non vide, sans extension |
| `file_path` | TEXT | chemin relatif |
| `file_type` | TEXT | `pdf`, `jpg`, `png`, `txt` ou `docx` |
| `file_size` | INTEGER | ≥ 0 |
| `page_count` | INTEGER | nul ou ≥ 0 |
| `thumbnail_path` | TEXT | chemin relatif, facultatif |
| `folder_id` | TEXT | FK → `folders(id)` `ON DELETE SET NULL` |
| `source` | TEXT | `scan`, `import`, `pdf_tool`, `ocr`, `id_scan` ou `generated` |
| `created_at`, `updated_at` | INTEGER | non nuls |
| `is_favorite` | INTEGER | 0 ou 1, maintenu par trigger |
| `is_encrypted` | INTEGER | 0 ou 1 |
| `is_in_vault` | INTEGER | 0 ou 1 |
| `deleted_at` | INTEGER | non nul = dans la corbeille |

Index : `folder_id`, `deleted_at`, `updated_at DESC`, `name COLLATE NOCASE`, `is_in_vault`.

Supprimer un dossier ne supprime jamais un document : `folder_id` repasse à `NULL` et le document revient à la racine.

### `document_pages`

Pages image d'un document numérisé : `id`, `document_id` (FK `ON DELETE CASCADE`), `page_order` (≥ 0), `image_path`, `created_at`. Contrainte unique `(document_id, page_order)`.

### `ocr_results`

Texte extrait, par document et éventuellement par page : `id`, `document_id` (FK `ON DELETE CASCADE`), `page_index`, `extracted_text`, `language`, `created_at`, `updated_at`. Sert aussi à la recherche plein texte de la bibliothèque.

### `scan_history` et `scan_sessions`

- `scan_history` : `id`, `document_id` (FK `ON DELETE SET NULL`), `scan_type`, `page_count`, `created_at`.
- `scan_sessions` : état sérialisé d'une numérisation en cours (`id`, `mode`, `payload` JSON, `created_at`, `updated_at`) pour reprendre après une interruption.

### `qr_history`

`id`, `content`, `format`, `kind` (`scanned` ou `generated`), `scanned_at`.

### `favorites`

`id`, `document_id` (unique, FK `ON DELETE CASCADE`), `created_at`.

Deux triggers gardent `documents.is_favorite` synchronisé :

- `trg_favorites_insert` passe l'indicateur à 1 ;
- `trg_favorites_delete` le repasse à 0.

La table `favorites` est donc la source de vérité ; la colonne n'est qu'un cache pour filtrer et trier vite.

### `tags` et `document_tags`

- `tags` : `id`, `name` (unique, insensible à la casse), `created_at`.
- `document_tags` : `(document_id, tag_id)` en clé primaire, les deux en FK `ON DELETE CASCADE`.

### `app_settings`

Clé-valeur (`key` PK, `value`). Les clés sont préfixées par module : `app.theme_mode`, `scanner.default_mode`, `security.auto_lock_seconds`.

**Aucun secret ici** : empreinte du code PIN et clés de chiffrement vivent dans le stockage sécurisé adossé à l'Android Keystore.

### `subscription_cache`

Cache du dernier état d'abonnement vérifié : `product_id` (PK), `state`, `verification_source`, `purchase_token_hash` (SHA-256 du jeton, jamais le jeton), `expiration_date`, `last_verified_at`.

Ce cache ne donne pas droit au Premium par lui-même : il ne sert qu'à tolérer une courte période hors connexion. Voir [monetization.md](monetization.md).

### `ai_usage`

Journal local des appels à l'assistant IA (`id` auto-incrémenté, `feature`, `created_at`) pour afficher la consommation. Aucun contenu de document.

## Intégrité

- `PRAGMA foreign_keys = ON` est exécuté à chaque ouverture (`onConfigure`).
- Contraintes `CHECK` sur les types de fichiers, les booléens et les valeurs positives.
- Les tests (`test/core/storage/app_database_test.dart`) vérifient les clés étrangères, les cascades, les triggers et l'unicité des noms de dossiers.

## Migrations

`lib/core/storage/database/migrations.dart` contient `kMigrations`, une liste ordonnée de listes d'instructions SQL. La version de la base est `kMigrations.length`.

Règles :

1. Ne jamais modifier une migration déjà publiée.
2. Pour faire évoluer le schéma, **ajouter** une nouvelle liste à la fin.
3. À l'installation, toutes les migrations s'exécutent dans l'ordre ; à la mise à jour, seules les nouvelles. SQLite exécute l'ensemble dans une transaction.

## Sauvegarde et restauration

La sauvegarde automatique d'Android est **désactivée** (`android:allowBackup="false"`, règles d'extraction vides) pour deux raisons :

- elle est plafonnée à 25 Mo par application, ce qu'une bibliothèque de documents dépasse vite — elle échouerait alors silencieusement ;
- les documents de l'utilisateur ne doivent pas quitter l'appareil sans action explicite.

La stratégie est donc une **sauvegarde volontaire** depuis l'application (`BackupService`) :

- **Export** : une archive zip unique contenant un manifeste versionné, les métadonnées en JSON et les fichiers. L'utilisateur choisit où l'enregistrer.
- **Restauration** : validation du manifeste, rejet des entrées qui sortiraient de la racine de stockage, import transactionnel, en mode *fusion* ou *remplacement*.
- **Coffre-fort** : les documents chiffrés ne sont jamais exportés. Leur clé vit dans l'Android Keystore et ne peut pas quitter l'appareil ; le résumé de sauvegarde indique combien de documents ont été ignorés pour cette raison.

## Maintenance

Au démarrage, `StorageMaintenance` purge les zones `temp/` et `exports/` selon leur âge et supprime les fichiers qu'aucune ligne ne référence plus.
