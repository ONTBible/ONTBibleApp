// Les écrans — lecture, lexique, recherche, vous.
//
// ## Ce module ne voit pas `ontdata`, et c'est le point
//
// Il n'y a pas de `project(":ontdata")` ci-dessous, et ce n'est pas un oubli.
// Un écran dépend de `CorpusRepository`, l'interface ; il ne sait pas si
// derrière il y a un fichier embarqué, un cache ou le réseau. C'est `app` qui
// tranche, au moment de câbler.
//
// Ce que ça achète : les modèles d'écran se testent sans émulateur, avec une
// doublure de trois lignes. C'est ce qui a donné 125 tests côté iOS, et il n'y
// a aucune raison d'en avoir moins ici.
//
// La discipline était tenue à la main en Swift — `ONTFeatures` n'importe que
// `ONTKit` et `ONTDesignSystem`, on l'a vérifié. Ici elle est tenue par le
// chemin de classes : `ontdata` n'y est pas, donc on ne peut pas l'appeler.

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.labibleont.ont.features"
    compileSdk = 36

    defaultConfig { minSdk = 26 }

    buildFeatures { compose = true }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }
}

dependencies {
    api(project(":ontkit"))
    api(project(":ontdesignsystem"))

    implementation(libs.core.ktx)
    implementation(libs.lifecycle.runtime.ktx)
    implementation(libs.lifecycle.viewmodel.compose)
    implementation(libs.navigation.compose)
    implementation(libs.compose.ui.tooling.preview)
    debugImplementation(libs.compose.ui.tooling)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation(libs.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.test.junit)
    debugImplementation(libs.compose.ui.test.manifest)
}
