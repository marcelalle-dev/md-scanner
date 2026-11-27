# Règles R8 propres à MD SCANNER.
# Les plugins (ML Kit, Play Billing, Google Mobile Ads, AndroidX) embarquent leurs propres règles.

# Conserve les numéros de ligne pour des traces d'erreur exploitables, sans exposer les noms de fichiers.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# google_mlkit_text_recognition référence les reconnaisseurs chinois, devanagari, japonais et coréen,
# qui sont des dépendances facultatives. MD SCANNER n'embarque que le modèle latin (français, anglais) :
# ces classes sont volontairement absentes et ne sont jamais chargées.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
