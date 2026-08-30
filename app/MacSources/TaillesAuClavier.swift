import SwiftUI

/// Les deux tailles que le Mac règle au clavier, et leurs bornes.
///
/// ## Pourquoi deux, et pas une
///
/// **⌘+ / ⌘− change l'interface** — les libellés, les listes, la barre
/// latérale. **⌘⌥+ / ⌘⌥− change le corps du texte**, et rien d'autre.
///
/// Les confondre serait un contresens pour cette app. Un lecteur atteint de
/// kératocône monte le corps du texte très haut pour lire, et n'a aucune
/// raison de faire enfler du même geste une barre latérale qui lui mangerait
/// la place où ce texte s'affiche. C'est d'ailleurs pourquoi le corps du texte
/// a déjà son propre curseur : le raccourci le double, il ne l'invente pas.
///
/// ## Pourquoi un type, pour deux additions
///
/// Parce que les bornes sont la seule chose qui puisse mentir en silence. Un
/// raccourci qui dépasse 28 ne casse rien de visible : il continue d'accepter
/// des appuis, la taille ne bouge plus, et l'on croit le raccourci mort. Le
/// serrage se teste ; le reste est de la plomberie SwiftUI.
enum TaillesAuClavier {
    /// Les bornes du corps du texte — **les mêmes que le curseur des réglages**,
    /// `Slider(in: 11...28, step: 1)`. Écrites une fois ici, employées par les
    /// deux, pour qu'un raccourci ne puisse pas atteindre une valeur que le
    /// curseur refuse.
    static let corps: ClosedRange<Double> = 11...28

    /// Le corps du texte, d'un cran vers le haut ou vers le bas.
    static func corpsDeplace(_ actuel: Double, de pas: Double) -> Double {
        min(max(actuel + pas, corps.lowerBound), corps.upperBound)
    }

    /// Les tailles d'interface offertes, de la plus petite à la plus grande.
    ///
    /// **Des facteurs, et non des `DynamicTypeSize`.** C'est le troisième
    /// dessin de ce réglage, et les deux premiers ne pouvaient pas marcher :
    /// `dynamicTypeSize` est inerte sur macOS — mesuré, `.body` rend 16 pt à
    /// `.xSmall` comme à `.xxxLarge`. Le raccourci changeait donc bien une
    /// valeur, et cette valeur ne commandait rien.
    ///
    /// Un facteur multiplie les fontes que l'app pose elle-même, via `ONTUI`.
    /// Il n'y a plus d'intermédiaire qui puisse ne pas répondre.
    ///
    /// Sept crans, de −15 % à +50 %. Pas au-delà : ce réglage est celui du
    /// confort, pas de l'accessibilité — un lecteur qui a besoin de bien plus
    /// grand monte le corps du texte, qui va jusqu'à 28 pt et ne fait pas
    /// enfler la barre latérale au passage.
    static let interface: [CGFloat] = [0.85, 0.9, 0.95, 1.0, 1.1, 1.25, 1.5]

    /// L'interface, d'un cran — rend l'indice serré dans les bornes.
    static func interfaceDeplacee(_ indice: Int, de pas: Int) -> Int {
        min(max(indice + pas, 0), interface.count - 1)
    }

    /// Le facteur d'un indice, quel que soit l'indice reçu.
    ///
    /// Serré ici plutôt que chez l'appelant : un réglage relu d'une session
    /// précédente peut désigner un cran qui n'existe plus, et le lire hors
    /// bornes ferait tomber l'app à l'ouverture — sur un fichier de préférences,
    /// c'est-à-dire sans qu'on puisse le reproduire.
    static func facteur(_ indice: Int) -> CGFloat {
        interface[min(max(indice, 0), interface.count - 1)]
    }

    /// L'indice de départ — le facteur 1, c'est-à-dire ce que le Mac dessine
    /// sans qu'on lui demande rien.
    static var interfaceParDefaut: Int {
        interface.firstIndex(of: 1.0) ?? 3
    }
}
