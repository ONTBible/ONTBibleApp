import ONTKit
import SwiftUI

/// Les fontes.
public enum ONTFonts {
    /// La fonte de l'hébreu biblique.
    ///
    /// Ezra SIL porte le niqqud (voyelles) et les te'amim (cantillation), et
    /// surtout les **positionne** correctement. Une fonte système ne le fait
    /// pas : les points se décrochent des consonnes, et un texte biblique
    /// devient illisible pour qui sait le lire.
    ///
    /// Sous licence OFL, donc redistribuable — contrairement à SBL Hebrew
    /// (EULA propriétaire) et à Taamey Frank CLM (GPL dont l'exception ne
    /// couvre que les documents), qui restent réservées à la composition
    /// Affinity.
    public static let hebrew = "EzraSIL"

    /// Les titres — Frank Ruhl Libre, OFL.
    public static let display = "FrankRuhlLibre-Medium"

    /// Le nom de famille d'une fonte de corps.
    ///
    /// Le nom de **famille**, pas de coupe : c'est lui qui permet à `.italic()`
    /// et au semi-gras de trouver la bonne fonte au lieu d'une pente simulée
    /// ou d'un gras épaissi à la main.
    ///
    /// Six familles sont embarquées, chacune en trois coupes figées sur l'axe
    /// de taille optique à 14 pt — la taille de lecture visée, car une fonte à
    /// `opsz` ne dessine pas pareil à 8 et à 60. Georgia n'est pas embarquée :
    /// Apple la livre.
    public static func family(_ font: ReadingFont) -> String {
        switch font {
        case .literata: "Literata"
        case .ebGaramond: "EB Garamond"
        case .spectral: "Spectral"
        case .sourceSerif: "Source Serif 4"
        case .newsreader: "Newsreader"
        case .jost: "Jost"
        case .georgia: "Georgia"
        }
    }

    /// Les coupes attendues d'une famille embarquée.
    ///
    /// Georgia n'en a pas : le système la fournit, on ne contrôle pas ses
    /// fichiers.
    static func faces(_ font: ReadingFont) -> [String] {
        guard font != .georgia else { return [] }
        let court = family(font).replacingOccurrences(of: " ", with: "")
        return ["Regular", "Italic", "SemiBold"].map { "\(court)-\($0)" }
    }

    /// La fonte du corps par défaut — Literata, OFL.
    ///
    /// Dessinée par TypeTogether pour Google Play Books : lecture prolongée
    /// sur écran, grande hauteur d'x qui tient quand Dynamic Type descend la
    /// taille, chiffres alignés. Georgia, qui occupait cette place, faisait
    /// danser les numéros de verset avec ses chiffres elzéviriens — et
    /// appartient à Microsoft, donc disparaîtrait hors d'iOS.
    public static let body = family(.literata)

    /// L'hébreu compose plus petit que le latin à taille égale : sans cette
    /// correction, les deux écritures ne s'accordent pas sur une même ligne.
    public static let hebrewScale: CGFloat = 1.08

    /// Vrai si la fonte hébraïque est bien embarquée.
    ///
    /// Sans elle, l'hébreu retomberait silencieusement sur une fonte système
    /// et le niqqud se décrocherait — un défaut qu'on préfère voir tôt.
    public static var hebrewAvailable: Bool {
        #if canImport(UIKit)
        UIFont(name: hebrew, size: 12) != nil
        #else
        true
        #endif
    }

    /// Vrai si toutes les coupes d'une fonte de corps sont enregistrées.
    ///
    /// Un oubli dans `UIAppFonts` ne fait pas planter l'app : elle retombe sur
    /// la fonte système, et personne ne s'en aperçoit avant de comparer deux
    /// captures d'écran. Le contrôle porte sur les **coupes** et non sur la
    /// famille, parce qu'une famille amputée de son italique se résout quand
    /// même — en pente simulée, penchée à la main par le moteur de rendu.
    public static func isAvailable(_ font: ReadingFont) -> Bool {
        #if canImport(UIKit)
        if font == .georgia { return UIFont(name: family(font), size: 12) != nil }
        return faces(font).allSatisfy { UIFont(name: $0, size: 12) != nil }
        #else
        return true
        #endif
    }

    /// Vrai si les sept fontes proposées au lecteur répondent toutes.
    public static var bodyAvailable: Bool {
        ReadingFont.allCases.allSatisfy(isAvailable)
    }
}

/// Les styles de texte, adossés aux **niveaux** du texte ONT (§2.1).
///
/// C'est ce que le projet a de particulier, et ce qu'aucune liseuse ordinaire
/// n'a besoin de nommer : chaque niveau a sa voix typographique, et le rendu
/// ne doit jamais choisir une taille au jugé.
public struct ONTTextStyle: Sendable {
    public var font: Font
    public var color: Color

    public init(font: Font, color: Color) {
        self.font = font
        self.color = color
    }
}

/// La fabrique de styles pour un thème et une taille donnés.
public struct ONTTypography: Sendable {
    /// La taille du corps, déjà mise à l'échelle par Dynamic Type.
    public let size: CGFloat
    public let theme: ReadingTheme
    /// La fonte du corps, choisie par le lecteur.
    public let face: ReadingFont

    public init(size: CGFloat, theme: ReadingTheme, face: ReadingFont = .literata) {
        self.size = size
        self.theme = theme
        self.face = face
    }

    /// Le nom de famille de la fonte choisie.
    private var body: String { ONTFonts.family(face) }

    private var ink: Color { ONTColors.ink(theme) }

    /// Les gloses sont plus petites : c'est la voix du projet, elle ne doit
    /// pas concurrencer celle du texte.
    private var glossSize: CGFloat { size * 0.86 }

    // MARK: - Les six styles

    /// Titre d'unité.
    public var display: ONTTextStyle {
        .init(font: .custom(ONTFonts.display, size: size * 1.7), color: ink)
    }

    /// Titre de section, à l'intérieur d'une unité.
    public var heading: ONTTextStyle {
        .init(font: .custom(ONTFonts.display, size: size * 1.25), color: ONTColors.burgundy)
    }

    /// Niveau 1 — le corps de la traduction.
    public var corpus: ONTTextStyle {
        .init(font: .custom(body, size: size), color: ink)
    }

    /// Niveau 1 — un intraduisible, touchable.
    public var term: ONTTextStyle {
        .init(font: .custom(body, size: size), color: ONTColors.accent(theme))
    }

    /// Niveau 1 — un terme important, qui ne se touche pas.
    ///
    /// Semi-gras **et** coloré : la couleur seule ne suffit pas — un lecteur
    /// daltonien ne verrait rien, et l'accessibilité n'est pas une option sur
    /// un texte qu'on lit des heures.
    public var important: ONTTextStyle {
        .init(
            font: .custom(body, size: size).weight(.semibold),
            color: ONTColors.important(theme)
        )
    }

    /// Niveau 2 — une glose.
    public var gloss: ONTTextStyle {
        .init(font: .custom(body, size: glossSize), color: ink.opacity(0.62))
    }

    /// Niveau 3 — la translittération, latine italique.
    public var translit: ONTTextStyle {
        .init(
            font: .custom(body, size: glossSize).italic(),
            color: ink.opacity(0.62)
        )
    }

    /// Niveau 3 — l'hébreu.
    public var hebrew: ONTTextStyle {
        .init(
            font: .custom(ONTFonts.hebrew, size: size * ONTFonts.hebrewScale),
            color: ink.opacity(0.85)
        )
    }

    /// L'hébreu à l'intérieur d'une glose ou d'une translittération.
    public var hebrewSmall: ONTTextStyle {
        .init(
            font: .custom(ONTFonts.hebrew, size: glossSize * ONTFonts.hebrewScale),
            color: ink.opacity(0.85)
        )
    }

    /// Le numéro de verset, en exposant.
    public var verseNumber: ONTTextStyle {
        .init(font: .custom(body, size: size * 0.62), color: ONTColors.accent(theme))
    }

    /// Le décalage vertical du numéro de verset.
    public var verseBaselineOffset: CGFloat { size * 0.34 }

    /// Une ponctuation d'appareil — parenthèses, crochets de glose.
    ///
    /// Non italique, délibérément : une italique incline aussi les crochets,
    /// et un « [ » penché se confond avec une barre oblique. L'appareil doit
    /// rester droit même quand ce qu'il encadre ne l'est pas.
    public var apparatus: ONTTextStyle {
        .init(font: .custom(body, size: glossSize), color: ink.opacity(0.62))
    }
}
