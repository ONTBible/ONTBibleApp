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
    platforms: [.iOS("26.0")],  // iOS seulement : les vues emploient UIKit
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
