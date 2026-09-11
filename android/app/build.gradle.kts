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
        // `versionName` est libre, lui : c'est ce que le lecteur lit, et rien
        // ne l'oblige à suivre le compteur.
        versionCode = numeroDeVersion()
        versionName = "0.1.0"

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

    // ## Le guide de prononciation n'est pas lu par Android
    //
    // `corpus.sh` copie `dist/*.json` — un **glob**, pas une liste. Tout
    // nouveau document du pipeline entre donc dans les ressources sans que
    // personne l'ait décidé, et de là dans le paquet de tous les lecteurs.
    //
    // C'est ce qui vient d'arriver : `prononciation.json`, seize kilo-octets
    // qu'iOS lit dans sept fichiers et qu'Android n'ouvre nulle part.
    // `verifierLeCorpus` l'a arrêté — c'est exactement ce pour quoi il existe.
    //
    // On exclut plutôt que de l'inscrire aux connus : inscrire déclare qu'un
    // lecteur existe, et ce serait faux.
    //
    // **C'est un écart de parité, pas une décision** — voir l'issue ouverte le
    // 8 septembre. Le jour où Android saura le lire, cette ligne disparaît et
    // le nom rejoint `connusDuCorpus`.
    exclude("prononciation.json")
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
    "manifest.json", "occurrences.json", "report.md", "search.json",
    "shemot.json",
    // Exclus de la copie plutôt que lus — voir `copierLesDonnees`. Ils figurent
    // ici pour que la garde ne redise pas ce qui est déjà tranché, et les
    // commentaires des exclusions portent la raison.
    "prononciation.json",
    "sources",
)

tasks.register("verifierLeCorpus") {
    description = "Refuse d'embarquer un fichier du pipeline que rien ne lit."
    // Des valeurs simples, capturées à la configuration : le cache de
    // configuration ne sait pas sérialiser une référence à un objet du script,
    // et refuse le build entier plutôt que de la perdre en silence.
    val dossier = donneesDuPipeline.asFile
    val connus = connusDuCorpus.toSet()
    doLast {
        val inattendus = dossier.listFiles()
            .orEmpty()
            .map { it.name }
            .filterNot { it in connus || it.startsWith(".") }
            .sorted()
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
