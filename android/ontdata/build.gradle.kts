// Les adaptateurs — tout ce qui parle au monde extérieur.
//
// Le corpus embarqué et téléchargé, le client du backend Rust, le stockage des
// jetons. C'est ici qu'atterrit `Schema.kt`, engendré depuis `schema.rs` par le
// pipeline : des DTO, la forme du JSON et rien d'autre.
//
// ## Le sens de la dépendance
//
// Ce module dépend d'`ontkit` pour **implémenter** ses ports. Jamais l'inverse.
// Le domaine ne sait pas qu'il existe un réseau, un fichier, un cache — il
// connaît `CorpusRepository`, et quelqu'un le lui fournit.
//
// La traduction DTO → domaine vit dans `SchemaMapping.kt`, et c'est le seul
// endroit du dépôt où les deux formes se croisent. Un champ renommé dans le
// vault s'arrête donc là, au lieu de se propager jusqu'au cœur de l'app —
// c'était précisément le défaut que le chantier `codegen` a défait côté iOS.

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "com.labibleont.ont.data"
    compileSdk = 36

    defaultConfig {
        minSdk = 26
        consumerProguardFiles("consumer-rules.pro")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }
}

dependencies {
    api(project(":ontkit"))

    implementation(libs.core.ktx)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.ktor.client.core)
    implementation(libs.ktor.client.okhttp)
    implementation(libs.ktor.client.content.negotiation)
    implementation(libs.ktor.serialization.kotlinx.json)
    implementation(libs.datastore.preferences)
    // Le pendant du Keychain, pour les jetons du compte.
    implementation(libs.security.crypto)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}
