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

# Tink — la bibliothèque de chiffrement sous `EncryptedSharedPreferences`, où
# vivent les jetons du compte — est annotée avec `com.google.errorprone.*`.
#
# Ces annotations sont des **outils de compilation** : `@CanIgnoreReturnValue`,
# `@Immutable`, `@CheckReturnValue` servent à l'analyse statique et ne sont
# volontairement pas embarquées à l'exécution. R8 les voit référencées, ne les
# trouve pas, et **échoue** — pas d'avertissement, un échec net :
#
#     Missing class com.google.errorprone.annotations.CanIgnoreReturnValue
#     (referenced from: com.google.crypto.tink.KeysetManager … et 52 autres)
#
# ## Pourquoi ça n'est apparu que le 3 septembre
#
# `security-crypto` est déclaré depuis le portage du 24 août, mais **personne ne
# s'en servait**. R8 élague ce qui n'est pas atteint : tink n'entrait pas dans le
# graphe, donc ses annotations manquantes ne regardaient personne. La carte du
# bundle du 2 septembre le confirme — zéro occurrence de `com.google.crypto.tink`.
#
# Le 3 septembre, le coffre à jetons (#208) a employé `EncryptedSharedPreferences`
# pour la première fois. Tink est devenu atteignable, et le bundle de publication
# a cessé de se construire — pendant sept jours, sans que rien ne le dise.
#
# ## Ce qui l'a laissé passer
#
# La CI lance `./gradlew test`, qui compile en **debug**, où R8 ne tourne pas. Ce
# fichier porte déjà deux fois cette phrase, pour `kotlinx.serialization` et pour
# Room. C'est la troisième fois, et la première où l'app n'était plus livrable du
# tout.
#
# Une dépendance déclarée mais inutilisée est invisible à ce contrôle : c'est le
# jour où on s'en sert qu'elle amène toute sa surface avec elle.
-dontwarn com.google.errorprone.annotations.**
