# Architecture

## Principes

Clean Architecture découpée par fonctionnalité. Chaque fonctionnalité sépare :

- `domain/` — entités et interfaces, en Dart pur ;
- `data/` — implémentations (SQLite, fichiers, plugins) ;
- `presentation/` — écrans, widgets et contrôleurs Riverpod.

Règle de dépendance : `presentation → domain ← data`. `core` et `shared` n'importent jamais une fonctionnalité. Les conventions complètes sont dans [CONTRIBUTING.md](../CONTRIBUTING.md).

## Vue d'ensemble

```
lib/
  main.dart                    appelle bootstrap()
  app/
    bootstrap.dart             ouvre la base et le stockage, câble les moteurs, lance l'app
    app.dart                   MaterialApp.router : thème, langue, localisations
    router.dart                GoRouter : 5 branches + écrans plein écran
    routes.dart                constantes de routes
    shell/app_shell.dart       barre de navigation
    theme/                     jetons de design et thème Material 3
    configuration/             configuration de build (--dart-define)
    l10n/                      textes de l'application (fr, en)
  core/
    errors/                    Result<T> et hiérarchie scellée Failure
    storage/                   AppDatabase, migrations, FileStorage, SettingsStore
    services/                  journal technique, pont natif (PlatformBridge)
    l10n/                      textes communs et messages d'erreur
    widgets/                   dialogues, progression, états vide/erreur, cartes
  shared/
    models/                    DocumentEntity, FolderEntity, TagEntity, DocumentQuery
    repositories/              contrat DocumentRepository et implémentation SQLite
    providers/                 listes de documents réactives, réglages, abonnement
    services/                  sauvegarde, maintenance du stockage
  features/
    document_scanner/          capture (ML Kit, galerie) et session de numérisation
    image_editor/              moteur d'image (détection, perspective, filtres)
    pdf_tools/                 moteur PDF et écrans d'outils
    document_vault/            bibliothèque : liste, détail, corbeille
    home/  settings/
```

## Décisions structurantes

### Erreurs typées

Les dépôts et services renvoient `Future<Result<T>>` et ne laissent fuir aucune exception. Les échecs sont des `Failure` d'une hiérarchie **scellée** : le compilateur impose de tous les traiter, et `failureMessage()` fournit un message localisé pour chacun. Le champ `debugMessage` ne contient jamais de nom de fichier ni de contenu de document.

### Métadonnées en base, octets sur disque

SQLite ne stocke que des métadonnées ; les fichiers vivent dans le stockage privé sous des noms UUID, référencés par des **chemins relatifs**. Détails : [database.md](database.md).

### Plugins derrière des interfaces

Tout ce qui ne fonctionne que sur un appareil (scanner Google, sélecteur de photos) est masqué par une interface du domaine (`DocumentCapture`). La logique — session de numérisation, export — se teste ainsi sur poste de développement avec des doublures.

### Traitements lourds hors du thread d'interface

Le moteur d'image exécute décodage, redressement et filtres dans des isolats. Les appels PDFium passent par le fil de travail de `pdfrx_engine` ; les opérations PDF en Dart pur (compression, tampons) s'exécutent dans des isolats. Les pages sont traitées une par une.

### Localisation modulaire

Chaque module possède ses fichiers ARB et sa classe générée (`AppLocalizations`, `CoreLocalizations`). `tool/gen_l10n.dart` régénère l'ensemble. Ajouter une langue revient à ajouter un fichier ARB par module.

### Session de numérisation réversible

Une page de session conserve l'image **d'origine** plus ses réglages (contour, rotation, filtre). Le rendu n'est calculé qu'à l'aperçu et à l'export : toute modification reste annulable jusqu'à l'enregistrement.

## Moteur PDF

| Besoin | Bibliothèque | Licence |
| --- | --- | --- |
| Affichage, rendu de pages, fusion, extraction, rotation | `pdfrx` / `pdfrx_engine` (PDFium) | MIT |
| Compression, filigrane, numérotation, tampons, chiffrement | `pdf_document` / `pdf_cos` (Dart pur) | Apache-2.0 |
| Création depuis des images | `pdf`, `image` | Apache-2.0, MIT |

Les opérations de structure préservent le contenu vectoriel : aucune page n'est convertie en image pour fusionner, extraire ou pivoter. La protection par mot de passe (AES-256, révision 6) est vérifiée par des tests qui rouvrent le fichier avec PDFium, une implémentation indépendante.

## Dépendances principales

| Paquet | Rôle | Licence |
| --- | --- | --- |
| `flutter_riverpod` | Gestion d'état | MIT |
| `go_router` | Navigation | BSD-3 |
| `sqflite` | Base SQLite | BSD-2 |
| `google_mlkit_document_scanner` | Scanner de documents | MIT (SDK Google sous ses propres conditions) |
| `image` | Traitement d'image | MIT |
| `pdfrx`, `pdf_document`, `pdf` | PDF | MIT, Apache-2.0 |
| `image_picker`, `file_picker`, `share_plus` | Import, export, partage | BSD-3, MIT |
| `archive` | Sauvegardes zip | MIT |

Des paquets sont déjà déclarés pour les modules à venir (OCR, codes-barres, sécurité, facturation, publicité) : voir l'état d'avancement du [README](../README.md).

## Plateforme Android

- AGP 9, Kotlin 2.3, Gradle 9 ; `compileSdk` et `targetSdk` 36, `minSdk` 24.
- `MainActivity` hérite de `FlutterFragmentActivity` et expose un canal natif minimal (protection d'écran, état de la permission caméra, ouverture des réglages).
- R8 et réduction des ressources activés en release.

## Tests

`test/` reflète `lib/`. Les tests utilisent une base SQLite en mémoire avec le schéma de production et un stockage temporaire (`test/helpers/`). La CI exécute formatage, analyse et tests à chaque push.
