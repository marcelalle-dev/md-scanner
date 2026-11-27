# Monétisation

> **État : non implémenté.** La version actuelle n'affiche aucune publicité et ne propose aucun achat. Ce document fixe le modèle retenu et ce qui est déjà préparé.

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

## Déjà en place

- Dépendances `in_app_purchase` et `google_mobile_ads` déclarées ; l'application se construit avec elles.
- Identifiant d'application AdMob injecté dans le manifest au build. Par défaut : l'identifiant d'exemple public de Google, qui ne sert que des annonces de test. Aucun identifiant de production n'a été inventé.
- Contrat d'abonnement (`lib/shared/providers/entitlement.dart`) : l'état Premium porte sa **provenance** (`playStore`, `server`, `offlineGrace`) et ne peut être écrit que par le futur service de facturation — jamais par un simple indicateur local.
- Table `subscription_cache` : dernier état vérifié, avec l'empreinte SHA-256 du jeton d'achat, jamais le jeton.
- Variables de build prévues : `ADMOB_BANNER_UNIT_ID`, `ADMOB_INTERSTITIAL_UNIT_ID`, `ADMOB_REWARDED_UNIT_ID`, `PURCHASE_VERIFICATION_URL`.

## Règles à respecter lors de l'implémentation

### Achats

- Vérifier un achat **avant** d'accorder le Premium, et ne l'acquitter qu'après vérification.
- Réinterroger Google Play à chaque démarrage : un abonnement que Play ne renvoie plus est révoqué.
- Hors connexion, tolérer le dernier état vérifié pendant 3 jours au plus.
- Prévoir la vérification serveur (API Google Play Developer), seule à détecter les remboursements.
- Afficher prix, période, conditions de renouvellement, bouton de restauration et lien de gestion de l'abonnement.

### Publicités

- Bannière discrète, interstitiel plafonné, annonce avec récompense.
- Jamais pendant la capture, jamais pendant un export, jamais par-dessus un document.
- Aucune annonce pour les abonnés Premium.
- Recueil du consentement (plateforme UMP de Google) avant toute demande d'annonce.
- Identifiants de test pendant le développement ; ne jamais cliquer sur ses propres annonces.

## À fournir par l'éditeur

Compte AdMob et identifiants de blocs, produits créés dans la Play Console, testeurs de licence. Voir [google-play-release.md](google-play-release.md).
