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
