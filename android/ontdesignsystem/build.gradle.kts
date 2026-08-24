// La peau — couleurs, typographie, surfaces, et le rendu des trois niveaux.
//
// ## Ce module ne décide rien, il rend
//
// Il ne connaît ni le réseau ni les cas d'usage. Il sait composer un verset,
// une carte, un intraduisible — à partir de ce qu'on lui donne. C'est ce qui
// permet d'en montrer un catalogue complet sans lancer l'app, comme le fait
// `DSCatalog` côté iOS.
//
// ## La marque ne se décline pas par plateforme
//
// Le bordeaux **#421B26** et l'or **#CDBE83** sont relevés au pixel sur le
// combination mark ; la nuit **#18090D** vient du `--color-nuit` du site. Ces
// valeurs sont les mêmes ici, à l'entier près : l'app iOS, le site et Android
// ne se **ressemblent** pas, ils emploient la même palette.
//
// D'où le refus assumé de **Material You** : la couleur dynamique repeindrait
// l'app aux teintes du fond d'écran de l'utilisateur. C'est la meilleure idée
// de Material 3 et elle est ici la seule à écarter — un lecteur qui ouvre l'ONT
// doit y trouver l'ONT.
//
// Ce qu'on prend de Material 3, en revanche : les gestes et les composants
// système — feuilles du bas, ondulations, `predictive back`. La peau est à
// nous, les habitudes sont à la plateforme.
//
// ## `ONTTextRenderer` est le morceau critique
//
// Corps, gloses `*[entre crochets]*`, translittération `(*translit* / hébreu)`.
// Les trois niveaux ne s'aplatissent pas — c'est le §2.1 du CLAUDE.md, et c'est
// le produit lui-même. Son pendant Compose doit rendre à l'identique de Swift,
// et c'est là-dessus que les captures comparées feront foi.

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.labibleont.ont.designsystem"
    compileSdk = 36

    defaultConfig { minSdk = 26 }

    buildFeatures { compose = true }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }
}

dependencies {
    // Le domaine, pour les types que la peau doit savoir rendre —
    // `ReadingTheme`, `Inline`, `Block`. Pas d'accès aux données.
    api(project(":ontkit"))

    val composeBom = platform(libs.compose.bom)
    api(composeBom)
    api(libs.compose.ui)
    api(libs.compose.ui.graphics)
    api(libs.compose.material3)
    implementation(libs.compose.material.icons)
    implementation(libs.compose.ui.tooling.preview)
    debugImplementation(libs.compose.ui.tooling)

    testImplementation(libs.junit)
    androidTestImplementation(composeBom)
    androidTestImplementation(libs.compose.ui.test.junit4)
    debugImplementation(libs.compose.ui.test.manifest)
}
