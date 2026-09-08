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
    private var dossier: URL
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
        if let file: ONTSchema.CorpusFile = lire("corpus.json") {
            corpora = file.corpora.map(Corpus.init).sorted { $0.order < $1.order }
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
        let book: Book
        if let dto: ONTSchema.Book = lire("books/\(id).json") {
            book = Book(dto)
        } else {
            book = try socle.book(id)
        }
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

    /// **Change la source, sans changer le dépôt.**
    ///
    /// Le mode développeur du Mac reconstruit le corpus depuis le vault et
    /// l'écrit à côté du corpus publié. Sans ce point d'entrée, il l'écrivait
    /// et **personne ne le lisait** : le dossier était fixé à la construction.
    ///
    /// Le défaut ne se voyait pas, parce que le bandeau affichait le compte que
    /// le pipeline venait de rendre — un nombre juste, sur un corpus que la
    /// liseuse n'ouvrait pas. C'est l'auteur qui l'a pris, en cherchant le
    /// **chapitre** plutôt que le nombre : « y avait certes écrit 45 mais le
    /// chapitre 20 n'est jamais apparu ».
    ///
    /// On vide les caches dans le même verrou : les rendre séparément
    /// laisserait une fenêtre où le dossier est neuf et le contenu ancien.
    public func regarder(_ nouveau: URL) {
        lock.lock()
        defer { lock.unlock() }
        dossier = nouveau
        cachedCorpora = nil
        cachedBooks.removeAll()
    }
}

/// Le lexique, même principe.
public final class DiskGlossaryRepository: GlossaryRepository, @unchecked Sendable {
    private var dossier: URL
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
        if let file: ONTSchema.GlossaryFile = lire("glossary.json") {
            entries = file.entries.map(GlossaryEntry.init)
        } else {
            entries = try socle.entries()
        }
        cachedEntries = entries
        return entries
    }

    public func occurrences(of lemma: String) -> [Occurrence] {
        lock.lock()

        if cachedOccurrences == nil, let file: ONTSchema.OccurrencesFile = lire("occurrences.json") {
            cachedOccurrences = file.byLemma.mapValues { $0.map(Occurrence.init) }
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

    /// Voir `DiskCorpusRepository.regarder(_:)` — le lexique suit le corpus,
    /// sans quoi l'aperçu montrerait des fiches d'un autre texte.
    public func regarder(_ nouveau: URL) {
        lock.lock()
        defer { lock.unlock() }
        dossier = nouveau
        cachedEntries = nil
        cachedOccurrences = nil
    }
}

/// Les fiches des noms propres, lues du disque quand elles y sont.
///
/// ## Le défaut que ça ferme
///
/// `shemot.json` n'était pas distribué : les fiches restaient celles de
/// l'installation pendant que le texte se corrigeait en minutes. Un lecteur qui
/// touchait un nom en or obtenait la fiche d'il y a trois semaines — et **rien
/// du tout** pour un Shem apparu depuis. Le cas était réel : `gavriel`,
/// `moshe`, `sinai` et `eliyahu` sont nommés dans le corpus sans fiche
/// distribuée.
///
/// Relevé par un audit externe le 8 septembre 2026 — A10.
///
/// ## Pourquoi lire, et non reconstruire
///
/// Reconstruire les fiches ou l'index dans l'app demanderait de réimplémenter
/// l'indexation du pipeline dans **trois liseuses**, avec la certitude qu'elles
/// divergeront. Le pipeline est le seul endroit où la forme se décide ; les
/// liseuses la lisent.
public final class DiskShemotRepository: ShemotRepository, @unchecked Sendable {
    private let dossier: URL
    private let socle: any ShemotRepository
    private let lock = NSLock()
    private var cached: [ShemEntry]?

    public init(
        dossier: URL = CorpusUpdater.dossierParDefaut(),
        socle: any ShemotRepository = BundleShemotRepository()
    ) {
        self.dossier = dossier
        self.socle = socle
    }

    public func entries() throws -> [ShemEntry] {
        lock.lock()
        defer { lock.unlock() }

        if let cached { return cached }
        let entries: [ShemEntry]
        if let file: ONTSchema.ShemotFile = lire("shemot.json") {
            entries = file.entries.map(ShemEntry.init)
        } else {
            entries = try socle.entries()
        }
        cached = entries
        return entries
    }

    private func lire<T: Decodable>(_ nom: String) -> T? {
        guard let octets = try? Data(contentsOf: dossier.appendingPathComponent(nom)) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: octets)
    }

    /// Oublie ce qui est en mémoire, après une mise à jour.
    public func oublier() {
        lock.lock()
        defer { lock.unlock() }
        cached = nil
    }
}

/// L'index de recherche, lu du disque quand il y est.
///
/// Même raison que les fiches : un index figé à l'installation ne trouve pas
/// ce qui a été écrit depuis. Et il est le plus gros des fichiers du corpus —
/// six cents kilo-octets —, donc le plus susceptible d'échouer sur un lien
/// mauvais. Le bundle répond en attendant, comme partout ailleurs.
///
/// **La clé publiée est `recherche`, et le fichier local `search.json`.** Le
/// premier est le nom du nœud dans le manifeste, écrit en français comme le
/// reste ; le second est le nom que le pipeline donne au fichier depuis le
/// début. Les confondre ferait chercher un fichier qui n'existe pas, et le
/// bundle répondrait à sa place — sans que rien ne le dise.
public final class DiskSearchIndex: SearchIndex, @unchecked Sendable {
    private let dossier: URL
    private let socle: any SearchIndex
    private let lock = NSLock()
    private var cached: [SearchRecord]?

    public init(
        dossier: URL = CorpusUpdater.dossierParDefaut(),
        socle: any SearchIndex = BundleSearchIndex()
    ) {
        self.dossier = dossier
        self.socle = socle
    }

    public func records() -> [SearchRecord] {
        lock.lock()
        defer { lock.unlock() }

        if let cached { return cached }
        let records: [SearchRecord]
        if let file: ONTSchema.SearchFile = lire("search.json") {
            records = file.records.map(SearchRecord.init)
        } else {
            records = socle.records()
        }
        cached = records
        return records
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
        cached = nil
    }
}

/// La feuille de prononciation, du disque quand elle y est, du bundle sinon.
///
/// Même montage que le glossaire, pour la même raison : le texte se corrige, et
/// une feuille figée à l'installation expliquerait la prononciation d'hier.
public final class DiskPrononciationRepository: PrononciationRepository, @unchecked Sendable {
    private let dossier: URL
    private let bundle: Foundation.Bundle
    private let lock = NSLock()
    private var cachee: FeuilleDePrononciation??

    public init(
        dossier: URL = CorpusUpdater.dossierParDefaut(),
        bundle: Foundation.Bundle = .main
    ) {
        self.dossier = dossier
        self.bundle = bundle
    }

    public func feuille() -> FeuilleDePrononciation? {
        lock.lock()
        defer { lock.unlock() }

        if let cachee { return cachee }
        let dto: ONTSchema.PrononciationFile? =
            lire("prononciation.json")
            ?? (try? BundleLoader.decode("prononciation", bundle: bundle))
        let feuille = dto.map {
            FeuilleDePrononciation(titre: $0.title, blocs: $0.blocks.map(Block.init))
        }
        cachee = feuille
        return feuille
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
        cachee = nil
    }
}
