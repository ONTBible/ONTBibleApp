// La carte des modules — et, par leurs dépendances, l'architecture elle-même.
//
// ## Le sens des flèches
//
//     app  ──────────────────────────────┐  la racine de composition
//      │                                 │
//      ├──▶ ontfeatures ──▶ ontdesignsystem
//      │        │                        │
//      │        └────────┐               │
//      └──▶ ontdata ─────┼───────────────┴──▶ ontkit
//                        │                      ▲
//                        └──────────────────────┘
//
// `ontkit` ne dépend de rien. `ontdata` **implémente** ses ports, `ontfeatures`
// les **consomme** — et ne voit jamais `ontdata`. Seul `app` connaît les deux à
// la fois, parce qu'il est le seul endroit où l'on branche une implémentation
// sur un port.
//
// Ce n'est pas une invention : c'est exactement la découpe des paquets Swift,
// où `ONTFeatures` n'importe que `ONTKit` et `ONTDesignSystem`, et où seul
// `App` importe `ONTData`. La différence est qu'ici, Gradle le **tient** : un
// module n'a sur son chemin de classes que ce qu'on lui a donné. Là où Swift
// demandait qu'on n'écrive pas `import ONTData`, ici on ne le peut pas.

pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    // Aucun module ne déclare de dépôt : ils sont tous ici. Un module qui
    // ajouterait le sien pourrait tirer une version que personne d'autre ne
    // voit — le genre de divergence qu'on ne découvre qu'en production.
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "ONT"

// Le domaine. Module **JVM pur** : voir son build.gradle.kts.
include(":ontkit")

// Les adaptateurs — ce qui parle au monde extérieur.
include(":ontdata")

// La peau : couleurs, typographie, rendu des trois niveaux.
include(":ontdesignsystem")

// Les écrans.
include(":ontfeatures")

// La racine de composition, et elle seule.
include(":app")
