import Foundation
import ONTKit
import Observation

/// Le modèle de la recherche.
@MainActor
@Observable
public final class SearchModel {
    private let index: any SearchIndex
    private let glossary: any GlossaryRepository
    private let corpus: any CorpusRepository

    public var query = "" { didSet { run() } }
    public var scope = SearchScope.body { didSet { run() } }
    public private(set) var hits: [SearchHit] = []

    /// Les lemmes du glossaire — pour que taper « chesed » trouve aussi les
    /// passages où le terme ne paraît qu'en hébreu. Calculés une fois : le
    /// macro `@Observable` n'admet pas `lazy`.
    @ObservationIgnored private let lemmas: Set<String>

    public init(
        index: any SearchIndex,
        glossary: any GlossaryRepository,
        corpus: any CorpusRepository
    ) {
        self.index = index
        self.glossary = glossary
        self.corpus = corpus
        self.lemmas = Set(((try? glossary.entries()) ?? []).map(\.lemma))
    }

    private func run() {
        hits = SearchEngine.search(query, in: index.records(), scope: scope, lemmas: lemmas)
    }

    /// Le titre d'un livre, pour l'affichage d'un résultat.
    public func bookTitle(_ bookId: String) -> String {
        corpus.allBooks().first { $0.id == bookId }?.title ?? bookId
    }
}
