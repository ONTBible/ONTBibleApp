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
}
