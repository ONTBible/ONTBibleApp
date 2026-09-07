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

#endif

/// Ce qu'on partage, rendu identifiable pour `sheet(item:)`.
///
/// **Hors du `#if`, et c'est le point.** Il ne contient rien d'UIKit — un
/// identifiant et des valeurs. Enfermé avec la feuille qui le présente, il
/// emportait avec lui tout le code qui *décide* quoi partager, alors que ce
/// code est le même partout : composer un texte, y joindre un lien, rendre une
/// image. Seule la **présentation** diffère d'une plateforme à l'autre.
///
/// C'est la limite qu'un `#if` doit suivre : ce qui touche au système, jamais
/// ce qui touche au sens.
public struct ONTShareItem: Identifiable {
    public let id = UUID()
    public let items: [Any]

    public init(_ items: [Any]) {
        self.items = items
    }
}

#if canImport(AppKit) && !canImport(UIKit)
    import AppKit

    /// La feuille de partage du Mac.
    ///
    /// `NSSharingServicePicker` s'ancre sur une vue et non sur une
    /// présentation : on le pose donc dans une vue de service, invisible, dont
    /// le seul rôle est de lui donner un point d'accroche.
    public struct ONTActivityView: NSViewRepresentable {
        private let items: [Any]

        public init(items: [Any]) {
            self.items = items
        }

        public func makeNSView(context: Context) -> NSView {
            let ancre = NSView(frame: .init(x: 0, y: 0, width: 1, height: 1))
            DispatchQueue.main.async {
                guard ancre.window != nil else { return }
                NSSharingServicePicker(items: items)
                    .show(relativeTo: .zero, of: ancre, preferredEdge: .minY)
            }
            return ancre
        }

        public func updateNSView(_ vue: NSView, context: Context) {}
    }
#endif
