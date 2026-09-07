#if canImport(UIKit)
    import SwiftUI
    import UIKit

    /// L'image du système, sous un nom qui ne le nomme pas.
    ///
    /// `UIImage` et `NSImage` portent la même chose et ne s'appellent pas
    /// pareil. Sans cet alias, chaque signature qui rend une image demande son
    /// `#if` — et le code qui *compose* l'image, identique partout, se
    /// retrouve coupé en deux pour une différence de nom.
    ///
    /// Le `#if` reste, mais il est **ici seul**, et il porte sur ce qu'il doit
    /// porter : un nom de type, pas une logique.
    public typealias ONTImage = UIImage
#else
    import AppKit
    import SwiftUI

    /// Voir la variante UIKit.
    public typealias ONTImage = NSImage
#endif

// MARK: - Réduire une image sous une borne d'octets

/// Ce que le portrait d'un lecteur doit subir avant de partir au serveur.
///
/// La logique est la même partout — descendre la qualité JPEG par paliers, et
/// si l'image résiste, la redimensionner vraiment — mais ni le codage ni le
/// dessin hors écran ne portent le même nom d'une plateforme à l'autre.
///
/// Elle vit ici plutôt que dans l'écran de profil, où elle était : un écran ne
/// doit pas savoir qu'un JPEG se compresse par essais successifs.
extension ONTImage {
    /// Rend l'image en JPEG sous `borne` octets, ou `nil` si c'est impossible.
    public func ontSousLaBorne(_ borne: Int) -> Data? {
        for qualite in stride(from: 0.85, through: 0.35, by: -0.1) {
            guard let donnees = ontJPEG(qualite: qualite) else { continue }
            if donnees.count <= borne { return donnees }
        }
        // Une image qui résiste à 0,35 est pathologique — un bruit de fond
        // photographique, que le JPEG ne sait pas compresser. On la réduit
        // alors vraiment, plutôt que de la refuser.
        return ontReduite(a: 256)?.ontJPEG(qualite: 0.6)
    }

    /// L'image ramenée à `cote` sur son plus grand côté, proportions gardées.
    public func ontReduite(a cote: CGFloat) -> ONTImage? {
        let plusGrand = max(size.width, size.height)
        guard plusGrand > cote else { return self }
        let facteur = cote / plusGrand
        let cible = CGSize(width: size.width * facteur, height: size.height * facteur)

        #if canImport(UIKit)
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            return UIGraphicsImageRenderer(size: cible, format: format).image { _ in
                draw(in: CGRect(origin: .zero, size: cible))
            }
        #else
            let vignette = NSImage(size: cible)
            vignette.lockFocus()
            draw(in: CGRect(origin: .zero, size: cible))
            vignette.unlockFocus()
            return vignette
        #endif
    }

    /// L'image codée en JPEG.
    func ontJPEG(qualite: Double) -> Data? {
        #if canImport(UIKit)
            return jpegData(compressionQuality: qualite)
        #else
            // **`NSImage` ne sait pas se coder seule** : il faut passer par sa
            // représentation bitmap, et une `NSImage` peut n'en avoir aucune —
            // un PDF, un vecteur. On en fabrique donc une à partir de son
            // `CGImage`, qui existe toujours pour ce qu'on reçoit ici.
            guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return nil
            }
            let rep = NSBitmapImageRep(cgImage: cg)
            return rep.representation(
                using: .jpeg, properties: [.compressionFactor: qualite])
        #endif
    }
}

extension Image {
    /// Une `Image` SwiftUI à partir de l'image du système.
    ///
    /// `Image(uiImage:)` et `Image(nsImage:)` font la même chose sous deux
    /// noms. Chaque vue qui affiche un portrait devait donc porter son `#if` —
    /// pour une **étiquette d'argument**.
    public init(ontImage: ONTImage) {
        #if canImport(UIKit)
            self.init(uiImage: ontImage)
        #else
            self.init(nsImage: ontImage)
        #endif
    }
}
