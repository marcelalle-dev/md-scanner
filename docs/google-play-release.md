# Publication sur Google Play

Ce guide décrit tout ce qu'il reste à faire **manuellement** pour publier MD SCANNER. Rien de ce qui suit n'a été exécuté automatiquement : aucun compte n'a été créé, aucun identifiant n'a été inventé, l'application n'est pas publiée.

| Élément | Valeur |
| --- | --- |
| Nom | MD SCANNER |
| Package | `dev.marcelalle.mdscanner` (définitif après la première mise en ligne) |
| Éditeur | MarcelAlle.Dev |
| Catégorie conseillée | Productivité |
| Niveau d'API ciblé | 36 (Android 16) — exigé par Google Play pour les nouvelles applications depuis le 31 août 2026 |
| Pages mémoire 16 Ko | Bibliothèques natives 64 bits vérifiées conformes |

## 1. Comptes à créer

1. **Compte développeur Google Play** — https://play.google.com/console (frais d'inscription uniques, vérification d'identité).
2. **Compte AdMob** — https://admob.google.com, à lier au compte Play.
3. **Profil de paiement marchand** dans la Play Console, indispensable pour vendre des abonnements.

> Les comptes développeur **personnels** récents doivent mener un **test fermé** avec un nombre minimal de testeurs pendant 14 jours consécutifs avant de pouvoir demander l'accès à la production. La Play Console affiche l'exigence exacte applicable à votre compte : planifiez ce délai.

## 2. Clé d'upload

Créez le keystore **vous-même** et conservez-le hors du dépôt, avec une copie de secours. Sa perte complique fortement les mises à jour.

```bash
keytool -genkeypair -v -keystore upload-keystore.jks -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Puis créez `android/key.properties` comme décrit dans [installation.md](installation.md). À la première mise en ligne, activez **Play App Signing** : Google conserve la clé de signature finale, la vôtre n'est qu'une clé d'upload, réinitialisable en cas de perte.

## 3. Identifiants AdMob

Dans AdMob :

1. Ajouter l'application Android → noter l'**identifiant d'application** (`ca-app-pub-…~…`).
2. Créer trois blocs d'annonces : **bannière**, **interstitiel**, **avec récompense** → noter leurs identifiants (`ca-app-pub-…/…`).
3. Configurer le **message de consentement** (onglet *Confidentialité et messages*) pour l'Europe et les États américains concernés : l'application affiche ce message via la plateforme UMP de Google.
4. Publier un fichier `app-ads.txt` sur le site web déclaré dans la fiche Play.

Fournir ces identifiants au build : voir « Configuration au moment du build » dans [installation.md](installation.md).

Tant qu'ils ne sont pas fournis, l'application n'affiche que des **annonces de test** de Google. Ne cliquez jamais sur vos propres annonces réelles ; pendant les tests, déclarez vos appareils comme appareils de test dans AdMob.

## 4. Produits Premium

Dans la Play Console → *Monétisation* :

| Identifiant produit | Type | À configurer |
| --- | --- | --- |
| `md_scanner_premium_monthly` | Abonnement | Un forfait de base à renouvellement mensuel, prix par pays |
| `md_scanner_premium_yearly` | Abonnement | Un forfait de base à renouvellement annuel, prix par pays |
| `md_scanner_premium_lifetime` | Produit ponctuel (non consommable) | Prix par pays |

Les identifiants doivent correspondre **exactement**. Les prix ne sont jamais écrits dans l'application : elle affiche ceux renvoyés par Google Play.

Ajoutez ensuite des **testeurs de licence** (*Paramètres → Tests de licence*) : ils peuvent acheter sans être débités. Les achats ne fonctionnent que pour une version installée depuis un canal de test Play (interne, fermé) ou la production — pas pour un APK installé à la main.

### Vérification serveur (recommandée)

Sans backend, l'application vérifie les achats auprès de Google Play sur l'appareil. C'est fonctionnel, mais ne détecte pas les remboursements et reste exposé à une falsification sur un appareil rooté.

Pour une vérification robuste, déployez le backend (`backend/`, voir [api.md](api.md)) avec un **compte de service Google Cloud** autorisé sur la Play Console (*Utilisateurs et autorisations* → inviter le compte de service → droit de consulter les données financières et les commandes), puis fournissez `PURCHASE_VERIFICATION_URL` au build.

## 5. Construire l'App Bundle

1. Incrémenter la version dans `pubspec.yaml` (`version: 1.0.0+1` → le nombre après `+` est le `versionCode`, à augmenter à chaque envoi).
2. Construire :

   ```bash
   flutter build appbundle --release --dart-define-from-file=config/prod.json
   ```

3. Vérifier que le fichier existe : `build/app/outputs/bundle/release/app-release.aab`.

Avec les secrets de signature configurés dans GitHub, le workflow `release.yml` produit aussi l'APK et l'AAB signés à chaque tag `vX.Y.Z`.

## 6. Fiche Play Store

| Élément | Exigence | Disponible |
| --- | --- | --- |
| Icône | 512 × 512 PNG | `assets/brand/play_store_icon.png` |
| Image de présentation | 1024 × 500 | À produire |
| Captures d'écran téléphone | 2 à 8, ratio 16:9 ou 9:16 | À capturer sur un appareil réel |
| Description courte | 80 caractères max | Proposition ci-dessous |
| Description complète | 4000 caractères max | Proposition ci-dessous |
| Politique de confidentialité | URL publique | [privacy.md](privacy.md), consultable sur GitHub |

**Description courte (FR)** — « Scanner de documents, OCR, outils PDF et QR codes. Fonctionne hors connexion. »

**Description courte (EN)** — "Document scanner, OCR, PDF tools and QR codes. Works offline."

**Description complète (FR)**

> MD SCANNER transforme votre téléphone en scanner de documents professionnel.
>
> • Numérisez vos documents, reçus, livres, tableaux et pièces d'identité, avec détection des bords, redressement et filtres.
> • Créez des PDF multipages, fusionnez, divisez, compressez, protégez par mot de passe, signez.
> • Extrayez le texte de vos images (OCR), corrigez-le et exportez-le.
> • Lisez et créez des QR codes et des codes-barres.
> • Rangez vos documents dans des dossiers, avec favoris, étiquettes et recherche.
> • Protégez vos fichiers sensibles dans un coffre-fort chiffré, verrouillé par code PIN ou biométrie.
>
> Vos documents restent sur votre appareil. La numérisation, les PDF, l'OCR et les QR codes fonctionnent sans connexion Internet.
>
> Gratuit avec publicités discrètes. L'offre Premium supprime les publicités et débloque les fonctions avancées.

Adaptez ce texte : il ne doit annoncer que ce que la version publiée fait réellement.

## 7. Déclarations obligatoires

### Sécurité des données

À remplir dans *Contenu de l'application → Sécurité des données*, en cohérence avec [privacy.md](privacy.md) :

| Donnée | Collectée | Partagée | Finalité |
| --- | --- | --- | --- |
| Identifiant publicitaire, données de diagnostic de l'appareil | Oui, par le SDK Google Mobile Ads | Oui, avec Google | Publicité, mesure |
| Historique des achats | Oui, par Google Play Billing | Avec Google ; avec votre backend si la vérification serveur est activée | Gestion de l'abonnement |
| Documents, photos, texte extrait | **Non** : traités et stockés sur l'appareil | Non | — |
| Texte envoyé à l'assistant IA | Seulement si l'utilisateur y consent, pour la requête en cours | Avec votre backend et le fournisseur d'IA ; non conservé | Fonctionnalité de l'application |

Cochez « les données sont chiffrées en transit » et indiquez comment l'utilisateur supprime ses données (dans l'application : *Profil → Confidentialité → Effacer mes données*).

### Autres déclarations

- **Publicités** : oui, l'application contient des annonces.
- **Identifiant publicitaire** : utilisé, pour la publicité.
- **Classification du contenu** : remplir le questionnaire (application utilitaire, sans contenu sensible).
- **Public cible** : adultes ; l'application ne s'adresse pas aux enfants.
- **Autorisations sensibles** : seule la caméra est demandée, pour numériser. Aucune permission de stockage globale.
- **Abonnements** : l'écran Premium affiche le prix, la période, les conditions de renouvellement, un bouton de restauration et un lien de gestion vers Google Play.

## 8. Mise en ligne

1. **Test interne** : envoyer l'AAB, installer depuis le lien de test, vérifier les achats (testeurs de licence) et les annonces de test.
2. **Rapport préalable au lancement** : consulter les résultats (plantages, accessibilité, pages 16 Ko).
3. **Test fermé** : obligatoire pour les comptes personnels récents (voir §1).
4. **Production** : déploiement progressif conseillé (par exemple 20 %, puis 100 %).

## 9. Liste de contrôle avant envoi

- [ ] `versionCode` incrémenté
- [ ] AAB signé avec la clé d'upload (pas la clé de debug)
- [ ] Identifiants AdMob réels fournis au build, annonces réelles jamais cliquées
- [ ] Les trois produits Premium actifs dans la Play Console
- [ ] `flutter analyze` sans problème, `flutter test` vert
- [ ] Parcours testés sur un appareil réel : numérisation, PDF, OCR, QR, coffre-fort, achat et restauration
- [ ] Politique de confidentialité en ligne et à jour
- [ ] Formulaire « Sécurité des données » cohérent avec le comportement réel de l'application
