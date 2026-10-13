# Flutter embarque déjà ses règles ; on garde seulement les classes du moteur
# Flutter et des plugins chargées par réflexion.
-keep class io.flutter.** { *; }
-keep class com.mainlyb.chabaka.** { *; }
-dontwarn io.flutter.embedding.**
