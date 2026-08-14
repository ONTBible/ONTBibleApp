// swift-tools-version: 6.0
import PackageDescription

// ONTData — les implémentations des ports d'ONTKit.
//
// Toute la connaissance du format JSON produit par le pipeline, des chemins
// de fichiers et du schéma de stockage vit ici, et nulle part ailleurs.
let package = Package(
    name: "ONTData",
    platforms: [.iOS("26.0"), .macOS("14.0")],
    products: [.library(name: "ONTData", targets: ["ONTData"])],
    dependencies: [.package(path: "../ONTKit")],
    targets: [
        .target(name: "ONTData", dependencies: [.product(name: "ONTKit", package: "ONTKit")]),
        // Le décodage se prouve ici, parce qu'il se fait ici. Ces tests
        // vivaient dans ONTKitTests, du temps où le domaine décodait
        // lui-même — ils y éprouvaient un contrat qui n'était pas le sien.
        .testTarget(name: "ONTDataTests", dependencies: ["ONTData"]),
    ]
)
