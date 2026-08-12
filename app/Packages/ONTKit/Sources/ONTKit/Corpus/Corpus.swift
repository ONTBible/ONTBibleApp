import Foundation

/// L'état d'une unité dans le flux de validation (CLAUDE.md §12).
public enum Status: String, Decodable, Sendable {
    /// Fait référence. Seules ces unités voyagent dans la distribution.
    case locked
    /// Rédigée, en attente de la relecture de l'auteur.
    case brouillon
}

/// Le sous-titre de référence — `*(Genèse / בְּרֵאשִׁית 18:1-33)*`.
///
/// Le nom français n'est qu'un pont de navigation pour le lecteur occidental
/// (§2.6) ; le renvoi biblique est la seule trace de la numérotation d'origine.
public struct Subtitle: Decodable, Hashable, Sendable {
    public let french: String
    public let hebrew: String
    public let reference: String?
}

/// Le pied d'une unité — version, verrouillage, décisions terminologiques.
public struct Footer: Decodable, Hashable, Sendable {
    public let version: String?
    public let locked: Bool
    public let notes: [Block]
}

/// Une unité ONT : un chapitre fonctionnel, ou la feuille d'introduction d'un
/// livre (§2.7).
///
/// « Unité » et non « chapitre biblique » : un bloc se clôt quand une fonction
/// cosmique est accomplie, pas quand un numéro de Langton change (§2.3).
public struct Chapter: Decodable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Decodable, Sendable {
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
public struct ChapterStub: Decodable, Hashable, Sendable, Identifiable {
    public let id: String
    public let n: Int
    public let title: String
    public let status: Status
    public let verseCount: Int
    public let reference: String?
}

/// Un livre — un des 70 slots de `corpus-order.md`.
public struct BookOutline: Decodable, Hashable, Sendable, Identifiable {
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

    public var verseCount: Int { chapters.reduce(0) { $0 + $1.verseCount } }
}

/// Le contenu complet d'un livre.
public struct Book: Decodable, Hashable, Sendable, Identifiable {
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
}

/// Un mode fonctionnel — Torah, Nevi'im, Ketouvim, Nistarot (§1).
///
/// Ce ne sont pas des divisions canoniques mais des modes distincts
/// d'engagement avec le réel : institution, lecture dans l'histoire,
/// habitation intérieure, traversée architecturale.
public struct Mode: Decodable, Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let order: Int
    public let books: [BookOutline]
}

/// Un corpus — la *Kenesset* ou la *Berit Hadashah*.
public struct Corpus: Decodable, Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let order: Int
    public let modes: [Mode]
}

public struct CorpusFile: Decodable, Sendable {
    public let schema: Int
    public let corpora: [Corpus]
}
