import Foundation

/// L'état d'une unité dans le flux de validation (CLAUDE.md §12).
public enum Status: String, Sendable {
    /// Fait référence. Seules ces unités voyagent dans la distribution.
    case locked
    /// Rédigée, en attente de la relecture de l'auteur.
    case brouillon
}

/// Le sous-titre de référence — `*(Genèse / בְּרֵאשִׁית 18:1-33)*`.
///
/// Le nom français n'est qu'un pont de navigation pour le lecteur occidental
/// (§2.6) ; le renvoi biblique est la seule trace de la numérotation d'origine.
public struct Subtitle: Hashable, Sendable {
    public let french: String
    public let hebrew: String
    public let reference: String?

    public init(french: String, hebrew: String, reference: String?) {
        self.french = french
        self.hebrew = hebrew
        self.reference = reference
    }
}

/// Le pied d'une unité — version, verrouillage, décisions terminologiques.
public struct Footer: Hashable, Sendable {
    public let version: String?
    public let locked: Bool
    public let notes: [Block]

    public init(version: String?, locked: Bool, notes: [Block]) {
        self.version = version
        self.locked = locked
        self.notes = notes
    }
}

/// Une unité ONT : un chapitre fonctionnel, ou la feuille d'introduction d'un
/// livre (§2.7).
///
/// « Unité » et non « chapitre biblique » : un bloc se clôt quand une fonction
/// cosmique est accomplie, pas quand un numéro de Langton change (§2.3).
public struct Chapter: Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case chapter
        case intro
    }

    public let id: String
    public let bookId: String
    public let kind: Kind
    public let n: Int
    public let title: String
    public let titleNodes: [Inline]
    public let subtitle: Subtitle?
    public let status: Status
    public let blocks: [Block]
    public let footer: Footer?
    public let verseCount: Int
    public let lemmas: [String]

    /// Initialiseur public — l'init mémberwise synthétisé reste interne, et
    /// les tests comme les aperçus ont besoin de fabriquer des unités.
    public init(
        id: String, bookId: String, kind: Kind, n: Int,
        title: String, titleNodes: [Inline] = [], subtitle: Subtitle? = nil,
        status: Status = .locked, blocks: [Block] = [], footer: Footer? = nil,
        verseCount: Int = 0, lemmas: [String] = []
    ) {
        self.id = id
        self.bookId = bookId
        self.kind = kind
        self.n = n
        self.title = title
        self.titleNodes = titleNodes
        self.subtitle = subtitle
        self.status = status
        self.blocks = blocks
        self.footer = footer
        self.verseCount = verseCount
        self.lemmas = lemmas
    }

    /// Tous les versets de l'unité, à plat.
    public var verses: [Verse] {
        blocks.flatMap { block -> [Verse] in
            guard case .verses(let verses) = block else { return [] }
            return verses
        }
    }
}

/// La forme allégée d'une unité dans l'arborescence de navigation.
public struct ChapterStub: Hashable, Sendable, Identifiable {
    public let id: String
    public let n: Int
    public let title: String
    public let status: Status
    public let verseCount: Int
    public let reference: String?

    public init(id: String, n: Int, title: String, status: Status, verseCount: Int, reference: String?) {
        self.id = id
        self.n = n
        self.title = title
        self.status = status
        self.verseCount = verseCount
        self.reference = reference
    }
}

/// Un livre — un des 70 slots de `corpus-order.md`.
public struct BookOutline: Hashable, Sendable, Identifiable {
    public let id: String
    /// Le numéro global 01–70, continu sur tout le corpus.
    public let slot: Int
    /// Le nom hébreu translittéré — le vrai titre du livre (§2.6).
    public let title: String
    /// Le nom français, repère pour le lecteur occidental.
    public let french: String
    public let hebrew: String?
    public let groupId: String?
    /// Vrai tant qu'aucun texte n'a été rédigé pour ce slot.
    public let empty: Bool
    public let intro: ChapterStub?
    public let chapters: [ChapterStub]

    public init(id: String, slot: Int, title: String, french: String, hebrew: String?, groupId: String?, empty: Bool, intro: ChapterStub?, chapters: [ChapterStub]) {
        self.id = id
        self.slot = slot
        self.title = title
        self.french = french
        self.hebrew = hebrew
        self.groupId = groupId
        self.empty = empty
        self.intro = intro
        self.chapters = chapters
    }

    public var verseCount: Int { chapters.reduce(0) { $0 + $1.verseCount } }
}

/// Le contenu complet d'un livre.
public struct Book: Hashable, Sendable, Identifiable {
    public let id: String
    public let slot: Int
    public let title: String
    public let french: String
    public let hebrew: String?
    public let corpusId: String
    public let modeId: String
    public let groupId: String?
    public let chapters: [Chapter]
    public let intro: Chapter?
    public let empty: Bool

    public init(id: String, slot: Int, title: String, french: String, hebrew: String?, corpusId: String, modeId: String, groupId: String?, chapters: [Chapter], intro: Chapter?, empty: Bool) {
        self.id = id
        self.slot = slot
        self.title = title
        self.french = french
        self.hebrew = hebrew
        self.corpusId = corpusId
        self.modeId = modeId
        self.groupId = groupId
        self.chapters = chapters
        self.intro = intro
        self.empty = empty
    }
}

/// Un mode fonctionnel — Torah, Nevi'im, Ketouvim, Nistarot (§1).
///
/// Ce ne sont pas des divisions canoniques mais des modes distincts
/// d'engagement avec le réel : institution, lecture dans l'histoire,
/// habitation intérieure, traversée architecturale.
/// Un conteneur de livres — les *Eduyot*, les *Trei Asar*, les deux *Igerot*.
///
/// **Nommé en français, et pas `Group`** : SwiftUI porte déjà un `Group`, et
/// une vue qui écrirait `Group { … }` à côté de celui-ci deviendrait ambiguë
/// pour le compilateur. Le site l'appelle `Conteneur` ; les deux liseuses
/// parlent donc la même langue.
///
/// Il existait dans les données sous forme d'un identifiant porté par chaque
/// livre, et **aucune interface ne l'affichait**. Les vingt-et-une *Igerot* se
/// lisaient comme une liste plate, alors que leur ordre porte un argument.
public struct Conteneur: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let french: String
    public let glose: String?
    /// La ligne de sens qui **précède** ce conteneur, quand la coupure est une
    /// rupture et non un rangement. Le *Ḥurban* est le seul à en porter une :
    /// une césure marquée partout ne marquerait plus rien.
    public let rupture: String?

    public init(id: String, title: String, french: String, glose: String?, rupture: String?) {
        self.id = id
        self.title = title
        self.french = french
        self.glose = glose
        self.rupture = rupture
    }
}

public struct Mode: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    /// Le pont de navigation — le mot que le lecteur cherche. Les
    /// intraduisibles y sont **rendus** : *Torah* devient « la Loi ».
    public let french: String?
    /// Ce que le nom ONT veut dire, quand ça n'est pas déjà le pont. Les
    /// intraduisibles y **restent en hébreu** : « la Fondation ».
    public let glose: String?
    public let order: Int
    /// Dans l'ordre où leurs livres paraissent. Vide pour la plupart.
    public let groups: [Conteneur]
    public let books: [BookOutline]

    public init(
        id: String,
        title: String,
        french: String? = nil,
        glose: String? = nil,
        order: Int,
        groups: [Conteneur] = [],
        books: [BookOutline]
    ) {
        self.id = id
        self.title = title
        self.french = french
        self.glose = glose
        self.order = order
        self.groups = groups
        self.books = books
    }
}

/// Un corpus — la *Kenesset* ou la *Berit Hadashah*.
public struct Corpus: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    /// Le pont de navigation — le mot que le lecteur cherche. Les
    /// intraduisibles y sont **rendus** : *Torah* devient « la Loi ».
    public let french: String?
    /// Ce que le nom ONT veut dire, quand ça n'est pas déjà le pont. Les
    /// intraduisibles y **restent en hébreu** : « la Fondation ».
    public let glose: String?
    public let order: Int
    public let modes: [Mode]

    public init(
        id: String,
        title: String,
        french: String? = nil,
        glose: String? = nil,
        order: Int,
        modes: [Mode]
    ) {
        self.id = id
        self.title = title
        self.french = french
        self.glose = glose
        self.order = order
        self.modes = modes
    }
}

// `CorpusFile` vivait ici. C'est une **enveloppe de fichier** — un numéro de
// schéma et une liste — pas un concept de l'ONT. Elle n'a donc rien à faire
// dans le domaine : `ONTSchema.CorpusFile`, engendré, la remplace.
