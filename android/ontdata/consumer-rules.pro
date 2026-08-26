# Les règles que ce module impose à qui le consomme.
#
# `build.gradle.kts` les déclarait déjà — `consumerProguardFiles("consumer-rules.pro")` —
# mais le fichier n'existait pas. Le build `release` échouait donc avant même
# d'obfusquer : « Supplied consumer proguard configuration does not exist ».
# En `debug`, rien ne le disait, R8 n'y tournant pas.
#
# ## Pourquoi ici plutôt que dans l'app
#
# Les classes à préserver sont **celles de ce module**. Une règle écrite chez
# le consommateur oblige chaque consommateur à connaître les entrailles de sa
# dépendance, et à les suivre quand elles bougent. `app/proguard-rules.pro`
# couvrait `data.schema.**` et pas `data.store.**` — l'écart exact qu'une
# règle portée par le module supprime.
#
# ## Ce qui casserait sans elles
#
# `kotlinx.serialization` retrouve ses sérialiseurs par le nom de la classe et
# par son `Companion`. R8 les renomme, et le décodage ne lève qu'à
# l'exécution : le corpus ne s'ouvre plus, les réglages du lecteur reviennent
# à leur valeur par défaut à chaque lancement — et seulement en release.

-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**

# Le `Companion` porte l'accès au sérialiseur engendré.
-keepclassmembers class com.labibleont.ont.data.** {
    *** Companion;
}

# Le sérialiseur lui-même, pour toute classe qui en déclare un.
-keepclasseswithmembers class com.labibleont.ont.data.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# Les objets `@Serializable` et leurs champs : ce sont les noms des champs qui
# deviennent les clés du JSON. Les renommer réécrirait le fichier de réglages
# du lecteur à chaque mise à jour de l'obfuscation.
-keepclassmembers @kotlinx.serialization.Serializable class com.labibleont.ont.data.** {
    <fields>;
}
