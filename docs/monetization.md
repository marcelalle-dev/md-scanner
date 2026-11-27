# Monétisation

> **État : implémenté, non éprouvé en conditions réelles.** Les règles sont couvertes par des tests avec une doublure du Play Store. Un achat réel exige des produits créés dans la Play Console et une version installée depuis Google Play ; des annonces réelles exigent vos identifiants AdMob.

## Modèle freemium

| Gratuit | Premium |
| --- | --- |
| Numérisation, export PDF et JPG | Suppression des publicités |
| Outils PDF essentiels | Outils PDF avancés, traitement par lots |
| Bibliothèque locale, hors connexion | OCR avancé, export DOCX |
| Publicités non intrusives | Assistant IA, fonctions avancées du coffre-fort |

Les fonctions essentielles de numérisation ne sont jamais bloquées.

## Produits Google Play

| Identifiant | Type |
| --- | --- |
| `md_scanner_premium_monthly` | Abonnement |
| `md_scanner_premium_yearly` | Abonnement |
| `md_scanner_premium_lifetime` | Achat unique |

Les prix se définissent dans la Play Console et ne figurent jamais dans le code.

## Achats — ce que fait l'application

- Les offres et leurs **prix viennent de Google Play** ; aucun prix n'est écrit dans le code.
- Un achat est **vérifié avant** d'accorder le Premium, et acquitté seulement après. Un achat non vérifié n'est pas acquitté : Google le rembourse automatiquement.
- À **chaque démarrage**, Google Play est réinterrogé. Un achat qu'il ne renvoie plus (expiré, annulé puis échu, remboursé) entraîne le retrait du Premium.
- **Hors connexion**, le dernier état vérifié est toléré 3 jours, puis l'application repasse en gratuit.
- Le statut Premium vit en mémoire et porte sa provenance (`playStore`, `server`, `offlineGrace`). Seul le service de facturation peut l'écrire.
- Le jeton d'achat n'est jamais stocké ; seule son empreinte SHA-256 figure dans `subscription_cache`.
- L'écran Premium affiche les avantages, les offres, la restauration des achats et le lien de gestion de l'abonnement sur Google Play.

### Vérification serveur

Sans `PURCHASE_VERIFICATION_URL`, la vérification se fait sur l'appareil : seul un achat que la bibliothèque Play Billing déclare « acheté » est accepté. C'est plus faible (remboursements vus tardivement, exposition sur appareil rooté). Avec l'URL configurée, l'application interroge le backend, qui consulte l'API Google Play Developer.

### Fonctions réservées à Premium

Suppression des publicités, export DOCX, couleurs personnalisées des QR codes, assistant IA. La numérisation, l'export PDF/JPG, l'OCR, l'export TXT, les codes, les outils PDF et le coffre-fort restent gratuits.

## Publicités — ce que fait l'application

- Rien n'est demandé à AdMob avant que la plateforme de consentement de Google (UMP) ne l'autorise ; son formulaire s'affiche quand la région l'exige, et reste accessible depuis le profil.
- Le Premium est vérifié **avant** l'initialisation des publicités : un abonné ne voit ni formulaire ni annonce.
- **Bannière** adaptative sur l'accueil et la bibliothèque, dans son propre emplacement : elle ne recouvre jamais un document.
- **Interstitiel** uniquement après une tâche terminée (document enregistré, outil PDF achevé) ; jamais pendant la capture ni pendant un export. Plafonds : aucun pendant la première minute, au moins 3 minutes et 3 tâches entre deux, 4 par session.
- Sans identifiants fournis au build, les blocs de **test** officiels de Google sont utilisés. Aucun identifiant de production n'a été inventé.
- Un échec de chargement n'affecte jamais l'application.

Non réalisé : l'annonce avec récompense.

Variables de build : `ADMOB_BANNER_UNIT_ID`, `ADMOB_INTERSTITIAL_UNIT_ID`, `ADS_ENABLED`, et `ADMOB_APP_ID` pour le manifest (voir [installation.md](installation.md)).

## À fournir par l'éditeur

Compte AdMob et identifiants de blocs, produits créés dans la Play Console, testeurs de licence. Voir [google-play-release.md](google-play-release.md).
