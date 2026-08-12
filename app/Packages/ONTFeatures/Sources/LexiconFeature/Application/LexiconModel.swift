import Foundation
import ONTKit
import Observation

/// Le modèle du lexique.
///
/// Ne dépend que de `GlossaryRepository` : la feature n'a aucune raison de
/// pouvoir lire le corpus, et ne le peut donc pas.
@MainActor
@Observable
public final class LexiconModel {
    private let glossary: any GlossaryRepository

    public private(set) var entries: [GlossaryEntry] = []
    private var byLemma: [String: GlossaryEntry] = [:]

    public init(glossary: any GlossaryRepository) {
        self.glossary = glossary
        load()
    }

    private func load() {
        entries = (try? glossary.entries()) ?? []
        byLemma = Dictionary(entries.map { ($0.lemma, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func entry(_ lemma: String) -> GlossaryEntry? { byLemma[lemma] }

    /// Les passages où un intraduisible paraît.
    ///
    /// `bodyOnly` répond à « où ce mot est dans le texte », par opposition à
    /// « où on l'explique » — deux questions distinctes (§2.1), et la fiche
    /// doit pouvoir poser l'une sans l'autre.
    public func occurrences(_ lemma: String, bodyOnly: Bool) -> [Occurrence] {
        let all = glossary.occurrences(of: lemma)
        return bodyOnly ? all.filter { $0.level == .body } : all
    }

    /// Le filtre du catalogue.
    public enum Scope: String, CaseIterable, Sendable {
        case tagged = "Intraduisibles"
        case fixed = "Vocabulaire fixé"
        case all = "Tout"
    }

    public func filtered(scope: Scope, search: String) -> [GlossaryEntry] {
        let pool = switch scope {
        case .tagged: entries.filter(\.tagged)
        case .fixed: entries.filter { !$0.tagged }
        case .all: entries
        }

        guard !search.isEmpty else { return pool }
        let needle = search.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: .current
        )

        return pool.filter { entry in
            [entry.title, entry.lemma, entry.rendering ?? "", entry.hebrew ?? "",
             entry.forms.joined(separator: " ")]
                .joined(separator: " ")
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .contains(needle)
        }
    }
}
