import java.io.File
import java.util.Properties
import java.time.LocalDateTime
import java.time.ZoneOffset

// La racine de composition — le seul module qui connaît tout le monde.
//
// C'est ici, et nulle part ailleurs, qu'une implémentation se branche sur un
// port : `ontdata` fournit, `ontfeatures` consomme, et les deux s'ignorent.
// Le jour où le corpus viendra d'ailleurs, c'est ce fichier qui change.

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

/**
 * La signature de téléversement.
 *
 * ## Le magasin n'est jamais dans le dépôt
 *
 * Il vit hors de l'arbre — `~/ONTBible/.cles/` sur la machine de l'auteur, un
 * secret GitHub en intégration. Committer une clé de signature, c'est la
 * publier : un dépôt privé se rend public, un fork se crée, un historique se
 * récupère. Elle ne se retire pas d'un historique git.
 *
 * ## Deux sources, dans cet ordre
 *
 * Les variables d'environnement d'abord — c'est ce que la CI fournit —, puis
 * `cle.properties` à la racine du module Android, pour la machine de l'auteur.
 * Aucune des deux : la configuration reste nulle et `assembleRelease` produit
 * un paquet non signé, ce qui est le comportement voulu pour qui clone le
 * dépôt sans avoir la clé.
 */
val proprietesDeCle = rootProject.file("cle.properties").let { f ->
    if (f.exists()) Properties().apply { f.inputStream().use { load(it) } } else null
}

fun secret(nomEnv: String, nomProp: String): String? =
    System.getenv(nomEnv) ?: proprietesDeCle?.getProperty(nomProp)

val magasinDeCles: File? = secret("ANDROID_KEYSTORE_PATH", "magasin")?.let(::File)?.takeIf { it.exists() }


/**
 * Le numéro de version, dérivé de l'horloge.
 *
 * ## Pourquoi ce n'est plus un nombre écrit à la main
 *
 * Play refuse un `versionCode` déjà téléversé, **définitivement** — y compris
 * celui d'une release de test supprimée. Le 1 a été brûlé le 27 août 2026, le 2
 * le 2 septembre.
 *
 * La consigne « à monter avant chaque téléversement » était juste et ne tenait
 * rien : c'est une étape que rien ne rappelle, dont l'oubli ne se voit qu'au
 * téléversement, et dont le message — « Version code has already been used » —
 * envoie chercher du côté de l'authentification quand on ne connaît pas la
 * règle. Avec des testeurs, on téléverse souvent ; on oubliera.
 *
 * ## La forme, et pourquoi elle tient jusqu'en 2040
 *
 *     (année − 2020) × 100 000 000
 *     + mois          ×   1 000 000
 *     + jour          ×      10 000
 *     + heure         ×         100
 *     + minute
 *
 * Le 3 septembre 2026 à 12 h 55 donne `609 031 255`. Play plafonne à
 * 2 100 000 000, ce que cette forme atteint en 2041 — largement au-delà de
 * l'horizon où quelqu'un relira cette ligne.
 *
 * La minute est la résolution : deux builds dans la même minute rendent le même
 * numéro, et le second sera refusé. C'est le seul cas de collision, il est
 * visible immédiatement, et il se règle en attendant soixante secondes.
 *
 * **`versionName` reste écrit à la main** : c'est ce que le lecteur lit, et rien
 * ne l'oblige à suivre un compteur.
 */
fun numeroDeVersion(): Int {
    val maintenant = LocalDateTime.now(ZoneOffset.UTC)
    return (maintenant.year - 2020) * 100_000_000 +
        maintenant.monthValue * 1_000_000 +
        maintenant.dayOfMonth * 10_000 +
        maintenant.hour * 100 +
        maintenant.minute
}

android {
    namespace = "com.labibleont.ont"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.labibleont.ont"

        // 26 — Android 8. Couvre le parc à ~99 %, et c'est le plancher en
        // dessous duquel les API de notification par canaux n'existent pas.
        // Or les canaux sont précisément ce qui règle, nativement, la
        // séparation « verset du jour » / « parutions » que la liseuse iOS a
        // dû construire à la main.
        minSdk = 26
        targetSdk = 36

        // ## Le numéro de version ne redescend jamais
        //
        // Play refuse un `versionCode` déjà téléversé, **définitivement** — y
        // compris celui d'une release de test supprimée. Le 1 a été consommé
        // le 27 août 2026 par la première release de test interne ; il est
        // brûlé pour toujours.
        //
        // À monter donc avant chaque téléversement, sans quoi la livraison
        // échoue sur « Version code 1 has already been used » — un message
        // qu'on cherche du côté de l'authentification quand on ne connaît pas
        // la règle.
        //
        // `versionName` ne suit pas le compteur — c'est ce que le lecteur lit,
        // et il a le droit de rester stable d'un build interne à l'autre.
        //
        // Mais il doit **bouger entre deux binaires téléversés**, et ça ne
        // l'avait pas été : les versions 1 et 2 portent toutes deux « 0.1.0 ».
        // Or c'est le seul numéro qui sorte jusqu'au testeur — la fiche Play,
        // les réglages du téléphone et « À propos de cette application »
        // n'affichent que lui, jamais le `versionCode`.
        //
        // Le 10 septembre 2026, une testeuse a signalé un défaut corrigé le
        // 28 août. Savoir si elle l'avait déjà demandait de savoir laquelle des
        // deux versions elle avait installée — et rien ne pouvait le dire, ni
        // chez elle, ni sur son téléphone, ni dans ce dépôt. Seule la Play
        // Console le savait, parce qu'elle est le seul écran qui montre le
        // `versionCode`.
        //
        // Un numéro que le lecteur voit et qui ne distingue pas deux binaires
        // ne renseigne personne : il ressemble à une version sans en être une.
        versionCode = numeroDeVersion()
        versionName = "0.1.1"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        create("televersement") {
            // Renseignée seulement si la clé est là. Sinon Gradle garderait une
            // configuration vide et échouerait à la signature plutôt qu'au
            // moment clair où l'on constate qu'il n'y a pas de clé.
            magasinDeCles?.let { fichier ->
                storeFile = fichier
                storePassword = secret("ANDROID_KEYSTORE_PASSWORD", "motDePasseDuMagasin")
                keyAlias = secret("ANDROID_KEY_ALIAS", "alias")
                keyPassword = secret("ANDROID_KEY_PASSWORD", "motDePasseDeLaCle")
            }
        }
    }

    buildTypes {
        release {
            // Nulle quand la clé est absente : le paquet sort non signé, et on
            // le voit au téléversement plutôt qu'au build.
            signingConfig = if (magasinDeCles != null) {
                signingConfigs.getByName("televersement")
            } else {
                null
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    buildFeatures {
        compose = true
        // `BuildConfig.DEBUG` distingue la build de développement de celle
        // qu'on livre. Depuis AGP 8, il n'est plus engendré par défaut : il
        // faut le demander, sinon la constante n'existe pas.
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }
}

/**
 * Les données du pipeline deviennent des assets.
 *
 * Une tâche plutôt qu'une copie commitée, pour la même raison que `Schema.kt`
 * n'est pas dans le dépôt : un fichier engendré qui vit à deux endroits finit
 * par diverger le jour où quelqu'un corrige l'un des deux. Ici, le corpus a une
 * seule source — `app/Resources/data`, ce que le pipeline écrit — et Android le
 * recopie à chaque build.
 *
 * La liseuse iOS lit exactement ces fichiers-là. Les deux ne peuvent donc pas
 * afficher deux textes différents.
 */
val donneesDuPipeline = layout.projectDirectory.dir("../../app/Resources/data")
val assetsEngendres = layout.buildDirectory.dir("generated/assets").get().asFile

tasks.register<Sync>("copierLesDonnees") {
    description = "Recopie le corpus produit par le pipeline dans les assets."
    from(donneesDuPipeline)
    into(File(assetsEngendres, "data"))


    // ## Les chuqqot non plus — et c'est la seconde fois en trois jours
    //
    // `chuqqot.json` est arrivé le 10 septembre 2026. iOS en a un onglet entier
    // — `ChuqqotFeature/Presentation/ChuqqotTab.swift`, six fichiers Swift —,
    // Android n'a que le mot dans trois commentaires, dont un de `MainActivity`
    // qui dit lui-même « les chuqqot n'ont pas encore d'écran ».
    //
    // Ce n'est plus un accident isolé : deux documents neufs du pipeline en
    // trois jours, tous deux arrivés jusqu'aux ressources d'Android sans lecteur.
    // Le glob de `corpus.sh` les fait entrer, et seul `verifierLeCorpus` les
    // arrête. Le portage de cette garde en amont, décidé par l'auteur, vaut pour
    // les trois clients à la fois — ici on ne peut que refuser la copie.
    //
    // **Écart de parité, pas décision.** Le jour où Android saura les lire,
    // cette ligne disparaît.
    exclude("chuqqot.json")
    // **Les langues sources, même raison et même date qu'au-dessus.**
    //
    // `corpus.sh` embarque `sources/he-wlc` depuis le 11 septembre 2026, sur
    // décision de l'auteur : l'hébreu n'est pas une langue source parmi
    // d'autres, c'est la langue de presque tout le corpus, et le mettre à la
    // demande revenait à mettre la fonctionnalité à la demande.
    //
    // Ce que le commentaire ci-dessous annonçait est donc arrivé, mot pour
    // mot : une ligne ajoutée dans un script partagé, pour le bénéfice d'iOS,
    // et 476 Ko qui atterrissent ici sans qu'aucune décision ait été prise de
    // ce côté-ci. Android ne sait pas encore lire ce dossier — l'exclure est
    // exact, l'embarquer serait mentir.
    //
    // **Écart de parité, pas décision.** Le jour où Android ouvrira le verset
    // d'origine, ces deux lignes disparaissent et `sources` rejoint
    // `connusDuCorpus`.
    exclude("sources/**")
}

/**
 * Ce que le pipeline embarque et que personne ne lit.
 *
 * ## Le silence que cette tâche brise
 *
 * `Sync` recopie **tout** `app/Resources/data` dans les assets. Ce dossier est
 * peuplé par `corpus.sh`, qui nomme ce qu'il prend — les `.json` de `dist` et
 * `dist/books` —, donc un dossier neuf du pipeline n'y arrive pas tout seul.
 *
 * (Le motif du script ne s'écrit pas ici tel quel : **Kotlin imbrique les
 * commentaires de bloc**, donc un `/` suivi d'une étoile ouvrirait un
 * commentaire dans le commentaire, et le `*` `/` final ne refermerait que
 * celui-là. Tout le code en dessous se retrouve avalé — sans erreur de
 * compilation, seulement une tâche que Gradle ne trouve plus.)
 *
 * **Le couplage est ailleurs, et il est plus discret :** le jour où `corpus.sh`
 * copiera une chose de plus, pour le bénéfice d'iOS par exemple, elle atterrira
 * ici et Android l'embarquera. Aucune décision n'aura été prise de ce côté-ci —
 * seulement une ligne ajoutée dans un script partagé par les deux liseuses.
 *
 * Le compilateur ne dira rien, parce qu'il n'y a rien à compiler : un fichier
 * n'a pas de type. C'est l'exact contraire d'un nœud ajouté à `schema.rs`, qui
 * traverse jusqu'à un `when` exhaustif et fait rougir la compilation.
 *
 * Le chantier des langues sources, ouvert le 7 septembre 2026, produira
 * `dist/sources/` — un fichier par livre et par témoin, 52 Mo. iOS l'exclut par
 * dessein : ces textes se téléchargent à la demande et ne s'embarquent jamais.
 * Si cette décision changeait un jour d'un seul côté, c'est ici qu'on
 * l'apprendrait.
 *
 * ## Une raison fausse a précédé celle-ci
 *
 * La première version de ce commentaire disait « `Sync` recopie tout `dist/` ».
 * C'était surestimer le risque et se tromper de mécanisme. La session macOS l'a
 * fait apparaître en vérifiant son propre côté du mur — et en constatant que
 * `corpus.sh` filtre, j'ai vu que mon défaut n'était pas celui que j'annonçais.
 *
 * La garde reste juste ; sa justification ne l'était pas.
 *
 * ## Pourquoi une liste et non une exclusion
 *
 * Exclure ce qu'on ne connaît pas laisserait passer la prochaine arrivée sans
 * rien dire, ce qui est le défaut qu'on ferme. La liste **nomme ce qu'on lit**,
 * et tout le reste arrête le build en se nommant.
 *
 * Ajouter une entrée ici n'est pas une formalité : c'est déclarer qu'un lecteur
 * existe. Le faire sans l'écrire rendrait cette tâche muette.
 */
val connusDuCorpus = setOf(
    "books", "corpus.json", "daily.json", "glossary.json",
    // `report.md` a quitté cette liste le 14 septembre 2026, trouvé par la
    // seconde moitié de la garde à son premier tour. Il n'arrive jamais dans les
    // assets — `corpus.sh` copie `dist/*.json`, et c'est un `.md` — et aucune
    // ligne de Kotlin ne l'ouvre. Il y figurait donc en déclarant un lecteur qui
    // n'a jamais existé, sur un fichier qui n'a jamais été copié : les deux
    // moitiés fausses à la fois, ce qui est précisément ce qui le rendait
    // invisible.
    "manifest.json", "occurrences.json", "search.json",
    "shemot.json",
    // **Lu depuis le 12 septembre 2026**, par `DiskPrononciationRepository`.
    // Il figurait ici sous un commentaire disant « exclu de la copie plutôt que
    // lu » — la garde le tolérait sans qu'un lecteur existe, et c'est exactement
    // la limite qu'elle porte : inscrire un nom **déclare** qu'un lecteur
    // existe, et rien ne vérifie que la déclaration est vraie. Elle était fausse
    // pendant quatre jours (#263).
    "prononciation.json",
    // Exclu de la copie plutôt que lu — voir `copierLesDonnees`. Il figure ici
    // pour que la garde ne redise pas ce qui est déjà tranché, et le commentaire
    // de l'exclusion porte la raison.
    "chuqqot.json",
    "sources",
)

/**
 * Ce qui est **volontairement** exclu du paquet, faute de lecteur.
 *
 * Une liste séparée de [connusDuCorpus], et non un drapeau dans celle-ci : les
 * deux disent des choses opposées. Y figurer veut dire « le pipeline l'émet,
 * Android ne sait pas le lire, et c'est consigné » — chaque nom a son issue
 * ouverte et le commentaire de son `exclude` porte la raison.
 *
 * Un nom qui quitte cette liste doit avoir gagné un lecteur le même jour.
 */
val exclusDeLaCopie = setOf(
    "chuqqot.json", // #273 — iOS a un onglet entier, Android n'a pas d'écran
    "sources", // les langues sources, même date et même raison
)

tasks.register("verifierLeCorpus") {
    description = "Refuse d'embarquer un fichier du pipeline que rien ne lit."
    // Des valeurs simples, capturées à la configuration : le cache de
    // configuration ne sait pas sérialiser une référence à un objet du script,
    // et refuse le build entier plutôt que de la perdre en silence.
    val dossier = donneesDuPipeline.asFile
    val connus = connusDuCorpus.toSet()
    // Capturée ici comme `connus`, et pour la même raison exactement : la lire
    // depuis `doLast` en ferait une référence au script, que le cache de
    // configuration refuse de sérialiser. Le commentaire ci-dessus l'annonçait,
    // et je l'ai quand même posée dans le bloc — la règle était écrite trois
    // lignes plus haut.
    val exclus = exclusDeLaCopie.toSet()
    doLast {
        val inattendus = dossier.listFiles()
            .orEmpty()
            .map { it.name }
            .filterNot { it in connus || it.startsWith(".") }
            .sorted()
        // ## Ce que la liste seule ne peut pas voir
        //
        // `connusDuCorpus` compare des **noms**. Inscrire un nom y *déclare*
        // qu'un lecteur existe, et rien ne vérifie que la déclaration est vraie :
        // `prononciation.json` y figurait depuis le 8 septembre 2026, exclu de la
        // copie, sans qu'aucune ligne de Kotlin ne l'ouvre — quatre jours, et la
        // garde verte tout du long (#263).
        //
        // D'où la seconde moitié : un fichier **inscrit aux connus et absent des
        // assets** est un lecteur déclaré qui n'a rien à lire. Les deux cas sont
        // des pannes opposées, et une liste ne peut nommer que le premier.
        //
        // Les exclusions assumées sont retirées de la comparaison : elles disent
        // « pas de lecteur, et on le sait ». C'est ce qui distingue un écart
        // consigné d'un oubli.
        // **On mesure `dist/`, pas les assets** — et c'est le piège qu'on a
        // failli poser ici. Cette tâche est une *dépendance* de
        // `copierLesDonnees` : elle tourne **avant** la copie. Lire
        // `generated/assets` y rendrait le résultat du build précédent, ou rien
        // du tout sur un arbre neuf — un contrôle vert parce qu'il regarde un
        // dossier qui n'existe pas encore.
        //
        // La question « ce nom arrivera-t-il dans le paquet ? » se répond donc
        // sur la source et la règle : présent dans `dist/`, et non exclu.
        val emis = dossier.listFiles().orEmpty().map { it.name }.toSet()
        val declaresSansEtreCopies = (connus - emis - exclus).sorted()

        if (declaresSansEtreCopies.isNotEmpty()) {
            throw GradleException(
                buildString {
                    appendLine("Android déclare lire ce que le pipeline n'émet pas :")
                    declaresSansEtreCopies.forEach { appendLine("    $it") }
                    appendLine()
                    appendLine("Le nom figure à `connusDuCorpus` — ce qui déclare qu'un lecteur")
                    appendLine("existe — mais le pipeline ne l'émet pas. Le lecteur lira donc")
                    appendLine("le vide, en silence.")
                    appendLine()
                    appendLine("Deux sorties :")
                    appendLine("  · le pipeline ne l'émet plus → retirer le nom des connus ;")
                    appendLine("  · il est exclu volontairement → l'inscrire à `exclusDeLaCopie`,")
                    appendLine("    qui dit « pas de lecteur, et on le sait ».")
                },
            )
        }

        if (inattendus.isNotEmpty()) {
            throw GradleException(
                buildString {
                    appendLine("Le pipeline produit ce qu'Android embarquerait sans le lire :")
                    inattendus.forEach { appendLine("    $it") }
                    appendLine()
                    appendLine("Ces fichiers partiraient dans le paquet, chez le lecteur, sans")
                    appendLine("qu'aucune ligne ne les ouvre — et rien ne l'aurait signalé.")
                    appendLine()
                    appendLine("Deux sorties, jamais une troisième :")
                    appendLine("  · écrire le lecteur, puis ajouter le nom à `connusDuCorpus` ;")
                    appendLine("  · exclure explicitement le dossier de `copierLesDonnees`,")
                    appendLine("    en disant pourquoi — pour ne pas l'embarquer en attendant.")
                },
            )
        }
    }
}

tasks.named("copierLesDonnees") { dependsOn("verifierLeCorpus") }

// Un `File` et non un `Provider` : l'API des sources Android refuse les
// seconds, parce qu'Android Studio doit pouvoir dire à l'indexation où sont les
// fichiers sans exécuter le build.
android.sourceSets.getByName("main").assets.directories.add(assetsEngendres.path)

// Tout ce qui lit ce dossier doit attendre qu'il soit rempli — pas seulement
// la fusion des assets.
//
// Le lint de `release` le lit aussi, et lui ne l'attendait pas : Gradle
// refusait le build entier avec « uses this output without declaring an
// explicit or implicit dependency ». Invisible en `debug`, où le lint fatal ne
// tourne pas — c'est-à-dire invisible jusqu'au jour de la livraison.
//
// La condition liste des noms de tâches parce que l'API propre ne s'applique
// pas ici : `addGeneratedSourceDirectory` veut un `Provider`, et la source doit
// rester un `File` pour qu'Android Studio sache indexer sans lancer le build —
// c'est la raison écrite juste au-dessus. Si une version d'AGP renomme ses
// tâches, le symptôme sera le même message, et c'est cette ligne qu'il faudra
// élargir.
tasks.matching {
    (it.name.startsWith("merge") && it.name.endsWith("Assets")) || it.name.contains("lint", ignoreCase = true)
}.configureEach { dependsOn("copierLesDonnees") }

dependencies {
    implementation(libs.sentry.android)
    implementation(libs.browser)
    implementation(project(":ontkit"))
    implementation(project(":ontdata"))
    implementation(project(":ontdesignsystem"))
    implementation(project(":ontfeatures"))

    implementation(libs.core.ktx)
    implementation(libs.lifecycle.runtime.ktx)
    implementation(libs.activity.compose)
    implementation(libs.navigation.compose)
    implementation(libs.compose.material3.navigation.suite)
    implementation(libs.compose.material.icons)

    // Le verset du jour sur l'écran d'accueil, et le réveil qui le pose.
    implementation(libs.glance.appwidget)
    implementation(libs.glance.material3)
    implementation(libs.work.runtime.ktx)

    testImplementation(libs.junit)
    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation(libs.androidx.test.junit)
    androidTestImplementation(libs.compose.ui.test.junit4)
    debugImplementation(libs.compose.ui.test.manifest)
}
