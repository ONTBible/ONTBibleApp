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
        reindex()
    }

    // MARK: - Surlignages

    public func all() -> [Highlight] { state.highlights }

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

    public func remove(_ highlight: Highlight) {
        state.highlights.removeAll { $0.id == highlight.id }
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
            state.highlights.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
