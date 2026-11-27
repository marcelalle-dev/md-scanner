# Sécurité

Ce document décrit ce qui est **en place** et ses limites. Le chiffrement et le code PIN sont couverts par des tests sur poste de développement ; la biométrie et l'Android Keystore ne s'exécutent que sur un appareil et restent à valider.

## En place

### Stockage

- Les documents sont enregistrés dans le stockage **privé** de l'application, inaccessible aux autres applications sur un appareil non rooté.
- Les fichiers portent des noms UUID ; le nom choisi par l'utilisateur ne figure que dans la base.
- `FileStorage.absolutePath()` rejette tout chemin qui sortirait de la racine de stockage. La restauration d'une sauvegarde refuse de même les entrées d'archive malveillantes (« zip-slip »).
- La sauvegarde automatique d'Android est désactivée : aucun document n'est copié dans le cloud à l'insu de l'utilisateur.

### Autorisations

- Caméra et Internet uniquement. Aucune autorisation de stockage : l'import et l'export passent par les sélecteurs du système.
- La caméra est déclarée facultative : l'application s'installe sur un appareil qui n'en a pas.

### PDF protégés

- Protection par mot de passe en AES-256 (PDF 2.0, révision 6).
- Le mot de passe saisi n'est ni enregistré ni journalisé.
- Un PDF protégé n'est déverrouillé que si l'utilisateur fournit le bon mot de passe.

### Journalisation

`AppLogger` n'accepte que des compteurs, durées, booléens et énumérations : un nom de fichier, un texte ou un chemin ne peut pas s'y retrouver. Les `Failure` ne transportent que le type de l'exception d'origine, jamais son message.

### Fichiers temporaires

Les fichiers de travail sont supprimés à la fin de chaque opération, y compris en cas d'échec. Un nettoyage au démarrage purge les restes éventuels.

### Code et dépôt

- Aucun secret dans le code ni dans le dépôt. `android/key.properties` et les keystores sont ignorés par Git.
- Les secrets de signature de la CI ne sont lus que depuis les secrets GitHub et supprimés du runner après le build.
- R8 est activé en release.

### Coffre-fort

- **Code PIN** de 4 à 8 chiffres, jamais stocké : seule une empreinte Argon2id (19 Mio, 2 passes) avec sel aléatoire est conservée, dans le stockage sécurisé adossé à l'Android Keystore. La comparaison se fait en temps constant.
- **Tentatives limitées** : après 5 échecs, blocage de 30 secondes, doublé à chaque nouvel échec jusqu'à 15 minutes. Le compteur survit au redémarrage de l'application.
- **Chiffrement des fichiers** en AES-256-GCM par blocs de 1 Mio, sans jamais charger le fichier entier en mémoire. Chaque bloc authentifie l'en-tête, son rang et un indicateur de fin : modification, permutation de blocs et troncature sont détectées.
- **Clé** aléatoire de 256 bits, générée une fois et conservée par le stockage sécurisé. Elle n'est pas dérivée du code PIN : changer de code ne rechiffre rien. Le code PIN protège l'accès dans l'application, le Keystore protège la clé au repos.
- **Aperçu** : un document du coffre est déchiffré dans un fichier temporaire, supprimé dès le verrouillage.
- **Verrouillage** automatique dès que l'application passe en arrière-plan ou que l'on quitte le coffre.
- **Captures d'écran** bloquées (`FLAG_SECURE`) tant que le coffre est affiché.
- **Biométrie** facultative, comme raccourci du code PIN (invite système AndroidX, biométrie seule).
- Les documents du coffre sont exclus des sauvegardes et retirés de la bibliothèque, vignette comprise.

### Verrouillage de l'application

Facultatif (menu du coffre-fort). Lorsqu'il est activé et qu'un code PIN existe, un écran de saisie recouvre toute l'application au lancement et à chaque retour d'arrière-plan ; il est placé au-dessus de la navigation, de sorte qu'aucun écran n'est atteignable avant le déverrouillage.

### Pièces d'identité

Les images d'une pièce d'identité sont des copies de travail supprimées dès la fermeture de l'écran ; rien n'est conservé sans enregistrement explicite. Les captures d'écran sont bloquées sur cet écran. Les informations lues ne sont ni stockées ni journalisées, et l'application ne se prononce jamais sur l'authenticité d'un document.

### Liens scannés

Un lien lu dans un QR code n'est jamais ouvert automatiquement. L'adresse complète est affichée avec un avis établi localement (http sans chiffrement, adresse IP, caractères trompeurs, identifiant caché, lien raccourci, téléchargement de programme…). Les schémas capables d'exécuter du code ou de lire des données locales (`javascript:`, `data:`, `file:`, `intent:`, `content:`…) sont bloqués.

### Achats

Le jeton d'achat n'est jamais écrit sur disque : seule son empreinte SHA-256 l'est. Le statut Premium n'est accordé qu'après vérification et retiré dès que Google Play ne confirme plus l'achat.

## Limites connues

- Le code PIN est court par nature : sa résistance repose sur la limitation des tentatives et sur le Keystore, pas sur son entropie.
- Un appareil rooté ou compromis sort du périmètre de protection.
- Code PIN oublié : le contenu du coffre est irrécupérable, par conception.
- Sans serveur de vérification, les achats sont vérifiés sur l'appareil : les remboursements ne sont détectés que lorsque Google Play cesse de renvoyer l'achat.
- Aucun audit de sécurité externe n'a été réalisé, et aucun essai sur appareil.
- Le plugin `cryptography_flutter`, qui accélère AES-GCM sur Android, utilise un mode de build Kotlin que de futures versions de Flutter refuseront ; il faudra le mettre à jour ou le remplacer.
- Non réalisé : effacement global des données depuis l'application.

## Signaler une faille

Ouvrir un ticket : https://github.com/marcelalle-dev/md-scanner/issues (sans y publier de détail exploitable ; indiquez seulement qu'il s'agit d'un sujet de sécurité).
