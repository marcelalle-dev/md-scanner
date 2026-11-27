# MD SCANNER

Application Android de numérisation et de gestion documentaire, éditée par **MarcelAlle.Dev**.

MD SCANNER transforme un smartphone en scanner de documents : capture avec détection des bords, PDF multipages, boîte à outils PDF et bibliothèque locale. Tout fonctionne hors connexion ; les documents ne quittent pas l'appareil.

| Élément | Valeur |
| --- | --- |
| Package Android | `dev.marcelalle.mdscanner` |
| Framework | Flutter 3.44 · Dart 3.12 · Material 3 |
| Architecture | Clean Architecture par fonctionnalité · Riverpod · GoRouter · SQLite |
| Langues | Français, anglais |
| Android | minSdk 24 · targetSdk 36 · bibliothèques natives alignées 16 Ko |

## État d'avancement

Cette section fait foi. Elle distingue ce qui fonctionne, ce qui est vérifié seulement par des tests sur poste de développement, et ce qui reste à faire.

> **Aucun test sur appareil réel n'a encore été effectué.** La logique est couverte par 279 tests automatisés exécutés sur poste de développement, et l'APK se construit ; la caméra, le scanner Google et le rendu sur téléphone restent à valider sur un appareil.

### Terminé

| Domaine | Contenu | Vérification |
| --- | --- | --- |
| Numérisation | Scanner de documents Google ML Kit (détection des bords, recadrage, multipage), import de photos avec détection et redressement maison, 5 modes de capture, réorganisation / duplication / rotation / suppression des pages, 6 filtres, export PDF et JPG | Tests hôte ; scanner ML Kit non exécuté sur appareil |
| Traitement d'image | Détection de contour, correction de perspective par homographie, niveaux de gris, noir et blanc adaptatif, lisibilité, suppression des ombres, hors du thread d'interface | Tests hôte sur images synthétiques |
| Moteur PDF | Images → PDF, PDF → images, fusion, extraction, suppression, réordonnancement, rotation, compression à 3 niveaux, filigrane, numérotation, ajout de texte et d'image, protection AES-256, déverrouillage | Tests hôte, sorties relues par PDFium |
| Outils PDF (interface) | 10 outils : images vers PDF, fusion, extraction de pages, compression, rotation, protection, déverrouillage, filigrane, numérotation, PDF vers images | Tests hôte de la logique |
| Bibliothèque | Persistance SQLite, import de fichiers, recherche, tri, favoris, renommage, aperçu PDF / image / texte, partage, corbeille et restauration | Tests hôte |
| Sauvegarde | Export et restauration d'une archive zip, nettoyage automatique des fichiers temporaires | Tests hôte |
| Application | Navigation à 5 entrées, thème clair / sombre / automatique, français et anglais, icône adaptative, écran de démarrage | Tests de widgets |
| Plateforme | Permissions minimales (caméra, Internet), aucune permission de stockage, signature de publication configurable | Manifest fusionné contrôlé |
| CI/CD | Workflows `ci`, `android-build`, `release` | Exécutés sur GitHub Actions |

### Présent dans le moteur, pas encore dans l'interface

- Dossiers et étiquettes de la bibliothèque.
- Recadrage manuel des quatre coins et réglages fins (luminosité, contraste, saturation).
- Ajout de texte libre et signature manuscrite sur un PDF, impression.

### Non réalisé

| Module | État |
| --- | --- |
| OCR (reconnaissance de texte, export TXT / DOCX) | Non commencé |
| Scanner et générateur de QR codes et codes-barres | Non commencé |
| Scanner de pièces d'identité | Non commencé |
| Coffre-fort, code PIN, biométrie, chiffrement des fichiers | Non commencé |
| Premium (Google Play Billing) | Non commencé — aucun achat n'est proposé dans l'application |
| Publicités (AdMob) | SDK et identifiant de test déclarés dans le manifest ; aucune annonce n'est affichée |
| Assistant IA | Non commencé côté application ; ébauche de backend non relue dans `backend/` (non versionnée) |
| Onboarding, écran de confidentialité intégré | Non commencé |
| Tests d'intégration sur appareil, tests de performance | Non réalisés |

L'application n'est **pas publiée** sur Google Play.

## Démarrage rapide

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Détails, configuration et signature : [docs/installation.md](docs/installation.md).

## Structure du projet

```
lib/
  app/        démarrage, routeur, thème, navigation, textes de l'application
  core/       erreurs typées, stockage, journal technique, widgets communs
  shared/     modèles, dépôt de documents, sauvegarde
  features/
    document_scanner/   capture et session de numérisation
    image_editor/       moteur de traitement d'image
    pdf_tools/          moteur et outils PDF
    document_vault/     bibliothèque de documents
    home/ settings/
```

## Documentation

- [Installation et configuration](docs/installation.md)
- [Architecture](docs/architecture.md)
- [Base de données et stockage](docs/database.md)
- [Sécurité](docs/security.md)
- [Confidentialité](docs/privacy.md)
- [Monétisation](docs/monetization.md)
- [API du backend](docs/api.md)
- [Publication sur Google Play](docs/google-play-release.md)
- [Conventions de développement](CONTRIBUTING.md)

## Licence

Code source disponible sous licence propriétaire — voir [LICENSE](LICENSE). La police Inter est distribuée sous licence SIL Open Font License 1.1.
