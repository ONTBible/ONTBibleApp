// swift-tools-version: 6.0
import PackageDescription

// ONTDesignSystem — jetons, thème, composants, et le rendu du texte ONT.
//
// Dépend d'ONTKit parce que le renderer compose des `Inline` : traduire les
// trois niveaux du texte en typographie est une décision de présentation, pas
// de domaine.
let package = Package(
    name: "ONTDesignSystem",
    platforms: [.iOS("18.0"), .macOS("14.0")],
    products: [.library(name: "ONTDesignSystem", targets: ["ONTDesignSystem"])],
    dependencies: [.package(path: "../ONTKit")],
    targets: [
        .target(
            name: "ONTDesignSystem",
            dependencies: [.product(name: "ONTKit", package: "ONTKit")],
            // La montagne du logo. Ressource du **paquet** et non de l'app :
            // l'app et le widget la veulent tous les deux, et une extension ne
            // lit pas le bundle de l'app qui la contient. Ici, `Bundle.module`
            // la sert aux deux sans duplication à maintenir.
            resources: [.process("Resources")]
        )
    ]
)
