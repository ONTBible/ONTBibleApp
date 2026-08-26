import java.io.File
import java.util.Properties

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

        versionCode = 1
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
}

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
