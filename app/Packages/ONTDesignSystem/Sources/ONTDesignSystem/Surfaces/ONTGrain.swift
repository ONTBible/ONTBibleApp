import ONTKit
import SwiftUI

#if canImport(UIKit)
import CoreImage
import os
import UIKit
#endif

/// Le grain de la nuit — `grain-page` du site.
///
/// ## Ce n'est pas un effet
///
/// La webapp le documente comme une **nécessité technique**, et le raisonnement
/// vaut ici : un dégradé sombre étalé sur une page se découpe en bandes, parce
/// qu'un écran n'a que 256 valeurs par canal et que l'écart entre deux nuances
/// de nuit est plus petit que ça. Le bruit casse les bandes.
///
/// La liseuse pose un aplat et non un dégradé, donc elle n'a pas ce défaut à
/// corriger. Ce qu'elle emprunte est le second effet, celui que le site
/// mentionne en passant : le grain donne **la matière d'un papier ancien**.
/// C'est ce qui distingue la nuit d'aubergine d'un simple fond sombre, et sans
/// lui « mystique » n'est qu'un thème sombre de plus.
///
/// ## Une seule image, fabriquée une fois
///
/// `feTurbulence` n'existe pas ici. On tire un bruit monochrome par CoreImage,
/// **une fois pour la vie du processus**, dans une tuile de 128 points qu'on
/// répète. Le refaire à chaque affichage coûterait un rendu CoreImage par
/// image de défilement, pour un résultat que l'œil ne distingue pas.
///
/// La tuile est tirée à l'échelle de l'écran : à 1×, sur une dalle 3×, le grain
/// devient un damier visible au lieu d'un bruit.
public struct ONTGrain: View {
    /// 3,5 %, la valeur du site. Au-delà, on voit le bruit ; en deçà, on ne
    /// voit plus la matière.
    public static let opacity: Double = 0.035

    /// L'échelle de la dalle, prise dans l'environnement.
    ///
    /// Et non `UIScreen.main.scale`, qui est déprécié depuis iOS 16 et surtout
    /// **faux** : il rend l'écran principal, pas celui qui affiche cette vue —
    /// donc l'échelle de l'iPad quand l'app tourne sur un écran externe, ou
    /// celle d'une fenêtre qui n'est pas la nôtre.
    @Environment(\.displayScale) private var echelle

    private let theme: ReadingTheme

    public init(theme: ReadingTheme) {
        self.theme = theme
    }

    public var body: some View {
        #if canImport(UIKit)
        // Seulement sur la nuit. Sur un parchemin, le grain se verrait comme
        // une salissure — le papier est déjà dans la couleur du fond.
        if theme == .mystique, let tuile = Self.tuile(echelle) {
            Image(uiImage: tuile)
                .resizable(resizingMode: .tile)
                .opacity(Self.opacity)
                // Le grain est une matière, pas une cible : il ne doit voler
                // ni un appui sur un verset, ni le curseur de VoiceOver.
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .ignoresSafeArea()
        }
        #endif
    }

    #if canImport(UIKit)
    /// Les tuiles déjà fabriquées, une par échelle rencontrée.
    ///
    /// Un cache et non une constante : l'échelle n'est connue qu'à
    /// l'affichage. Il y en a une ou deux pour la vie du processus — 2× et 3× —
    /// et une tuile de 128 points pèse quelques centaines de kilooctets.
    ///
    /// Sous verrou parce qu'une vue SwiftUI n'est pas garantie de se composer
    /// sur le fil principal, et que deux fabrications simultanées corrompraient
    /// le dictionnaire.
    private static let cache = OSAllocatedUnfairLock(initialState: [CGFloat: UIImage]())

    private static func tuile(_ echelle: CGFloat) -> UIImage? {
        cache.withLock { memo in
            if let deja = memo[echelle] { return deja }
            guard let neuve = fabrique(echelle) else { return nil }
            memo[echelle] = neuve
            return neuve
        }
    }

    private static func fabrique(_ echelle: CGFloat) -> UIImage? {
        let cote: CGFloat = 128
        let pixels = CGRect(x: 0, y: 0, width: cote * echelle, height: cote * echelle)

        guard let bruit = CIFilter(name: "CIRandomGenerator")?.outputImage else { return nil }
        // Désaturé : un bruit coloré poserait des points verts et rouges sur
        // une nuit bordeaux, et se lirait comme un défaut de dalle.
        guard let gris = CIFilter(
            name: "CIColorControls",
            parameters: [kCIInputImageKey: bruit, kCIInputSaturationKey: 0]
        )?.outputImage else { return nil }

        let contexte = CIContext(options: nil)
        guard let cg = contexte.createCGImage(gris, from: pixels) else { return nil }
        return UIImage(cgImage: cg, scale: echelle, orientation: .up)
    }
    #endif
}
