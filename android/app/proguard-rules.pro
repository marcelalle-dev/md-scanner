# Règles R8 propres à MD SCANNER.
# Les plugins (ML Kit, Play Billing, Google Mobile Ads, AndroidX) embarquent leurs propres règles.

# Conserve les numéros de ligne pour des traces d'erreur exploitables, sans exposer les noms de fichiers.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
