import SwiftUI

#if canImport(UIKit)
import UIKit

/// La feuille de partage du système, pour ce que `ShareLink` ne sait pas faire.
///
/// `ShareLink` exige de connaître son contenu au moment où la vue se construit.
/// Une image de 1080 × 1080 rendue à chaque évaluation du corps — donc à chaque
/// verset touché — serait du gaspillage pur. Ici on rend à l'appui, une fois,
/// puis on présente.
public struct ONTActivityView: UIViewControllerRepresentable {
    private let items: [Any]

    public init(items: [Any]) {
        self.items = items
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    public func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Ce qu'on partage, rendu identifiable pour `sheet(item:)`.
public struct ONTShareItem: Identifiable {
    public let id = UUID()
    public let items: [Any]

    public init(_ items: [Any]) {
        self.items = items
    }
}
#endif
