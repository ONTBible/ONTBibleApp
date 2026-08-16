import Metal
import SwiftUI

/// Jusqu'où un `Text` peut monter avant que son dessin se perde.
///
/// ## Le défaut que ça répare
///
/// Poser un `TextRenderer` oblige SwiftUI à rasteriser le `Text` hors écran
/// pour le confier au moteur. Au-delà de la plus grande texture que la machine
/// sait allouer, le tampon n'existe pas — et le dessin disparaît sans erreur,
/// sans trace, sans rien. Dix chapitres de Bereshit sur dix-neuf étaient muets
/// pour cette seule raison.
///
/// ## Pourquoi on le demande au lieu de l'écrire
///
/// La première parade inscrivait 8192 px en dur, relevé sur le simulateur.
/// C'était vrai là, et faux ailleurs : les appareils depuis l'A11 en acceptent
/// le double. Le plafond prudent coûtait alors l'estompage sur presque toutes
/// les sections d'un vrai téléphone — une section de Bereshit 19 fait 13 695 px,
/// bien au-dessous de ce que la machine sait faire, et bien au-dessus de ce
/// qu'on lui accordait.
///
/// On le **probe** donc : allouer une texture d'un pixel de large et de la
/// hauteur voulue ne coûte presque rien, et la réponse du pilote est la seule
/// qui ne se démente pas d'un modèle à l'autre.
public enum ONTTampon {
    /// Les hauteurs qu'on tente, de la plus généreuse à la plus prudente.
    private static let candidats = [16_384, 8_192, 4_096]

    /// La plus grande hauteur de texture que cette machine accepte, en pixels.
    ///
    /// Calculé une fois. Sans Metal — ce qui n'arrive pas sur un appareil réel
    /// mais peut arriver sous un outil — on retient le plus prudent.
    public static let plafondEnPixels: Int = {
        guard let gpu = MTLCreateSystemDefaultDevice() else { return candidats.last! }
        for hauteur in candidats where accepte(hauteur, gpu) { return hauteur }
        return candidats.last!
    }()

    private static func accepte(_ hauteur: Int, _ gpu: MTLDevice) -> Bool {
        let plan = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: 1, height: hauteur, mipmapped: false)
        // `.memoryless` : on ne veut pas la mémoire, seulement savoir si le
        // pilote consent à la forme.
        plan.storageMode = .private
        return gpu.makeTexture(descriptor: plan) != nil
    }

    /// Le même plafond, en points, avec une marge.
    ///
    /// Les cinq pour cent couvrent l'écart entre la hauteur de la vue et celle
    /// du tampon qu'elle demande — SwiftUI y ajoute de quoi loger les
    /// débordements de glyphes.
    public static func plafondEnPoints(echelle: CGFloat) -> CGFloat {
        CGFloat(plafondEnPixels) / max(echelle, 1) * 0.95
    }
}
