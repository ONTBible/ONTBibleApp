#if canImport(UIKit)
    import ONTKit
    import SwiftUI
    import UIKit

    /// Le portrait du lecteur, taillé en rond pour une barre d'onglets.
    ///
    /// ## Pourquoi il faut fabriquer une image, et pas composer une vue
    ///
    /// La première tentative posait la vue `Portrait` dans le `icon:` d'un
    /// `Label` de `Tab`. Résultat mesuré à l'écran : **l'onglet perdait son
    /// icône** — un libellé « Vous » tout seul, sans rien au-dessus.
    ///
    /// Une barre d'onglets d'iOS ne compose pas une vue quelconque : elle veut
    /// une `Image`, qu'elle mesure et détoure elle-même. Lui en donner une
    /// autre ne produit pas une erreur, ça produit **du vide** — et un vide
    /// ressemble à un oubli, pas à un refus.
    ///
    /// ## `.renderingMode(.original)` n'est pas une option
    ///
    /// Sans lui, la barre d'onglets peint l'image en aplat de la teinte
    /// courante : le visage sortirait en silhouette monochrome, ce qui est
    /// exactement ce qu'on essayait d'éviter.
    enum PortraitDOnglet {
        /// Le côté du rond, en points. La taille d'icône d'une barre d'onglets.
        private static let cote: CGFloat = 26

        /// Rend le portrait en rond, ou `nil` quand il n'y en a pas.
        ///
        /// `nil` plutôt qu'une image de repli : c'est à l'appelant de choisir le
        /// symbole du système, qui reste la bonne icône pour un lecteur qui n'a
        /// pas de compte. Fabriquer ici un rond gris reviendrait à décider à sa
        /// place, et à priver l'onglet du symbole que le système sait animer.
        @MainActor
        static func rond(_ octets: Data?) -> Image? {
            guard let octets, let source = UIImage(data: octets) else { return nil }

            let taille = CGSize(width: cote, height: cote)
            let format = UIGraphicsImageRendererFormat.preferred()
            format.opaque = false
            let rendu = UIGraphicsImageRenderer(size: taille, format: format).image { _ in
                UIBezierPath(ovalIn: CGRect(origin: .zero, size: taille)).addClip()
                // `scaleAspectFill` à la main : un portrait n'est pas carré, et
                // le déformer pour qu'il tienne vaut moins que le recadrer.
                let echelle = max(taille.width / source.size.width,
                                  taille.height / source.size.height)
                let cadre = CGSize(
                    width: source.size.width * echelle,
                    height: source.size.height * echelle)
                source.draw(
                    in: CGRect(
                        x: (taille.width - cadre.width) / 2,
                        y: (taille.height - cadre.height) / 2,
                        width: cadre.width, height: cadre.height))
            }
            return Image(uiImage: rendu).renderingMode(.original)
        }
    }
#endif
