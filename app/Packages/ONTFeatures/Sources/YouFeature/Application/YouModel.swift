import Foundation
import ONTKit
import Observation

/// Le modèle de l'onglet « Vous ».
@MainActor
@Observable
public final class YouModel {
    private let corpus: any CorpusRepository
    private let glossary: any GlossaryRepository

    public init(corpus: any CorpusRepository, glossary: any GlossaryRepository) {
        self.corpus = corpus
        self.glossary = glossary
    }

    public var allBooks: Int { corpus.allBooks().count }
    public var writtenBooks: Int { corpus.writtenBooks().count }
    public var verses: Int { corpus.writtenBooks().reduce(0) { $0 + $1.verseCount } }
    public var glossaryCount: Int { ((try? glossary.entries()) ?? []).count }
}
