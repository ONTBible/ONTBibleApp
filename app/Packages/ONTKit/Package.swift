// swift-tools-version: 6.0
import PackageDescription

// ONTKit — le domaine.
//
// Zéro dépendance, pas même SwiftUI : ce module sait ce qu'est un verset, un
// intraduisible, un surlignage, mais rien du disque, du réseau ni de l'écran.
// C'est ce qui rend ses tests instantanés et indépendants du simulateur —
// même principe que le domaine du backend Rust.
let package = Package(
    name: "ONTKit",
    platforms: [.iOS("26.0"), .macOS("14.0")],
    products: [.library(name: "ONTKit", targets: ["ONTKit"])],
    targets: [
        .target(name: "ONTKit"),
        .testTarget(name: "ONTKitTests", dependencies: ["ONTKit"]),
    ]
)
