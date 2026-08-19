import Foundation
import ONTKit
import Testing

@testable import LexiconFeature
@testable import ReadingFeature

/// Un livre publié pendant que l'app est ouverte doit se voir tout de suite.
///
/// `CorpusUpdater` écrit le fichier neuf sur le disque et le dépôt vide son
/// cache. Mais vider un cache ne change aucune propriété observée : sans un
/// signal explicite, les vues gardent la liste d'avant et le livre n'apparaît
/// qu'au lancement suivant. Ces tests portent sur ce signal.
@MainActor
struct CorpusVivantTests {
    /// Un dépôt qui change d'avis, comme le disque après un téléchargement.
    final class CorpusMouvant: CorpusRepository, @unchecked Sendable {
        var livres: [BookOutline] = []

        func corpora() throws -> [Corpus] {
            [Corpus(id: "kenesset", title: "Kenesset", order: 1,
                    modes: [Mode(id: "torah", title: "Torah", order: 1, books: livres)])]
        }

        func book(_ id: String) throws -> Book {
            throw NSError(domain: "test", code: 0)
        }
    }

    final class Positions: PositionRepository {
        var position: ReadingPosition?
        func remember(_ position: ReadingPosition) { self.position = position }
    }

    final class Preferences: PreferencesRepository {
        var preferences: ReadingPreferences = .default
    }

    final class Highlights: HighlightRepository {
        func all() -> [Highlight] { [] }
        func allForSync() -> [Highlight] { [] }
        func highlight(chapterId: String, verse: Int) -> Highlight? { nil }
        func save(_ highlight: Highlight) {}
        func remove(_ highlight: Highlight) {}
    }

    private func livre(_ id: String) -> BookOutline {
        BookOutline(
            id: id, slot: 1, title: id, french: id, hebrew: nil, groupId: nil,
            empty: false, intro: nil, chapters: []
        )
    }

    /// Le drapeau du réveil, dans une boîte.
    ///
    /// `onChange` est `@Sendable` — la concurrence stricte refuse d'y muter une
    /// variable locale, et elle a raison : l'observation peut appeler de
    /// n'importe où. Une référence partagée dit ce qu'on veut vraiment.
    final class Reveil: @unchecked Sendable {
        var sonne = false
    }

    private func modele(_ corpus: CorpusMouvant) -> ReadingModel {
        ReadingModel(
            corpus: corpus, highlights: Highlights(),
            positions: Positions(), preferences: Preferences()
        )
    }

    @Test("le livre neuf est là dès qu'on l'annonce")
    func leLivreNeufApparait() {
        let corpus = CorpusMouvant()
        let model = modele(corpus)
        #expect(model.corpora.first?.modes.first?.books.isEmpty == true)

        corpus.livres = [livre("bereshit")]
        model.corpusChanged()

        #expect(model.corpora.first?.modes.first?.books.count == 1)
    }

    /// Le cœur du correctif : une vue qui a lu `corpora` doit être **réveillée**.
    ///
    /// Sans le `_ = corpusRevision` dans l'accesseur, rien ici ne se déclenche —
    /// la liste serait pourtant juste à la relecture suivante, et le test
    /// précédent passerait quand même. C'est cette différence qu'on éprouve.
    @Test("une vue qui a lu le corpus est réveillée")
    func laVueEstReveillee() {
        let corpus = CorpusMouvant()
        let model = modele(corpus)

        let reveil = Reveil()
        withObservationTracking {
            _ = model.corpora
        } onChange: {
            reveil.sonne = true
        }

        model.corpusChanged()
        #expect(reveil.sonne, "la vue serait restée sur la liste d'avant")
    }

    @Test("la table d'un livre suit aussi")
    func laTableSuit() {
        let corpus = CorpusMouvant()
        let model = modele(corpus)

        let reveil = Reveil()
        withObservationTracking {
            _ = model.writtenBooks
        } onChange: {
            reveil.sonne = true
        }

        model.corpusChanged()
        #expect(reveil.sonne)
    }

    // MARK: - Le lexique

    final class GlossaireMouvant: GlossaryRepository, @unchecked Sendable {
        var entrees: [GlossaryEntry] = []
        func entries() throws -> [GlossaryEntry] { entrees }
        func occurrences(of lemma: String) -> [Occurrence] { [] }
    }

    @Test("une entrée corrigée se voit sans relancer")
    func leLexiqueSuit() {
        let glossaire = GlossaireMouvant()
        let model = LexiconModel(glossary: glossaire)
        #expect(model.entries.isEmpty)

        glossaire.entrees = [
            GlossaryEntry(
                lemma: "bara", title: "bara", tagged: false, forms: [],
                hebrew: "ברא", rendering: "orchestrer", definition: nil,
                taggingNote: nil, firstUse: nil, sourceSection: nil,
                count: 0, bodyCount: 0, glossCount: 0
            )
        ]
        model.glossaryChanged()

        #expect(model.entries.count == 1)
        #expect(model.entry("bara")?.rendering == "orchestrer")
    }
}
