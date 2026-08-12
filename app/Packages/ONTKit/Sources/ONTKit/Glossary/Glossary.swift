import Foundation

/// Une entrée du lexique : un intraduisible, toutes formes confondues.
///
/// C'est l'équivalent ONT d'un numéro Strong, à ceci près qu'il n'a pas fallu
/// l'inventer — le glossaire du `CLAUDE.md` §2.5 et §3 *est* le lexique, et le
/// pipeline le dérive à chaque build.
public struct GlossaryEntry: Decodable, Hashable, Sendable, Identifiable {
    /// La clé de jointure avec `Inline.term(_:lemma:)`.
    public let lemma: String
    /// La forme d'affichage — `chesed`, `El Elyon`, `She'ol`.
    public let title: String
    /// Vrai si le terme est balisé dans le texte, donc touchable à la lecture.
    /// Faux pour le reste du vocabulaire fixé (§3) — *bara* → « orchestrer » —
    /// traduit dans le corps, donc invisible au toucher mais consultable ici.
    public let tagged: Bool
    public let forms: [String]
    public let hebrew: String?
    /// La traduction ONT arrêtée, quand le terme en a une.
    public let rendering: String?
    /// Le champ sémantique complet — ce que le terme signifie, et ce qu'il
    /// n'est pas.
    public let definition: [Block]?
    /// La note de balisage (§2.5) — règles de rendu, formes dérivées.
    public let taggingNote: [Block]?
    /// Le premier emploi déclaré — `Bereshit 15:6`.
    public let firstUse: String?
    public let sourceSection: String?
    public let count: Int
    /// Occurrences dans le corps de la traduction (niveau 1).
    public let bodyCount: Int
    /// Occurrences dans les gloses (niveau 2).
    public let glossCount: Int

    public var id: String { lemma }
}

/// Une occurrence d'un intraduisible.
public struct Occurrence: Decodable, Hashable, Sendable {
    /// Le niveau où la forme paraît (§2.1).
    ///
    /// La distinction n'est pas cosmétique : « où ce mot est dans le texte »
    /// et « où on l'explique » ne se cherchent pas de la même façon.
    public enum Level: String, Decodable, Sendable {
        case body
        case gloss
    }

    public let bookId: String
    public let chapterId: String
    public let verse: Int?
    public let form: String
    public let level: Level
    public let snippet: String
}

public struct GlossaryFile: Decodable, Sendable {
    public let schema: Int
    public let entries: [GlossaryEntry]
}

public struct OccurrencesFile: Decodable, Sendable {
    public let schema: Int
    public let byLemma: [String: [Occurrence]]
}
