import SwiftUI

#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif

/// Le presse-papier du système.
///
/// ## Pourquoi un nom à nous pour une chose aussi simple
///
/// `UIPasteboard.general.string = …` d'un côté, et de l'autre un
/// `NSPasteboard` qu'il faut **vider avant d'écrire**, sans quoi l'ancien
/// contenu survit à côté du neuf et le collage rend l'un ou l'autre selon
/// l'application qui reçoit.
///
/// Cette asymétrie est exactement le genre de chose qu'une vue ne doit pas
/// avoir à savoir. Elle veut poser un texte à copier ; qu'il faille d'abord
/// déclarer un type sur le Mac et pas sur le téléphone ne la regarde pas.
public enum ONTPressePapier {
    /// Y pose un texte, en remplaçant ce qui s'y trouvait.
    public static func poser(_ texte: String) {
        #if canImport(UIKit)
            UIPasteboard.general.string = texte
        #else
            let p = NSPasteboard.general
            // **`clearContents` d'abord**, et ce n'est pas de la prudence : le
            // presse-papier du Mac garde plusieurs représentations d'un même
            // contenu. Écrire sans vider laisse l'ancienne à côté de la neuve,
            // et chaque application colle celle qu'elle préfère — donc parfois
            // le verset d'avant.
            p.clearContents()
            p.setString(texte, forType: .string)
        #endif
    }
}
