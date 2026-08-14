import Foundation

/// Une couleur de surlignage.
///
/// Le domaine ne connaît que le **nom** de la teinte, jamais sa valeur : la
/// couleur réelle est une décision de présentation, elle vit dans le design
/// system. C'est ce qui permet de retoucher la palette sans migrer les
/// données déjà enregistrées, et de la décliner par thème.
public enum HighlightColor: String, Codable, CaseIterable, Sendable {
    case gold, olive, sky, rose, violet

    public var label: String {
        switch self {
        case .gold: "Or"
        case .olive: "Olive"
        case .sky: "Ciel"
        case .rose: "Rose"
        case .violet: "Violet"
        }
    }
}

/// Un surlignage, posé sur un verset.
///
/// La granularité est le **verset**, pas la plage de caractères : c'est
/// l'unité que le lecteur retient et cite, et la seule qui résiste à une
/// révision du texte. Un décalage de caractères deviendrait faux dès qu'une
/// glose change ; un numéro de verset, non.
public struct Highlight: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var bookId: String
    public var chapterId: String
    public var verse: Int
    public var color: HighlightColor
    public var note: String?
    public var updatedAt: Date
    /// Une **pierre tombale**, et non une absence.
    ///
    /// Supprimer physiquement un surlignage ne se synchronise pas : l'appareil
    /// qui efface n'a plus rien à envoyer, et celui qui reçoit ne voit qu'un
    /// objet manquant — indistinguable d'un objet qu'il n'a pas encore. Il le
    /// renvoie donc, et le surlignage ressuscite au prochain échange.
    ///
    /// On garde donc la ligne, marquée. C'est ce que le serveur attend déjà :
    /// son `Highlight` porte `deleted` depuis le premier jour, et l'app le
    /// mettait à `false` en dur.
    ///
    /// `@decode` tolérant par défaut : un fichier écrit avant ce champ se relit
    /// sans erreur, et ses surlignages sont vivants.
    public var deleted: Bool

    public init(
        id: UUID = UUID(),
        bookId: String,
        chapterId: String,
        verse: Int,
        color: HighlightColor,
        note: String? = nil,
        updatedAt: Date = Date(),
        deleted: Bool = false
    ) {
        self.id = id
        self.bookId = bookId
        self.chapterId = chapterId
        self.verse = verse
        self.color = color
        self.note = note
        self.updatedAt = updatedAt
        self.deleted = deleted
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        bookId = try c.decode(String.self, forKey: .bookId)
        chapterId = try c.decode(String.self, forKey: .chapterId)
        verse = try c.decode(Int.self, forKey: .verse)
        color = try c.decode(HighlightColor.self, forKey: .color)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
    }

    /// La clé d'un verset — `bereshit-18#19`.
    public var key: String { Highlight.key(chapterId: chapterId, verse: verse) }

    public static func key(chapterId: String, verse: Int) -> String {
        "\(chapterId)#\(verse)"
    }
}

/// Où le lecteur en était.
public struct ReadingPosition: Codable, Hashable, Sendable {
    public var bookId: String
    public var chapterId: String
    public var chapterTitle: String
    public var verse: Int
    public var date: Date

    public init(
        bookId: String,
        chapterId: String,
        chapterTitle: String,
        verse: Int,
        date: Date = Date()
    ) {
        self.bookId = bookId
        self.chapterId = chapterId
        self.chapterTitle = chapterTitle
        self.verse = verse
        self.date = date
    }
}

/// Le mode de coloration de la page.
public enum ReadingTheme: String, CaseIterable, Codable, Sendable {
    case parchment
    case light
    case dark

    public var label: String {
        switch self {
        case .parchment: "Parchemin"
        case .light: "Clair"
        case .dark: "Sombre"
        }
    }
}

/// La fonte du corps.
///
/// Un choix laissé au lecteur, pas arbitré une fois pour toutes : ce qui est
/// confortable dépend de la vue, de l'âge, de l'habitude, et personne ne lit
/// une Bible de la même manière. L'app en propose sept ; elle en impose une
/// par défaut, ce qui n'est pas la même chose.
///
/// Toutes sont sous licence OFL et embarquées, sauf `.georgia`, qu'Apple
/// livre avec le système. Le nom de famille correspondant vit dans
/// `ONTDesignSystem` — le domaine nomme un choix, pas un fichier de fonte.
public enum ReadingFont: String, CaseIterable, Codable, Sendable {
    case literata
    case ebGaramond
    case spectral
    case sourceSerif
    case newsreader
    case jost
    case georgia

    public var label: String {
        switch self {
        case .literata: "Literata"
        case .ebGaramond: "EB Garamond"
        case .spectral: "Spectral"
        case .sourceSerif: "Source Serif"
        case .newsreader: "Newsreader"
        case .jost: "Jost"
        case .georgia: "Georgia"
        }
    }

    /// Ce que la fonte apporte, en une ligne — de quoi choisir sans être
    /// typographe.
    public var note: String {
        switch self {
        case .literata: "Dessinée pour la lecture longue à l'écran"
        case .ebGaramond: "La lettre du livre imprimé classique"
        case .spectral: "Ouverte et franche, tient les petites tailles"
        case .sourceSerif: "Neutre, elle s'efface derrière le texte"
        case .newsreader: "Étroite, plus de texte par écran"
        case .jost: "Géométrique — la fonte de l'édition imprimée"
        case .georgia: "La fonte du système, robuste et familière"
        }
    }
}

/// Ce que le lecteur a réglé.
///
/// Les deux premiers champs ne sont pas des préférences d'affichage : ce sont
/// les **niveaux du texte** (CLAUDE.md §2.1), et pouvoir les éteindre est la
/// raison d'être de la liseuse. Corps seul, on lit d'une traite ; gloses
/// allumées, on lit l'appareil ; hébreu allumé, on travaille.
public struct ReadingPreferences: Codable, Hashable, Sendable {
    /// Niveau 2 — les gloses.
    public var showGloss: Bool
    /// Niveau 3 — translittération et hébreu.
    public var showLevel3: Bool
    /// Le corps du texte, en points, avant mise à l'échelle Dynamic Type.
    public var textSize: Double
    /// L'interligne, en multiple de la taille du corps.
    public var lineSpacing: Double
    public var theme: ReadingTheme
    /// La fonte du corps. `Codable` avec une valeur par défaut : un réglage
    /// enregistré avant l'arrivée de ce champ doit se relire sans erreur.
    public var bodyFont: ReadingFont
    /// Les versets à la suite, en prose continue, plutôt qu'un par bloc.
    ///
    /// Deux façons de lire, pas deux goûts : le bloc par verset sert l'étude —
    /// on vise, on annote, on compare. La prose continue sert la lecture
    /// suivie, où la découpe en versets est un artefact du XIIIᵉ siècle qui
    /// hache une phrase en trois.
    public var continuous: Bool
    /// Le rappel quotidien.
    ///
    /// Ici plutôt que dans un second magasin, parce qu'il n'y a qu'un port de
    /// préférences et qu'en ouvrir un deuxième pour trois entiers coûterait
    /// plus que la petite impureté de ranger un rappel avec des réglages
    /// d'affichage.
    public var daily: DailyVerseSchedule

    public init(
        showGloss: Bool = true,
        showLevel3: Bool = true,
        textSize: Double = 19,
        lineSpacing: Double = 0.5,
        theme: ReadingTheme = .parchment,
        bodyFont: ReadingFont = .literata,
        continuous: Bool = false,
        daily: DailyVerseSchedule = .default
    ) {
        self.showGloss = showGloss
        self.showLevel3 = showLevel3
        self.textSize = textSize
        self.lineSpacing = lineSpacing
        self.theme = theme
        self.bodyFont = bodyFont
        self.continuous = continuous
        self.daily = daily
    }

    // Décodage tolérant : les réglages du lecteur sont sur son appareil, et
    // une clé absente ne doit pas les effacer tous.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defauts = ReadingPreferences.default
        showGloss = try c.decodeIfPresent(Bool.self, forKey: .showGloss) ?? defauts.showGloss
        showLevel3 = try c.decodeIfPresent(Bool.self, forKey: .showLevel3) ?? defauts.showLevel3
        textSize = try c.decodeIfPresent(Double.self, forKey: .textSize) ?? defauts.textSize
        lineSpacing = try c.decodeIfPresent(Double.self, forKey: .lineSpacing)
            ?? defauts.lineSpacing
        theme = try c.decodeIfPresent(ReadingTheme.self, forKey: .theme) ?? defauts.theme
        bodyFont = try c.decodeIfPresent(ReadingFont.self, forKey: .bodyFont) ?? defauts.bodyFont
        continuous = try c.decodeIfPresent(Bool.self, forKey: .continuous) ?? defauts.continuous
        daily = try c.decodeIfPresent(DailyVerseSchedule.self, forKey: .daily) ?? defauts.daily
    }

    public static let `default` = ReadingPreferences()
}
