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
    /// **Les cinq tailles ordinaires seulement.** `DynamicTypeSize` en compte
    /// cinq de plus, dites d'accessibilité, qui recomposent les vues en
    /// colonnes et rendent une barre latérale inutilisable. Le lecteur qui en a
    /// besoin les obtient du système, pour toutes ses apps ; ce raccourci-ci
    /// règle le confort, pas l'accessibilité.
    static let interface: [DynamicTypeSize] = [
        .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
    ]

    /// L'interface, d'un cran — rend l'indice serré dans les bornes.
    static func interfaceDeplacee(_ indice: Int, de pas: Int) -> Int {
        min(max(indice + pas, 0), interface.count - 1)
    }

    /// L'indice de départ : `.large`, la taille par défaut du système.
    static var interfaceParDefaut: Int {
        interface.firstIndex(of: .large) ?? 3
    }
}
