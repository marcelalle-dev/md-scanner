# Installation et configuration

## Prérequis

| Outil | Version utilisée |
| --- | --- |
| Flutter | 3.44.5 (canal stable) |
| Dart | 3.12.2 (fourni avec Flutter) |
| JDK | 17 ou plus récent (21 recommandé) |
| Android SDK | plateforme 36, build-tools 36 |
| Android NDK | 28.2.13676358 |
| Git | toute version récente |

Vérifier l'environnement :

```bash
flutter doctor -v
```

Si Flutter signale des licences Android non acceptées :

```bash
flutter doctor --android-licenses
```

> Sous Windows, placez le projet dans un chemin **sans espace** (par exemple `C:\src\md-scanner`). Le NDK et certains outils Gradle gèrent mal les espaces.

## Récupérer et lancer le projet

```bash
git clone https://github.com/marcelalle-dev/md-scanner.git
cd md-scanner
flutter pub get
flutter run
```

Le premier build Android télécharge Gradle, les dépendances et la bibliothèque PDFium : comptez une dizaine de minutes et une connexion Internet.

## Commandes courantes

```bash
dart format lib test tool      # formatage
flutter analyze                # analyse statique
flutter test                   # tests unitaires et de widgets
dart run tool/gen_l10n.dart    # régénère les classes de localisation de tous les modules
```

Les fichiers de localisation générés (`lib/**/l10n/generated/`) sont versionnés. Après avoir modifié un fichier `.arb`, relancez `gen_l10n.dart` et committez le résultat : la CI échoue si les fichiers générés ne sont pas à jour.

## Configuration au moment du build

MD SCANNER fonctionne **sans aucune configuration** : sans rien fournir, l'application utilise les annonces de test de Google, désactive l'assistant IA et vérifie les achats auprès de Google Play sur l'appareil.

Les valeurs de production se passent au build. Aucune n'est un secret : toutes finissent lisibles dans l'APK.

### Variables Dart (`--dart-define`)

| Clé | Rôle | Sans valeur |
| --- | --- | --- |
| `AI_BACKEND_URL` | URL du backend qui relaie l'assistant IA | Assistant IA désactivé |
| `PURCHASE_VERIFICATION_URL` | Point d'accès de vérification serveur des achats | Vérification sur l'appareil uniquement |
| `ADMOB_BANNER_UNIT_ID` | Bloc d'annonces bannière | Bloc de test Google |
| `ADMOB_INTERSTITIAL_UNIT_ID` | Bloc d'annonces interstitiel | Bloc de test Google |
| `ADMOB_REWARDED_UNIT_ID` | Bloc d'annonces avec récompense | Bloc de test Google |
| `ADS_ENABLED` | `false` désactive toute publicité | `true` |

Le plus simple est un fichier JSON **non versionné** :

```json
{
  "AI_BACKEND_URL": "https://exemple.workers.dev",
  "ADMOB_BANNER_UNIT_ID": "ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX"
}
```

```bash
flutter build apk --release --dart-define-from-file=config/prod.json
```

### Identifiant d'application AdMob

L'identifiant d'**application** AdMob est écrit dans le manifest Android. Sans valeur, le build utilise l'identifiant d'exemple public de Google (annonces de test uniquement).

```bash
# variable d'environnement
ADMOB_APP_ID="ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX" flutter build appbundle --release

# ou propriété Gradle, dans ~/.gradle/gradle.properties
admobAppId=ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX
```

## Signature de publication

Sans configuration, un build `release` est signé avec la **clé de debug** : pratique pour tester, mais **non publiable** sur Google Play.

1. Créer le keystore d'upload (une seule fois ; à conserver précieusement, hors du dépôt) :

   ```bash
   keytool -genkeypair -v -keystore upload-keystore.jks -storetype JKS \
     -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

2. Créer `android/key.properties` (ignoré par Git) :

   ```properties
   storeFile=C:/chemin/vers/upload-keystore.jks
   storePassword=********
   keyAlias=upload
   keyPassword=********
   ```

3. Construire :

   ```bash
   flutter build apk --release          # build/app/outputs/flutter-apk/app-release.apk
   flutter build appbundle --release    # build/app/outputs/bundle/release/app-release.aab
   ```

La procédure complète de publication est décrite dans [google-play-release.md](google-play-release.md).

## Identité visuelle

Le logo est dessiné par un script, donc reproductible :

```bash
dart run tool/generate_brand_assets.dart     # écrit assets/brand/*.png
dart run flutter_launcher_icons              # icônes de lancement Android
dart run flutter_native_splash:create        # écran de démarrage natif
```

La police **Inter** (licence SIL Open Font License 1.1) est embarquée dans `assets/fonts/` : aucun téléchargement à l'exécution, l'application reste identique hors connexion.

## Intégration continue

| Workflow | Déclencheur | Rôle |
| --- | --- | --- |
| `ci.yml` | push et pull request | localisations à jour, formatage, analyse, tests |
| `android-build.yml` | push sur `main`, lancement manuel | APK release ; AAB si les secrets de signature existent |
| `release.yml` | tag `vX.Y.Z` | APK et AAB signés, brouillon de release GitHub |

Secrets du dépôt, à créer uniquement quand le keystore existe :

| Secret | Contenu |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | le fichier `.jks` encodé en base64 |
| `ANDROID_KEYSTORE_PASSWORD` | mot de passe du keystore |
| `ANDROID_KEY_ALIAS` | alias de la clé (`upload`) |
| `ANDROID_KEY_PASSWORD` | mot de passe de la clé |

Encoder le keystore :

```bash
base64 -w0 upload-keystore.jks          # Linux, Git Bash
```

Les identifiants non secrets (`ADMOB_APP_ID`, `ADMOB_*_UNIT_ID`, `AI_BACKEND_URL`, `PURCHASE_VERIFICATION_URL`) se déclarent comme **variables** du dépôt, pas comme secrets.

Aucun workflow ne publie sur Google Play : la mise en ligne reste une action manuelle.

## Dépannage

| Symptôme | Cause et solution |
| --- | --- |
| `Failed to find target with hash string 'android-37'` | Un plugin exige une plateforme Android plus récente que celle gérée par l'AGP du projet. Ne pas ajouter `permission_handler` 14.x : le projet utilise un canal natif à la place (`PlatformBridge`). |
| Le build Gradle sature la mémoire | `android/gradle.properties` limite le tas à 3 Go. Fermez les autres applications lourdes pendant le build. |
| Avertissement « plugins that apply Kotlin Gradle Plugin » | Connu pour `cryptography_flutter`. Sans effet avec Flutter 3.44 ; à surveiller lors d'une montée de version de Flutter. |
| `Missing class com.google.mlkit.vision.text.chinese…` avec R8 | Les règles nécessaires sont dans `android/app/proguard-rules.pro`. |
