import SwiftUI

/// L'échelle d'espacement.
///
/// Des `@ScaledMetric` relatifs à `.body`, donc **ils grandissent avec Dynamic
/// Type** — le réglage système de taille de police. Pour une liseuse, et pour
/// un lectorat qui n'a pas vingt ans, une grille en points fixes est un défaut
/// d'accessibilité, pas un détail de style.
///
/// N'employer ces jetons que là où on aurait écrit un nombre au jugé. Pour le
/// reste, `.padding()` sans argument : SwiftUI tient déjà compte de la classe
/// de taille et du conteneur.
public struct ONTSpacing: DynamicProperty {
    /// 4 pt — l'écart le plus serré : icône et libellé, intérieur d'une pastille.
    @ScaledMetric(relativeTo: .body) public var xs: CGFloat = 4
    /// 8 pt — un groupe lié : un titre au-dessus de son sous-titre.
    @ScaledMetric(relativeTo: .body) public var s: CGFloat = 8
    /// 12 pt — marges d'une ligne, intérieur d'une carte.
    @ScaledMetric(relativeTo: .body) public var m: CGFloat = 12
    /// 16 pt — la marge par défaut d'une vue.
    @ScaledMetric(relativeTo: .body) public var l: CGFloat = 16
    /// 22 pt — les marges latérales d'une page de lecture.
    @ScaledMetric(relativeTo: .body) public var page: CGFloat = 22
    /// 24 pt — séparation entre sections.
    @ScaledMetric(relativeTo: .body) public var xl: CGFloat = 24
    /// 32 pt — respiration en tête d'écran.
    @ScaledMetric(relativeTo: .body) public var xxl: CGFloat = 32

    public init() {}
}

/// Une taille en points, mise à l'échelle du curseur système.
///
/// `ONTSpacing` couvre les écarts, dont les valeurs sont peu nombreuses et se
/// nomment. Restait ce que l'on ne peut pas mettre en jetons : le corps d'un
/// `.system(size:)`, le côté d'un symbole SF, le minimum d'une case de grille —
/// des nombres dictés par un dessin précis, différents à chaque endroit.
///
/// Écrits en dur, ils ne bougent pas d'un pouce quand le lecteur monte
/// « Taille du texte » dans les réglages. C'est le piège de SwiftUI :
/// `Font.custom(_:size:)` suit ce curseur d'office, `.system(size:)` **non**.
/// Une vue qui mélange les deux voit sa hiérarchie se défaire dès que le
/// curseur bouge — le texte grandit, les étiquettes et les icônes restent.
///
/// ```swift
/// private var echelle = ONTScaled()
/// ...
/// Image(systemName: "xmark")
///     .font(.system(size: echelle(12), weight: .bold))
///     .frame(width: echelle(28), height: echelle(28))
/// ```
///
/// Le corps **et** le cadre qui le contient, toujours ensemble : un symbole
/// qui grandit dans une pastille figée en déborde.
public struct ONTScaled: DynamicProperty {
    @ScaledMetric(relativeTo: .body) private var facteur: CGFloat = 1

    public init() {}

    public func callAsFunction(_ points: CGFloat) -> CGFloat { points * facteur }
}

/// Les rayons de courbure.
public enum ONTRadius {
    /// Pastilles et étiquettes.
    public static let pill: CGFloat = 999
    /// Surlignage d'un verset — juste assez pour adoucir l'angle.
    public static let highlight: CGFloat = 6
    /// Blocs secondaires.
    public static let block: CGFloat = 18
    /// Cartes de premier plan.
    public static let card: CGFloat = 22
}

/// La largeur de lecture.
public enum ONTLayout {
    /// Au-delà, une ligne devient trop longue pour que l'œil retrouve le
    /// début de la suivante. Vaut surtout sur iPad.
    public static let readingWidth: CGFloat = 700

    /// La largeur d'une **page** — listes, cartes, réglages.
    ///
    /// Plus large que la mesure du texte suivi, et c'est délibéré : une liste
    /// ne se lit pas comme une phrase. L'œil n'y court pas d'un bout à l'autre,
    /// il saute d'un intitulé à sa valeur. La serrer à la mesure de la prose la
    /// tassait sans rien gagner en lisibilité.
    public static let pageWidth: CGFloat = 850

    /// La largeur d'une carte — celle qu'elle a sur iPhone.
    ///
    /// Un iPhone de 402 points moins ses deux marges de vingt : la carte du
    /// verset y fait 363 × 232, soit un rapport de 1,56. Étalée sur la colonne
    /// de l'iPad, elle passait à 803 × 235 — un rapport de 3,4, une bande. Le
    /// verset n'y tenait plus que sur deux lignes qui traversaient l'écran.
    ///
    /// La carte garde donc sa mesure d'un appareil à l'autre. C'est aussi ce
    /// qui la maintient jumelle de la pastille du widget, qui ne s'étire pas
    /// non plus.
    public static let cardWidth: CGFloat = 362
}
