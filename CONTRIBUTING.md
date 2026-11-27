# Conventions de développement — MD SCANNER

Ce document est le contrat commun de toute personne (ou agent) qui écrit du code dans ce dépôt.

## 1. Architecture

Clean Architecture, découpée par fonctionnalité.

```
lib/
  app/        composition : bootstrap, routeur, thème, configuration
  core/       briques techniques sans logique métier (erreurs, stockage, sécurité, l10n, widgets)
  shared/     modèles, dépôts et providers utilisés par plusieurs fonctionnalités
  features/<nom>/
    domain/        entités, interfaces de dépôts/services, cas d'usage — Dart pur
    data/          implémentations (SQLite, fichiers, plugins, réseau)
    presentation/  écrans, widgets, contrôleurs Riverpod
    l10n/          <nom>_fr.arb, <nom>_en.arb, generated/
```

Règles de dépendance :

- `presentation` → `domain` ← `data`. La couche `domain` n'importe ni Flutter (hors `foundation`), ni plugin, ni `data`.
- Une fonctionnalité peut importer le `domain` d'une autre, jamais sa `presentation` ni son `data` (sauf via un provider exposé par le `domain`).
- `core` et `shared` n'importent jamais `features`.
- Imports toujours en `package:md_scanner/...` (lint `always_use_package_imports`).
- Pas de génération de code (ni `build_runner`, ni `freezed`, ni `riverpod_generator`). Entités immuables avec `Equatable` et `copyWith` écrits à la main.
- Aucun fichier de plusieurs milliers de lignes : au-delà d'environ 400 lignes, découper.

## 2. Gestion d'état — Riverpod 3

- `Notifier` / `AsyncNotifier` avec `NotifierProvider` / `AsyncNotifierProvider`, `Provider`, `FutureProvider`, `StreamProvider`.
- Pas d'API héritée (`StateProvider`, `StateNotifierProvider`, `ChangeNotifierProvider`).
- Les dépendances (dépôts, services, plugins) sont injectées par providers pour être remplaçables en test via `overrides`.
- Un contrôleur ne référence jamais un `BuildContext`.

## 3. Erreurs

- Les dépôts et services renvoient `Future<Result<T>>` (`core/errors/result.dart`) et ne laissent jamais fuir d'exception brute. Utiliser `guard(() async { ... })`.
- Les échecs sont des `Failure` typés (`core/errors/failure.dart`). Besoin d'un nouveau cas : l'ajouter à la hiérarchie scellée et au mappage `core/l10n/failure_messages.dart`.
- L'interface affiche `failureMessage(context, failure)` ; jamais `failure.debugMessage`, jamais `e.toString()`.
- `CancelledFailure` n'est pas une erreur à afficher.
- `debugMessage` et le journal technique (`AppLogger`) ne contiennent jamais de contenu de document, de texte OCR, de nom de fichier ni de donnée personnelle.

## 4. Localisation

Français (modèle) et anglais. Chaque module possède ses fichiers ARB :

```
lib/features/ocr/l10n/ocr_fr.arb
lib/features/ocr/l10n/ocr_en.arb
```

Puis :

```bash
dart run tool/gen_l10n.dart ocr
```

génère `OcrLocalizations` dans `l10n/generated/ocr_localizations.dart` (fichiers générés versionnés).

- Aucune chaîne visible en dur dans les widgets.
- Les libellés communs (OK, Annuler, Enregistrer, messages d'erreur…) sont dans `CoreLocalizations` : ne pas les dupliquer.
- Toute clé présente en français doit l'être en anglais.
- Ajouter une langue : ajouter `<module>_<code>.arb` dans chaque module et le code dans `AppSettings.supportedLocaleCodes`.

## 5. Navigation

- GoRouter. Les chemins viennent exclusivement de `AppRoutes` (`lib/app/routes.dart`).
- Passer des identifiants (paramètres de chemin ou de requête) plutôt que des objets ; `extra` est réservé aux requêtes éphémères qui n'ont pas à survivre à un redémarrage.
- Un écran renvoie un résultat à l'appelant avec `context.pop(result)`.

## 6. Fichiers et base de données

- SQLite ne stocke que des métadonnées. Les octets vivent sur disque via `FileStorage`.
- Les chemins enregistrés sont **relatifs** à la racine de stockage (`documents/<uuid>.pdf`). Résoudre avec `fileStorage.absolutePath(relative)`.
- Tout fichier produit pour l'utilisateur est enregistré dans la bibliothèque via `DocumentRepository.register` ou `importExternalFile`.
- Fichiers de travail : zone `temp` ou `sessions`, supprimés dès la fin de l'opération (y compris en cas d'échec).
- Évolution du schéma : ajouter une migration à la fin de `kMigrations`, ne jamais modifier une migration publiée.
- Préférences : `SettingsStore` avec des clés préfixées par le module (`scanner.default_mode`). Jamais de secret dans cette table.

## 7. Performance

- Décodage, filtres, redressement, génération PDF, chiffrement : hors du thread UI (`Isolate.run` / `compute`).
- Ne jamais charger toutes les pages d'un PDF ou d'une session en mémoire : traiter page par page, afficher des vignettes.
- Toute opération longue expose une progression, peut être annulée quand c'est possible et se protège contre le double déclenchement.

## 8. Sécurité et confidentialité

- Aucun secret, clé d'API ou identifiant de production dans le code ou le dépôt.
- Aucun mot de passe ni code PIN en clair, nulle part.
- Aucun envoi de document hors de l'appareil sans action explicite et consentement de l'utilisateur.
- Permissions Android minimales ; pas de permission de stockage globale.

## 9. Qualité produit

- Aucun bouton sans action réelle. Aucune donnée de démonstration présentée comme réelle.
- Aucun résultat inventé (score de confiance, taux de compression, statut Premium).
- Chaque écran gère ses états : chargement, vide, erreur, succès.
- Accessibilité : cibles tactiles d'au moins 48 dp, `tooltip`/`Semantics` sur les boutons-icônes, contrastes suffisants, mise en page correcte à 320 dp de large et avec une taille de police augmentée.
- Pas de commentaires qui paraphrasent le code ; documenter le *pourquoi* et les contrats publics.

## 10. Tests

- `test/` reflète l'arborescence de `lib/`.
- `test/helpers/pump_app.dart` : `tester.pumpApp(widget, delegates: [...], overrides: [...])`.
- `test/helpers/test_database.dart` : `openTestDatabase()` (SQLite en mémoire, schéma de production) et `createTestStorage()`.
- Les plugins natifs sont masqués derrière une interface du `domain` ; les tests utilisent des doublures, jamais de faux résultat en production.

Avant chaque commit :

```bash
dart format .
flutter analyze
flutter test
```

## 11. Commits

Messages au format Conventional Commits : `feat:`, `fix:`, `test:`, `docs:`, `refactor:`, `chore:`, `ci:`.
