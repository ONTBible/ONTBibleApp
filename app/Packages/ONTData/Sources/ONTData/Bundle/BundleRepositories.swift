import Foundation
import ONTKit

/// Le chargement des données produites par le pipeline.
///
/// Toute la connaissance du format — nom des fichiers, sous-dossiers, schéma
/// JSON — est enfermée ici. Si le pipeline change sa sortie, c'est le seul
/// endroit à toucher.
///
/// Le découpage du chargement est délibéré : l'arborescence des 70 slots et
/// le lexique arrivent au lancement (20 Ko + 76 Ko), le contenu d'un livre
/// seulement quand on l'ouvre (*Bereshit* fait 750 Ko à lui seul), l'index de
/// recherche à la première requête (600 Ko).
public enum BundleLoader {
    public enum Failure: LocalizedError {
        case missing(String)

        public var errorDescription: String? {
            switch self {
            case .missing(let name):
                // Sans guillemets, délibérément : le filet d'expurgation de
                // Sentry masque tout texte cité de plus de douze caractères —
                // c'est ainsi qu'une note de lecteur serait interceptée. Un
                // nom de ressource ne doit pas ressembler à une note, sinon
                // le diagnostic part expurgé et ne dit plus rien.
                "Ressource introuvable dans le bundle : \(name)"
            }
        }
    }

    static func decode<T: Decodable>(
        _ name: String,
        as type: T.Type = T.self,
        subdirectory: String? = nil,
        bundle: Foundation.Bundle
    ) throws -> T {
        let directory = ["data", subdirectory].compactMap(\.self).joined(separator: "/")
        guard
            let url = bundle.url(
                forResource: name,
                withExtension: "json",
                subdirectory: directory
            ) ?? bundle.url(forResource: name, withExtension: "json")
        else {
            throw Failure.missing("\(directory)/\(name).json")
        }
        return try JSONDecoder().decode(T.self, from: try Data(contentsOf: url))
    }
}

// MARK: - Corpus

/// Le corpus, lu du bundle de l'app.
///
/// `@unchecked Sendable` assumé : le cache est protégé par un verrou, et le
/// contenu chargé est immuable une fois décodé.
public final class BundleCorpusRepository: CorpusRepository, @unchecked Sendable {
    private let bundle: Foundation.Bundle
    private let lock = NSLock()
    private var cachedCorpora: [Corpus]?
    private var cachedBooks: [String: Book] = [:]

    public init(bundle: Foundation.Bundle = .main) {
        self.bundle = bundle
    }

    public func corpora() throws -> [Corpus] {
        lock.lock()
        defer { lock.unlock() }

        if let cachedCorpora { return cachedCorpora }
        let file: ONTSchema.CorpusFile = try BundleLoader.decode("corpus", bundle: bundle)
        let sorted = file.corpora.map(Corpus.init).sorted { $0.order < $1.order }
        cachedCorpora = sorted
        return sorted
    }

    public func book(_ id: String) throws -> Book {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cachedBooks[id] { return cached }
        let dto: ONTSchema.Book = try BundleLoader.decode(id, subdirectory: "books", bundle: bundle)
        let book = Book(dto)
        cachedBooks[id] = book
        return book
    }
}

// MARK: - Lexique

public final class BundleGlossaryRepository: GlossaryRepository, @unchecked Sendable {
    private let bundle: Foundation.Bundle
    private let lock = NSLock()
    private var cachedEntries: [GlossaryEntry]?
    private var cachedOccurrences: [String: [Occurrence]]?

    public init(bundle: Foundation.Bundle = .main) {
        self.bundle = bundle
    }

    public func entries() throws -> [GlossaryEntry] {
        lock.lock()
        defer { lock.unlock() }

        if let cachedEntries { return cachedEntries }
        let file: ONTSchema.GlossaryFile = try BundleLoader.decode("glossary", bundle: bundle)
        let entries = file.entries.map(GlossaryEntry.init)
        cachedEntries = entries
        return entries
    }

    public func occurrences(of lemma: String) -> [Occurrence] {
        lock.lock()
        defer { lock.unlock() }

        if cachedOccurrences == nil {
            cachedOccurrences = (try? BundleLoader.decode(
                "occurrences",
                as: ONTSchema.OccurrencesFile.self,
                bundle: bundle
            ))?.byLemma.mapValues { $0.map(Occurrence.init) } ?? [:]
        }
        return cachedOccurrences?[lemma] ?? []
    }
}

// MARK: - Recherche

public final class BundleSearchIndex: SearchIndex, @unchecked Sendable {
    private let bundle: Foundation.Bundle
    private let lock = NSLock()
    private var cached: [SearchRecord]?

    public init(bundle: Foundation.Bundle = .main) {
        self.bundle = bundle
    }

    public func records() -> [SearchRecord] {
        lock.lock()
        defer { lock.unlock() }

        if let cached { return cached }
        let loaded = (try? BundleLoader.decode(
            "search",
            as: ONTSchema.SearchFile.self,
            bundle: bundle
        ))?.records.map(SearchRecord.init) ?? []
        cached = loaded
        return loaded
    }
}

// MARK: - Verset du jour

/// Le vivier quotidien, lu du bundle.
///
/// Chargé paresseusement et gardé : le widget est réveillé, lit une fois,
/// puis meurt. L'app, elle, le relit à chaque changement de jour.
public final class BundleDailyVerseRepository: DailyVerseRepository, @unchecked Sendable {
    private let bundle: Foundation.Bundle
    private let lock = NSLock()
    private var cached: [DailyVerse]?

    public init(bundle: Foundation.Bundle = .main) {
        self.bundle = bundle
    }

    public func pool() -> [DailyVerse] {
        lock.lock()
        defer { lock.unlock() }

        if let cached { return cached }
        let loaded = (try? BundleLoader.decode(
            "daily",
            as: ONTSchema.DailyFile.self,
            bundle: bundle
        ))?.verses.map(DailyVerse.init) ?? []
        cached = loaded
        return loaded
    }
}

// `DailyFile` était déclarée ici, à la main. Elle est engendrée maintenant —
// `ONTSchema.DailyFile` — comme les cinq autres enveloppes de fichier.

/// Les fiches des Shemot, embarquées avec l'app.
///
/// La même forme que le glossaire, et un fichier à part — `shemot.json`, 564 Ko
/// pour 194 fiches. Le charger paresseusement compte : c'est le plus gros
/// fichier du bundle après le corpus, et un lecteur qui ne touche jamais un nom
/// propre n'a aucune raison de le payer.
public final class BundleShemotRepository: ShemotRepository, @unchecked Sendable {
    private let bundle: Foundation.Bundle
    private let lock = NSLock()
    private var cached: [ShemEntry]?

    public init(bundle: Foundation.Bundle = .main) {
        self.bundle = bundle
    }

    public func entries() throws -> [ShemEntry] {
        lock.lock()
        defer { lock.unlock() }

        if let cached { return cached }
        let file: ONTSchema.ShemotFile = try BundleLoader.decode("shemot", bundle: bundle)
        let entries = file.entries.map(ShemEntry.init)
        cached = entries
        return entries
    }
}
