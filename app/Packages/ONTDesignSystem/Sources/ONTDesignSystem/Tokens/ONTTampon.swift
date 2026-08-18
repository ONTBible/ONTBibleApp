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
/// ## Pourquoi ce n'est pas mesuré
///
/// On a essayé de le demander au pilote : allouer une texture d'un pixel de
/// large et de la hauteur voulue, et lire la réponse. Metal n'en donne pas.
/// `newTextureWithDescriptor:` ne rend pas `nil` sur une dimension hors
/// limites — il **avorte le processus** :
///
///     -[MTLTextureDescriptorInternal validateWithDevice:]
///     __assert_rtn → abort
///
/// La sonde a donc tué l'app à la première section de prose sur simulateur,
/// où le plafond est 8192, sans rien montrer sur l'appareil, où 16 384 passe.
/// Une question qu'on ne peut poser qu'en connaissant déjà la réponse n'est pas
/// une mesure.
///
/// ## Ce qu'on retient à la place
///
/// Deux valeurs, et la frontière est le simulateur, pas la génération de
/// matériel : l'app demande iOS 18, donc au moins un A12, et tous les Apple GPU
/// depuis l'A9 acceptent 16 384. Seul le pilote du simulateur s'arrête à 8192 —
/// c'est lui, et lui seul, que ce `#if` distingue.
public enum ONTTampon {
    /// La plus grande hauteur de texture, en pixels.
    public static let plafondEnPixels: Int = {
        #if targetEnvironment(simulator)
        8_192
        #else
        16_384
        #endif
    }()

    /// Le même plafond, en points, avec une marge.
    ///
    /// Les cinq pour cent couvrent l'écart entre la hauteur de la vue et celle
    /// du tampon qu'elle demande — SwiftUI y ajoute de quoi loger les
    /// débordements de glyphes.
    public static func plafondEnPoints(echelle: CGFloat) -> CGFloat {
        CGFloat(plafondEnPixels) / max(echelle, 1) * 0.95
    }
}
