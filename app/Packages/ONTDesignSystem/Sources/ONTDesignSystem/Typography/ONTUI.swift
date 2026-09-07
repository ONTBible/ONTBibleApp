import Observation
import SwiftUI

/// L'échelle de l'interface — ce que `dynamicTypeSize` ne fait pas sur le Mac.
///
/// ## Ce qui a été mesuré
///
/// L'auteur a signalé trois fois que ⌘= ne changeait rien. J'ai cherché deux
/// fois au mauvais endroit : d'abord un défaut de câblage du menu, puis la
/// barre latérale d'AppKit. Les deux étaient de vrais défauts, aucun n'était
/// *le* défaut.
///
/// Le troisième relevé est sans appel — même texte, deux tailles de type
/// dynamique, rendu par `ImageRenderer` :
///
///     .body   à .xSmall → 16,0 pt     à .xxxLarge → 16,0 pt
///     Jost 14 à .xSmall → 14,0 pt     à .xxxLarge → 14,0 pt
///
/// **`dynamicTypeSize` est inerte sur macOS.** Ce n'est pas un oubli d'Apple :
/// Dynamic Type est un réglage d'iOS, le Mac n'en a pas d'équivalent système, et
/// une app qui veut régler la taille de son interface doit la régler elle-même.
///
/// L'épreuve qui l'a établi vit dans `MacTests/EchelleDeLInterfaceTests` et
/// reste en place : le jour où macOS l'honorerait, elle nous le dirait.
///
/// ## Pourquoi une référence observable et non un `@Environment`
///
/// Une valeur d'environnement obligerait chaque vue à la déclarer pour s'en
/// servir, et une fonte se compose en chaîne — `.font(ONTUI.caption.monospacedDigit())`.
/// Un objet observé lu depuis un `static` se glisse dans la chaîne sans rien
/// changer à l'appel, et `Observation` enregistre quand même la dépendance :
/// la lecture a lieu pendant l'évaluation du `body`, ce qui suffit.
@Observable
@MainActor
public final class ONTEchelleUI {
    /// L'exemplaire que toute l'app lit.
    public static let partage = ONTEchelleUI()

    /// Le facteur appliqué aux fontes d'interface. 1 est la taille du système.
    ///
    /// Il reste à 1 sur iOS et Android : là, c'est le réglage du système qui
    /// commande, et le doubler serait le contredire.
    public var facteur: CGFloat = 1

    private init() {}
}

/// Les fontes de l'interface — ce qui n'est pas le texte biblique.
///
/// Le corps de la traduction a sa propre échelle, réglée au curseur et par
/// ⌘⇧= : ce sont deux choses distinctes, et les confondre serait un contresens.
/// On monte le corps très haut pour lire, sans vouloir qu'une barre latérale
/// enfle et mange la place de ce texte.
///
/// Sur iOS, ces membres rendent la fonte **sémantique** telle quelle, pour que
/// Dynamic Type continue de commander — c'est la seule chose qui compte pour un
/// lecteur qui monte le curseur système afin de voir. Sur macOS, où ce curseur
/// n'existe pas, ils rendent une taille en points multipliée par le facteur.
///
/// Le `#if` porte donc sur ce qui touche au **système** — l'existence de
/// Dynamic Type —, jamais sur ce qui touche au sens.
@MainActor
public enum ONTUI {
    private static var f: CGFloat { ONTEchelleUI.partage.facteur }

    public static var largeTitle: Font { police(.largeTitle, 26) }
    public static var title: Font { police(.title, 22) }
    public static var title2: Font { police(.title2, 17) }
    public static var title3: Font { police(.title3, 15) }
    public static var headline: Font { police(.headline, 13, .semibold) }
    public static var subheadline: Font { police(.subheadline, 11) }
    public static var body: Font { police(.body, 13) }
    public static var callout: Font { police(.callout, 12) }
    public static var footnote: Font { police(.footnote, 10) }
    public static var caption: Font { police(.caption, 10) }
    public static var caption2: Font { police(.caption2, 10) }

    /// Une taille en points, mise à l'échelle de l'interface.
    ///
    /// Pour les nombres qu'aucun rôle ne nomme — le côté d'un symbole SF, le
    /// minimum d'une case de grille. Sur iOS, `ONTScaled` fait déjà ce travail
    /// avec le curseur du système ; ici on ne fait que suivre le facteur.
    // MARK: - Ce qu'une ligne de liste doit déclarer sur le Mac

    /// **Pourquoi ces trois-là rendent `nil` sur iOS.**
    ///
    /// Une `List` de macOS reprend la fonte du système à ses lignes : mesuré au
    /// pixel, aucun style n'y échappe — `sidebar`, `plain`, `inset`, `bordered`
    /// —, et rien posé au-dessus ne franchit la barrière, ni sur la `List` ni
    /// sur une `Section`. Un texte de ligne qui ne déclare pas sa fonte ne
    /// suivra donc jamais ⌘=.
    ///
    /// Sur iOS le problème n'existe pas : le style de liste donne déjà la bonne
    /// fonte, et Dynamic Type la fait suivre. **Y imposer la nôtre changerait
    /// l'apparence pour rien** — un en-tête n'y vaut pas `.body`, et on
    /// écraserait ce que la plateforme a choisi.
    ///
    /// D'où `Font?` et non `Font` : `.font(nil)` veut dire « hérite », donc
    /// exactement ce qui se passe aujourd'hui. Le remède n'a de contenu que là
    /// où le mal existe, et ça se lit dans le type.
    ///
    /// Les trois rôles ne prennent pas la même fonte, et c'est le point : un
    /// en-tête, un pied et un contenu de ligne n'ont pas la même voix.
    public static var ligneDeListe: Font? {
        #if os(macOS)
            return body
        #else
            return nil
        #endif
    }

    /// L'intitulé d'une `Section`.
    public static var enteteDeListe: Font? {
        #if os(macOS)
            return footnote
        #else
            return nil
        #endif
    }

    /// Le paragraphe explicatif sous une `Section`.
    public static var piedDeListe: Font? {
        #if os(macOS)
            return footnote
        #else
            return nil
        #endif
    }

    public static func points(_ valeur: CGFloat) -> CGFloat {
        #if os(macOS)
            return valeur * f
        #else
            return valeur
        #endif
    }

    private static func police(
        _ semantique: Font, _ points: CGFloat, _ graisse: Font.Weight? = nil
    ) -> Font {
        #if os(macOS)
            let base = Font.system(size: points * f)
            return graisse.map { base.weight($0) } ?? base
        #else
            return semantique
        #endif
    }
}
