# Sécurité

Ce document décrit ce qui est **en place** et ce qui est **prévu**. Le coffre-fort, le code PIN et la biométrie ne sont pas encore développés.

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

## Prévu

| Fonction | Conception retenue |
| --- | --- |
| Code PIN | Jamais stocké : empreinte Argon2id avec sel aléatoire, limitation des tentatives persistante |
| Biométrie | Invite système AndroidX, biométrie seule |
| Coffre-fort | Chiffrement AES-256-GCM par blocs avec clé conservée via l'Android Keystore |
| Protection d'écran | `FLAG_SECURE` sur les écrans sensibles — le canal natif existe déjà |
| Effacement des données | Suppression des documents, de la base et des clés |

## Limites connues

- Sans coffre-fort, un document n'est protégé que par le bac à sable d'Android et le verrouillage de l'appareil.
- Aucun audit de sécurité externe n'a été réalisé.
- Le plugin `cryptography_flutter`, déclaré pour le futur coffre-fort, utilise un mode de build Kotlin que de futures versions de Flutter refuseront ; il faudra le mettre à jour ou le remplacer.

## Signaler une faille

Ouvrir un ticket : https://github.com/marcelalle-dev/md-scanner/issues (sans y publier de détail exploitable ; indiquez seulement qu'il s'agit d'un sujet de sécurité).
