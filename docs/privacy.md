# Politique de confidentialité — MD SCANNER

*Dernière mise à jour : 27 novembre 2026.*

MD SCANNER est édité par MarcelAlle.Dev. Cette page décrit ce que fait réellement l'application.

## En résumé

- Vos documents restent **sur votre appareil**. L'application ne crée pas de compte.
- La version gratuite affiche des **publicités** Google, après recueil de votre consentement lorsque la loi l'exige.
- L'abonnement Premium est géré par **Google Play**.
- L'**assistant IA** n'envoie du texte hors de l'appareil que si vous l'acceptez expressément, à chaque première utilisation.

## Données traitées sur l'appareil uniquement

| Donnée | Usage |
| --- | --- |
| Photos, documents numérisés, PDF | Numérisation, traitement d'image, outils PDF |
| Texte reconnu (OCR) | Affichage, correction, recherche dans la bibliothèque |
| QR codes et codes-barres lus ou créés | Historique local, effaçable |
| Pièces d'identité | Images de travail supprimées à la fermeture de l'écran ; informations lues affichées mais jamais enregistrées. Seul le PDF que vous choisissez d'enregistrer est conservé |
| Noms des documents, favoris, préférences | Organisation et personnalisation |
| Code PIN du coffre-fort | Seule une empreinte irréversible est conservée, dans le stockage sécurisé du système |
| Documents du coffre-fort | Chiffrés (AES-256) ; la clé reste dans l'Android Keystore de l'appareil |

La reconnaissance de texte, la lecture des codes et le chiffrement fonctionnent **sans connexion**. Ces données ne sont pas transmises à l'éditeur.

## Données transmises à des tiers

### Publicité (version gratuite)

Les annonces sont fournies par **Google AdMob**. Le SDK Google Mobile Ads peut collecter l'identifiant publicitaire de l'appareil, des données techniques (modèle, système, langue), l'adresse IP et des données d'interaction avec les annonces.

- Avant toute demande d'annonce, l'application interroge la plateforme de consentement de Google et affiche son formulaire lorsque votre région l'exige.
- Vous pouvez modifier votre choix à tout moment dans *Profil → Choix de confidentialité publicitaire* lorsque cette option s'applique à votre région.
- Aucune publicité n'est affichée aux abonnés Premium, ni pendant une numérisation ou un export.

Règles de Google : https://policies.google.com/technologies/partner-sites

### Achats

Les achats passent par **Google Play Billing**. Google traite le paiement ; l'application ne voit jamais vos moyens de paiement. Elle reçoit un jeton d'achat pour vérifier votre abonnement ; seule une empreinte de ce jeton est conservée sur l'appareil.

### Assistant IA (Premium, facultatif)

L'assistant n'est actif que si l'éditeur a mis en service son serveur. Lorsqu'il l'est et que vous l'utilisez :

- seul le **texte** extrait du document est envoyé, jamais le fichier ;
- il transite par le serveur de MD SCANNER puis par un fournisseur d'intelligence artificielle, uniquement pour produire la réponse ;
- il n'y est pas conservé ;
- un identifiant d'installation aléatoire, sans lien avec votre identité, sert à limiter le nombre de demandes ;
- rien n'est envoyé sans votre accord explicite.

Le repérage local des dates et montants, proposé sur le même écran, fonctionne entièrement sur l'appareil.

### Scanner de documents de Google

L'interface de capture est fournie par les services Google Play ; les images sont traitées sur l'appareil. Conditions : https://developers.google.com/ml-kit/terms

## Autorisations Android

| Autorisation | Raison |
| --- | --- |
| Appareil photo | Numériser des documents et lire des codes |
| Internet, état du réseau | Publicités, vérification des achats, assistant IA |
| Biométrie | Déverrouiller le coffre-fort, si vous l'activez |
| Facturation Google Play | Achats Premium |
| Identifiant publicitaire | Publicité |

Aucune autorisation d'accès au stockage n'est demandée : l'import et l'export passent par les sélecteurs du système.

## Partage et sauvegarde

Un document ne quitte l'application que lorsque vous utilisez **Partager** ou **Exporter une sauvegarde**. La sauvegarde automatique d'Android est désactivée. Les documents du coffre-fort ne sont jamais inclus dans une sauvegarde.

## Suppression de vos données

- Documents : corbeille, puis suppression définitive.
- Historique des codes : *Outils → Historique des codes → Effacer*.
- Tout effacer : *Profil → Effacer toutes mes données* supprime documents, coffre-fort, historiques, code PIN et réglages. Désinstaller l'application a le même effet.

Si vous oubliez le code PIN du coffre-fort, son contenu ne peut pas être récupéré.

## Enfants

L'application ne s'adresse pas aux enfants de moins de 13 ans.

## Contact

https://github.com/marcelalle-dev/md-scanner/issues
