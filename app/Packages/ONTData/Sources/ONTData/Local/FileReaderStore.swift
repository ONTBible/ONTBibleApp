import Foundation
import ONTKit

/// Ce que le lecteur produit, persisté en JSON dans le conteneur de l'app.
///
/// JSON explicite plutôt que SwiftData, pour une raison précise : la
/// synchronisation visée passe par notre propre backend, pas par CloudKit. Ce
/// fichier *est* déjà le corps de la future requête `PUT /sync` — le jour où
/// le compte existe, il n'y a rien à convertir.
///
/// Un seul type implémente trois ports (surlignages, position, réglages)
/// parce qu'ils partagent le même fichier et la même écriture atomique.
/// Les *consommateurs*, eux, ne dépendent que du port qui les concerne : une
/// vue de lecture déclare `HighlightRepository` et ne voit rien du reste.
public final class FileReaderStore: HighlightRepository, PositionRepository, PreferencesRepository {
    private let url: URL
    private var state: State

    private struct State: Codable {
        var highlights: [Highlight] = []
        var position: ReadingPosition?
        var preferences: ReadingPreferences = .default
    }

    /// Index par verset, pour que le rendu d'un chapitre ne balaie pas la
    /// liste complète à chaque ligne.
    private var byVerse: [String: Highlight] = [:]

    public init(directory: URL = .applicationSupportDirectory, name: String = "lecteur.json") {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appending(path: name)

        state = (try? Data(contentsOf: url))
            .flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
        purgerLesPierresTombales()
        reindex()
    }

    // MARK: - Surlignages

    /// Ce qui se montre. Les pierres tombales restent sur le disque et dans
    /// l'envoi, jamais dans une liste que le lecteur regarde.
    public func all() -> [Highlight] { state.highlights.filter { !$0.deleted } }

    /// Ce qui part au serveur — suppressions comprises.
    public func allForSync() -> [Highlight] { state.highlights }

    public func highlight(chapterId: String, verse: Int) -> Highlight? {
        byVerse[Highlight.key(chapterId: chapterId, verse: verse)]
    }

    public func save(_ highlight: Highlight) {
        if let index = state.highlights.firstIndex(where: { $0.id == highlight.id }) {
            state.highlights[index] = highlight
        } else if let index = state.highlights.firstIndex(where: { $0.key == highlight.key }) {
            state.highlights[index] = highlight
        } else {
            state.highlights.append(highlight)
        }
        byVerse[highlight.key] = highlight
        persist()
    }

    /// Marque, ne détruit pas.
    ///
    /// La ligne reste, avec `deleted` et un horodatage frais : c'est ce qui
    /// permet à la suppression de voyager. Sans elle, l'appareil qui efface
    /// n'a plus rien à envoyer, et le prochain échange ressuscite le
    /// surlignage depuis un autre appareil — ou depuis le serveur lui-même.
    ///
    /// La note part avec : une pierre tombale ne conserve rien de ce qu'elle
    /// remplace, elle dit seulement que ça a existé et que c'est fini.
    public func remove(_ highlight: Highlight) {
        guard let index = state.highlights.firstIndex(where: { $0.id == highlight.id })
            ?? state.highlights.firstIndex(where: { $0.key == highlight.key })
        else { return }

        state.highlights[index].deleted = true
        state.highlights[index].note = nil
        state.highlights[index].updatedAt = Date()
        byVerse[highlight.key] = nil
        persist()
    }

    // MARK: - Position

    public var position: ReadingPosition? { state.position }

    public func remember(_ position: ReadingPosition) {
        // Ce fichier est touché à chaque défilement : ne réécrire que si la
        // position a réellement bougé.
        if state.position?.chapterId == position.chapterId,
           state.position?.verse == position.verse {
            return
        }
        state.position = position
        persist()
    }

    // MARK: - Réglages

    public var preferences: ReadingPreferences {
        get { state.preferences }
        set {
            guard newValue != state.preferences else { return }
            state.preferences = newValue
            persist()
        }
    }

    // MARK: - Persistance

    private func reindex() {
        byVerse = Dictionary(
            state.highlights.filter { !$0.deleted }.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Les pierres tombales ne s'accumulent pas indéfiniment.
    ///
    /// Quatre-vingt-dix jours : bien au-delà du temps qu'un appareil peut
    /// rester hors ligne sans être réinstallé, et assez court pour que le
    /// fichier ne grossisse pas d'une ligne par suppression pendant des
    /// années. Passé ce délai, un appareil qui referait surface avec une vieille
    /// copie pourrait ressusciter un surlignage — c'est le compromis connu de
    /// toute synchronisation par pierres tombales, et personne n'en a trouvé
    /// de meilleur.
    private func purgerLesPierresTombales() {
        let limite = Date().addingTimeInterval(-90 * 24 * 60 * 60)
        let avant = state.highlights.count
        state.highlights.removeAll { $0.deleted && $0.updatedAt < limite }
        if state.highlights.count != avant { persist() }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
