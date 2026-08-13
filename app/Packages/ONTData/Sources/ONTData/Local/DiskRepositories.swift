import Foundation
import ONTKit

/// Le corpus, lu du disque quand il y est, du bundle sinon.
///
/// ## Le bundle n'est pas un repli, c'est le socle
///
/// L'app est livrée avec un corpus complet. Il fait marcher une installation
/// neuve **avant** tout réseau — dans un train, dans un avion, sur un forfait
/// épuisé — et il ne disparaît jamais.
///
/// Ce que [`CorpusUpdater`] télécharge vient le **recouvrir**, fichier par
/// fichier. Un livre présent sur le disque est lu du disque ; les autres
/// continuent de venir du bundle. Il n'y a donc aucun état intermédiaire
/// invalide : à tout instant, chaque livre est lisible dans l'une ou l'autre
/// version, jamais dans aucune.
///
/// ## Pourquoi une réalisation de plus, et pas une option dans l'ancienne
///
/// `CorpusRepository` est un **port**. En écrire une seconde réalisation ne
/// touche ni les vues, ni les modèles, ni les tests des autres : c'est
/// exactement ce que cette architecture permettait, et la première fois qu'on
/// s'en sert.
///
/// `@unchecked Sendable` assumé, comme pour le bundle : le cache est protégé
/// par un verrou, et le contenu décodé est immuable.
public final class DiskCorpusRepository: CorpusRepository, @unchecked Sendable {
    private let dossier: URL
    private let socle: any CorpusRepository
    private let lock = NSLock()
    private var cachedCorpora: [Corpus]?
    private var cachedBooks: [String: Book] = [:]

    public init(
        dossier: URL = CorpusUpdater.dossierParDefaut(),
        socle: any CorpusRepository = BundleCorpusRepository()
    ) {
        self.dossier = dossier
        self.socle = socle
    }

    public func corpora() throws -> [Corpus] {
        lock.lock()
        defer { lock.unlock() }

        if let cachedCorpora { return cachedCorpora }
        let corpora: [Corpus]
        if let file: CorpusFile = lire("corpus.json") {
            corpora = file.corpora.sorted { $0.order < $1.order }
        } else {
            corpora = try socle.corpora()
        }
        cachedCorpora = corpora
        return corpora
    }

    public func book(_ id: String) throws -> Book {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cachedBooks[id] { return cached }
        let book: Book = try lire("books/\(id).json") ?? socle.book(id)
        cachedBooks[id] = book
        return book
    }

    /// Lit un fichier du disque, ou rend `nil`.
    ///
    /// **Aucune erreur ne remonte**, et c'est délibéré : un fichier absent est
    /// le cas normal — l'app n'a pas encore téléchargé ce livre — et un fichier
    /// illisible ne doit pas empêcher de lire. Dans les deux cas, le socle
    /// répond.
    private func lire<T: Decodable>(_ nom: String) -> T? {
        guard let octets = try? Data(contentsOf: dossier.appendingPathComponent(nom)) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: octets)
    }

    /// Oublie ce qui est en mémoire, après une mise à jour.
    ///
    /// Sans ça, le corpus fraîchement téléchargé n'apparaîtrait qu'au prochain
    /// lancement : les caches tiennent la version d'avant, et rien ne leur dit
    /// qu'elle a vieilli.
    public func oublier() {
        lock.lock()
        defer { lock.unlock() }
        cachedCorpora = nil
        cachedBooks.removeAll()
    }
}

/// Le lexique, même principe.
public final class DiskGlossaryRepository: GlossaryRepository, @unchecked Sendable {
    private let dossier: URL
    private let socle: any GlossaryRepository
    private let lock = NSLock()
    private var cachedEntries: [GlossaryEntry]?
    private var cachedOccurrences: [String: [Occurrence]]?

    public init(
        dossier: URL = CorpusUpdater.dossierParDefaut(),
        socle: any GlossaryRepository = BundleGlossaryRepository()
    ) {
        self.dossier = dossier
        self.socle = socle
    }

    public func entries() throws -> [GlossaryEntry] {
        lock.lock()
        defer { lock.unlock() }

        if let cachedEntries { return cachedEntries }
        let entries: [GlossaryEntry]
        if let file: GlossaryFile = lire("glossary.json") {
            entries = file.entries
        } else {
            entries = try socle.entries()
        }
        cachedEntries = entries
        return entries
    }

    public func occurrences(of lemma: String) -> [Occurrence] {
        lock.lock()

        if cachedOccurrences == nil, let file: OccurrencesFile = lire("occurrences.json") {
            cachedOccurrences = file.byLemma
        }
        if let table = cachedOccurrences {
            defer { lock.unlock() }
            return table[lemma] ?? []
        }

        // Rien sur le disque : c'est le socle qui répond, et le verrou est
        // rendu **avant** de l'appeler. Le garder exposerait à un interblocage
        // le jour où le socle voudrait, lui aussi, verrouiller quelque chose.
        lock.unlock()
        return socle.occurrences(of: lemma)
    }

    private func lire<T: Decodable>(_ nom: String) -> T? {
        guard let octets = try? Data(contentsOf: dossier.appendingPathComponent(nom)) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: octets)
    }

    public func oublier() {
        lock.lock()
        defer { lock.unlock() }
        cachedEntries = nil
        cachedOccurrences = nil
    }
}
