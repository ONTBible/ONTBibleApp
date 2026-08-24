// La racine de composition — le seul module qui connaît tout le monde.
//
// C'est ici, et nulle part ailleurs, qu'une implémentation se branche sur un
// port : `ontdata` fournit, `ontfeatures` consomme, et les deux s'ignorent.
// Le jour où le corpus viendra d'ailleurs, c'est ce fichier qui change.

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
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

        versionCode = 1
        versionName = "0.1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    buildFeatures { compose = true }

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

tasks.matching { it.name.startsWith("merge") && it.name.endsWith("Assets") }
    .configureEach { dependsOn("copierLesDonnees") }

dependencies {
    implementation(project(":ontkit"))
    implementation(project(":ontdata"))
    implementation(project(":ontdesignsystem"))
    implementation(project(":ontfeatures"))

    implementation(libs.core.ktx)
    implementation(libs.lifecycle.runtime.ktx)
    implementation(libs.activity.compose)
    implementation(libs.navigation.compose)
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
