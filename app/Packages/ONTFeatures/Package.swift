// swift-tools-version: 6.0
import PackageDescription

// ONTFeatures — une bibliothèque par feature.
//
// Chacune porte son `Application/` (le modèle observable qui orchestre les
// dépôts) et sa `Presentation/` (les vues). Le domaine et les données restent
// partagés : Bible, Lexique et Recherche lisent le même corpus, et le
// dupliquer créerait trois vérités.
let package = Package(
    name: "ONTFeatures",
    // Les deux plateformes. Ce qu'elles ne nomment pas pareil est traduit une
    // fois pour toutes dans `ONTPlateformes`, côté design system — les vues
    // déclarent une intention, jamais un système.
    // macOS **15** et non 14 : les vues emploient `textRenderer`,
    // `onScrollPhaseChange` et `onScrollVisibilityChange`, tous trois nés
    // avec macOS 15. Les rétroporter reviendrait à écrire une seconde liseuse.
    //
    // Les paquets du dessous restent à 14 — ils n'en ont pas besoin, et un
    // plancher qu'on monte sans raison exclut des machines pour rien.
    platforms: [.iOS("18.0"), .macOS("15.0")],
    products: [
        .library(name: "ReadingFeature", targets: ["ReadingFeature"]),
        .library(name: "LexiconFeature", targets: ["LexiconFeature"]),
        .library(name: "SearchFeature", targets: ["SearchFeature"]),
        .library(name: "QahalFeature", targets: ["QahalFeature"]),
        .library(name: "YouFeature", targets: ["YouFeature"]),
    ],
    dependencies: [
        .package(path: "../ONTKit"),
        .package(path: "../ONTDesignSystem"),
    ],
    targets: [
        .target(name: "ReadingFeature", dependencies: [
            .product(name: "ONTKit", package: "ONTKit"),
            .product(name: "ONTDesignSystem", package: "ONTDesignSystem"),
        ]),
        .target(name: "LexiconFeature", dependencies: [
            .product(name: "ONTKit", package: "ONTKit"),
            .product(name: "ONTDesignSystem", package: "ONTDesignSystem"),
        ]),
        .target(name: "SearchFeature", dependencies: [
            .product(name: "ONTKit", package: "ONTKit"),
            .product(name: "ONTDesignSystem", package: "ONTDesignSystem"),
        ]),
        .target(name: "QahalFeature", dependencies: [
            .product(name: "ONTKit", package: "ONTKit"),
            .product(name: "ONTDesignSystem", package: "ONTDesignSystem"),
            "ReadingFeature",
        ]),
        .target(name: "YouFeature", dependencies: [
            .product(name: "ONTKit", package: "ONTKit"),
            .product(name: "ONTDesignSystem", package: "ONTDesignSystem"),
            "ReadingFeature",
        ]),
    ]
)
