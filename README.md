# MD SCANNER

Application Android de numérisation et de gestion documentaire, éditée par **MarcelAlle.Dev**.

MD SCANNER transforme un smartphone en scanner de documents : capture avec détection des bords, PDF multipages, OCR, QR codes, boîte à outils PDF, bibliothèque locale et coffre-fort chiffré. Les fonctions de numérisation, PDF, OCR, codes et coffre-fort fonctionnent hors connexion.

| Élément | Valeur |
| --- | --- |
| Package Android | `dev.marcelalle.mdscanner` |
| Framework | Flutter 3.44 · Dart 3.12 · Material 3 |
| Architecture | Clean Architecture par fonctionnalité · Riverpod · GoRouter · SQLite |
| Langues | Français, anglais |
| Android | minSdk 24 · targetSdk 36 · bibliothèques natives alignées 16 Ko |

## État d'avancement

Cette section fait foi.

> **Aucun test sur appareil réel n'a encore été effectué.** La logique est couverte par 356 tests automatisés (plus 93 pour le backend) exécutés sur poste de développement, et l'APK se construit. La caméra, le scanner et l'OCR de Google, la biométrie, les achats et les publicités ne s'exécutent que sur un téléphone : ils restent à valider.

### Terminé

| Domaine | Contenu | Vérification |
| --- | --- | --- |
| Numérisation | Scanner Google ML Kit, import de photos avec détection et redressement, recadrage manuel des quatre coins, réglages de luminosité, contraste et saturation par page, 5 modes de capture, 6 filtres, gestion multipage, export PDF et JPG | Tests hôte |
| Moteur PDF et 12 outils | Images ↔ PDF, fusion, extraction, compression, rotation, protection AES-256, déverrouillage, filigrane, numérotation, ajout de texte, signature manuscrite ; impression | Tests hôte du moteur, sorties relues par PDFium ; signature et impression non exécutées |
| OCR | Reconnaissance hors ligne (alphabet latin), PDF page par page, correction manuelle, recherche insensible aux accents, export TXT et DOCX | Tests hôte ; moteur ML Kit non exécuté |
| QR codes et codes-barres | Lecture caméra et image (QR, Data Matrix, Aztec, PDF417, EAN, UPC, Code 128, Code 39), lampe, zoom, analyse de sécurité des liens, historique, génération avec export PNG | Tests hôte ; caméra non exécutée |
| Bibliothèque | SQLite, import, dossiers imbriqués, étiquettes avec filtre, recherche (noms et texte reconnu), tri, favoris, aperçu, partage, corbeille, sauvegarde | Tests hôte |
| Pièces d'identité | Capture recto et verso, lecture des zones MRZ (passeports et cartes, clés de contrôle vérifiées), repérage des dates et numéros à défaut, export PDF ; rien n'est conservé sans enregistrement | Tests hôte de l'analyse ; capture non exécutée |
| Coffre-fort et verrouillage | Code PIN (empreinte Argon2id, tentatives limitées), biométrie, chiffrement AES-256-GCM par blocs, verrouillage à la mise en arrière-plan, protection contre les captures d'écran, verrouillage facultatif de toute l'application, effacement complet des données | Tests hôte (chiffrement, falsification) ; biométrie et Keystore non exécutés |
| Premium | Google Play Billing : offres et prix lus sur le Play Store, vérification avant octroi, restauration, révocation, tolérance hors ligne de 3 jours | Tests hôte avec doublure du Play Store |
| Publicités | AdMob après consentement (UMP), bannière dans son propre emplacement, interstitiel plafonné après une tâche terminée, annonce avec récompense pour un export DOCX ponctuel, rien pour les abonnés | Politique testée ; SDK non exécuté |
| Assistant | Repérage local des dates et montants ; client du backend IA avec consentement explicite | Tests hôte avec faux serveur |
| Application | Introduction au premier lancement, navigation à 5 entrées, thèmes, français et anglais, icône adaptative | Tests de widgets |
| Backend | Relais vers l'API Claude et vérification des achats Google Play (Cloudflare Workers), quotas et budget global | 93 tests avec doublures ; jamais déployé |
| CI/CD | Workflows `ci`, `android-build`, `release` | Exécutés sur GitHub Actions |

### En attente d'éléments externes

| Fonction | Ce qui manque |
| --- | --- |
| Achats Premium | Produits à créer dans la Play Console ; fonctionne seulement pour une version installée depuis Google Play |
| Publicités réelles | Identifiants AdMob ; sans eux, seules des annonces de test s'affichent |
| Assistant IA | Backend à déployer avec vos clés ([backend/README.md](backend/README.md)) ; sans lui, l'assistant s'affiche comme indisponible |
| Vérification serveur des achats | Même backend |
| Publication | Keystore d'upload, compte développeur |

### Non réalisé

- Placement libre de la signature et du texte sur la page (positions prédéfinies seulement).
- Tests d'intégration sur appareil et tests de performance.

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
  app/        démarrage, routeur, thème, navigation
  core/       erreurs typées, stockage, sécurité, widgets communs
  shared/     modèles, dépôt de documents, sauvegarde, abonnement
  features/
    document_scanner/  image_editor/  pdf_tools/  ocr/  qr_scanner/
    document_vault/    security/      premium/    ads/  ai_assistant/
    id_scanner/        onboarding/    home/       settings/
backend/      serveur Cloudflare Workers (assistant IA, vérification des achats)
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
