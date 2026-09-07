import ONTKit
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

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

    /// Les titres — Jost, OFL. La géométrique du combination mark.
    ///
    /// C'est la règle du site, que l'app ne suivait qu'à moitié : Jost pour
    /// « titres, navigation, capitales », Literata pour le reste. Le corps
    /// suivait déjà, les titres non — ils étaient en Frank Ruhl Libre, arrivée
    /// au commit initial sans raison consignée.
    ///
    /// ## La taille n'a pas eu à bouger, et ce n'était pas évident
    ///
    /// La webapp note que Jost a une « hauteur d'x basse » — vrai **face à
    /// Literata**, dont l'œil est très ouvert. Face à Frank Ruhl, mesuré dans
    /// les tables `OS/2` des deux fichiers :
    ///
    ///     Frank Ruhl Libre   hauteur d'x 0,470 em   capitale 0,660 em
    ///     Jost               hauteur d'x 0,460 em   capitale 0,700 em
    ///
    /// Deux pour cent d'écart sur l'œil, et une capitale **plus grande** de
    /// six. Un titre composé au même corps se lit donc aussi gros, un titre en
    /// capitales un peu plus. Corriger la taille « pour compenser » aurait
    /// grossi ce qu'il fallait laisser.
    public static let display = "Jost-SemiBold"

    /// La fonte des barres et des listes — Jost en graisse normale.
    ///
    /// **Pourquoi une coupe de plus, et pas `display`.** `display` est le
    /// SemiBold : juste pour un titre, un cran trop lourd pour une ligne de
    /// navigation. La barre latérale de l'iPad, que le système compose, pose
    /// ses lignes en graisse normale ; celle du Mac, que l'app peint, les
    /// posait en SemiBold. Les deux captures côte à côte ne montraient pas la
    /// même barre, et c'était la première raison.
    ///
    /// La coupe est déjà embarquée et déjà inscrite — `Jost-Regular.ttf` dans
    /// `UIAppFonts` pour iOS, et prise par `ATSApplicationFontsPath` sur le
    /// Mac. Rien à ajouter au bundle.
    public static let navigation = "Jost-Regular"

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

    /// Une fonte répond-elle à son nom PostScript ?
    ///
    /// **Écrit une fois, pour toutes les plateformes.** Les deux gardes qui
    /// suivent posaient chacune un `#if canImport(UIKit)` et retombaient sur
    /// `true` ailleurs — c'est-à-dire sur le Mac, où rien n'était donc vérifié.
    /// Le catalogue y affichait « embarquée » en vert quoi qu'il arrive.
    ///
    /// Le défaut que ça a couvert : la cible du Mac ne déclarait aucune clé
    /// d'inscription de fontes. Literata ne se résolvait nulle part, et l'hébreu
    /// ne se résolvait que sur la machine de l'auteur, qui a Ezra SIL installée
    /// à titre personnel. La garde disait vert, et elle avait raison de dire
    /// vert : elle ne regardait pas.
    ///
    /// **Le repli est `false`, non `true`.** Une garde qui ne sait pas ne doit
    /// pas rassurer : elle doit se taire bruyamment. C'est ce qui aurait fait
    /// voir le défaut le jour où il est apparu, plutôt que trois semaines plus
    /// tard en comparant deux captures.
    private static func repond(_ nom: String) -> Bool {
        #if canImport(UIKit)
            return UIFont(name: nom, size: 12) != nil
        #elseif canImport(AppKit)
            return NSFont(name: nom, size: 12) != nil
        #else
            return false
        #endif
    }

    /// Vrai si la fonte hébraïque est bien embarquée.
    ///
    /// Sans elle, l'hébreu retomberait silencieusement sur une fonte système
    /// et le niqqud se décrocherait — un défaut qu'on préfère voir tôt.
    public static var hebrewAvailable: Bool {
        repond(hebrew)
    }

    /// Vrai si toutes les coupes d'une fonte de corps sont enregistrées.
    ///
    /// Un oubli dans `UIAppFonts` ne fait pas planter l'app : elle retombe sur
    /// la fonte système, et personne ne s'en aperçoit avant de comparer deux
    /// captures d'écran. Le contrôle porte sur les **coupes** et non sur la
    /// famille, parce qu'une famille amputée de son italique se résout quand
    /// même — en pente simulée, penchée à la main par le moteur de rendu.
    public static func isAvailable(_ font: ReadingFont) -> Bool {
        // Georgia vient du système et n'a pas de coupes embarquées à compter.
        if font == .georgia { return repond(family(font)) }
        return faces(font).allSatisfy(repond)
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

    /// L'encre du niveau 2 — une teinte du thème, plus une opacité au jugé.
    private var soft: Color { ONTColors.inkSoft(theme) }

    /// Les gloses sont plus petites : c'est la voix du projet, elle ne doit
    /// pas concurrencer celle du texte.
    private var glossSize: CGFloat { size * 0.86 }

    // MARK: - Les six styles

    /// Titre d'unité.
    public var display: ONTTextStyle {
        .init(font: .custom(ONTFonts.display, size: size * 1.7), color: ONTColors.inkStrong(theme))
    }

    /// Titre de section, à l'intérieur d'une unité.
    ///
    /// La couleur passe par le thème depuis qu'on a mesuré : le bordeaux posé
    /// en dur donnait 1,23:1 sur le fond sombre. Un titre invisible.
    public var heading: ONTTextStyle {
        .init(
            font: .custom(ONTFonts.display, size: size * 1.25),
            color: ONTColors.brandInk(theme)
        )
    }

    /// Niveau 1 — le corps de la traduction.
    public var corpus: ONTTextStyle {
        .init(font: .custom(body, size: size), color: ink)
    }

    /// Niveau 1 — un intraduisible, touchable.
    public var term: ONTTextStyle {
        .init(font: .custom(body, size: size), color: ONTColors.accent(theme))
    }

    /// Niveau 1 — un **Shem**, touchable.
    ///
    /// Même graisse que le corps, comme un intraduisible : c'est la couleur
    /// qui distingue, et le nom doit se lire dans le fil de la phrase. Un
    /// semi-gras en ferait une insistance, alors qu'un nom propre n'insiste
    /// pas — il désigne.
    public var shem: ONTTextStyle {
        .init(font: .custom(body, size: size), color: ONTColors.shem(theme))
    }

    /// Niveau 1 — une accentuation, qui ne se touche pas.
    ///
    /// Semi-gras **et** coloré : la couleur seule ne suffit pas — un lecteur
    /// daltonien ne verrait rien, et l'accessibilité n'est pas une option sur
    /// un texte qu'on lit des heures.
    public var accentuation: ONTTextStyle {
        .init(
            font: .custom(body, size: size).weight(.semibold),
            color: ONTColors.accentuation(theme)
        )
    }

    /// Niveau 2 — une glose.
    public var gloss: ONTTextStyle {
        .init(font: .custom(body, size: glossSize), color: soft)
    }

    /// Niveau 3 — la translittération, latine italique.
    public var translit: ONTTextStyle {
        .init(
            font: .custom(body, size: glossSize).italic(),
            color: soft
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
        .init(font: .custom(body, size: glossSize), color: soft)
    }
}
