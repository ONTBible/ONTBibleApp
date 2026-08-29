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

/**
 * Les fontes du projet deviennent des ressources Android.
 *
 * Mêmes fichiers que la liseuse iOS — `app/Resources/Fonts` — recopiés à chaque
 * build plutôt que dupliqués dans le dépôt. Deux copies d'une fonte finissent
 * par ne plus être la même fonte le jour où l'une est mise à jour. Le dossier
 * d'arrivée est donc ignoré par git, comme `Schema.kt` et comme `dist/`.
 *
 * Le renommage n'est pas cosmétique : Android exige qu'un nom de ressource soit
 * en minuscules avec des soulignés. `Literata-SemiBold.ttf` ne compile pas,
 * `literata_semibold.ttf` oui. On le fait ici plutôt qu'en renommant les
 * fichiers, pour que les deux plateformes lisent le même dossier.
 *
 * On écrit dans `src/main/res/font` plutôt que dans un dossier engendré ajouté
 * aux sources : sur un module bibliothèque, AGP 9 refuse qu'on touche à
 * `sourceSets` après coup. Écrire à l'endroit attendu évite l'API entière.
 *
 * Les licences OFL ne sont pas recopiées : ce ne sont pas des ressources
 * Android, et la fiche Play les portera comme la fiche App Store les porte.
 */
val fontesDuProjet = layout.projectDirectory.dir("../../app/Resources/Fonts")

val copierLesFontes = tasks.register<Sync>("copierLesFontes") {
    description = "Recopie les fontes OFL du projet en ressources Android."
    from(fontesDuProjet) { include("*.ttf") }
    into(layout.projectDirectory.dir("src/main/res/font"))
    rename { nom ->
        nom.replace("-", "_")
            .replace(Regex("([a-z0-9])([A-Z])"), "$1_$2")
            .lowercase()
    }
}

tasks.configureEach {
    if (name.startsWith("preBuild") || name.contains("Resources") || name.contains("Assets")) {
        dependsOn(copierLesFontes)
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
    // `WindowCompat`, pour que le thème règle lui-même la polarité des
    // icônes de barre système — voir `ONTTheme`.
    implementation(libs.core.ktx)
    implementation(libs.compose.material.icons)
    implementation(libs.compose.ui.tooling.preview)
    debugImplementation(libs.compose.ui.tooling)

    testImplementation(libs.junit)
    androidTestImplementation(composeBom)
    androidTestImplementation(libs.compose.ui.test.junit4)
    debugImplementation(libs.compose.ui.test.manifest)
}
