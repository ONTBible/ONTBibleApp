# `kotlinx.serialization` engendre des sérialiseurs par réflexion sur les noms
# de classes : R8 les renommerait, et le corpus ne se décoderait plus qu'en
# release — le pire moment pour l'apprendre.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class com.labibleont.ont.data.schema.** {
    *** Companion;
}
-keepclasseswithmembers class com.labibleont.ont.data.schema.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# Room engendre une implémentation par base — `WorkDatabase_Impl` pour celle
# que WorkManager tient — et l'instancie par réflexion, via son constructeur
# sans argument. R8 ne voit personne l'appeler et le supprime.
#
# Le symptôme n'est pas discret mais il est tardif : l'app **ne démarre pas**.
# `androidx.startup.InitializationProvider` échoue avant la première image, sur
# `NoSuchMethodException: androidx.work.impl.WorkDatabase_Impl.<init> []`. Rien
# ne le montre en debug, où R8 ne tourne pas — c'est-à-dire jusqu'au jour de la
# livraison, et Play accepterait le téléversement sans rien dire.
#
# WorkManager sert le verset du jour ; retirer la règle revient à retirer l'app.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep @androidx.room.Database class * { *; }
