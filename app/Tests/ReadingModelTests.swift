import Foundation
import ONTKit
import Testing

@testable import ReadingFeature

/// Le modèle de lecture, éprouvé sur des doublures en mémoire.
///
/// C'est la démonstration que le découpage tient : aucun bundle, aucun
/// fichier, aucun simulateur — juste des protocoles satisfaits par une
/// vingtaine de lignes. Avant le refactoring, ces tests étaient impossibles à
/// écrire.
@MainActor
struct ReadingModelTests {
    // MARK: - Doublures

    final class FakeCorpus: CorpusRepository, @unchecked Sendable {
        func corpora() throws -> [Corpus] { [] }
        func book(_ id: String) throws -> Book {
            throw NSError(domain: "test", code: 0)
        }
    }

    /// Même comportement que le vrai stockage : `remove` marque, il ne détruit
    /// pas. Les tests existants comptent `stored` — ils comptent donc les
    /// pierres tombales, et c'est ce qu'on veut vérifier.
    final class FakeHighlights: HighlightRepository {
        var stored: [String: Highlight] = [:]

        /// Ce qui reste vivant — c'est sur ça que portent les assertions de
        /// comptage des tests de lecture.
        var vivants: [Highlight] { stored.values.filter { !$0.deleted } }

        func all() -> [Highlight] { vivants }
        func allForSync() -> [Highlight] { Array(stored.values) }
        func highlight(chapterId: String, verse: Int) -> Highlight? {
            stored[Highlight.key(chapterId: chapterId, verse: verse)]
                .flatMap { $0.deleted ? nil : $0 }
        }
        func save(_ highlight: Highlight) { stored[highlight.key] = highlight }
        func remove(_ highlight: Highlight) {
            guard var existant = stored[highlight.key] else { return }
            existant.deleted = true
            existant.note = nil
            existant.updatedAt = Date()
            stored[highlight.key] = existant
        }
    }

    final class FakePositions: PositionRepository {
        var position: ReadingPosition?
        func remember(_ position: ReadingPosition) { self.position = position }
    }

    final class FakePreferences: PreferencesRepository {
        var preferences: ReadingPreferences = .default
    }

    private func makeModel() -> (ReadingModel, FakeHighlights, FakePreferences) {
        let highlights = FakeHighlights()
        let preferences = FakePreferences()
        let model = ReadingModel(
            corpus: FakeCorpus(),
            highlights: highlights,
            positions: FakePositions(),
            preferences: preferences
        )
        return (model, highlights, preferences)
    }

    private var chapter: Chapter {
        Chapter(
            id: "bereshit-18", bookId: "bereshit", kind: .chapter, n: 18,
            title: "Bereshit 18", titleNodes: [], subtitle: nil, status: .locked,
            blocks: [], footer: nil, verseCount: 33, lemmas: []
        )
    }

    // MARK: - Surlignage

    @Test("poser une couleur crée le surlignage")
    func createsHighlight() {
        let (model, highlights, _) = makeModel()
        model.toggleHighlight(19, in: chapter, color: .gold)

        #expect(highlights.vivants.count == 1)
        #expect(model.highlight(chapterId: "bereshit-18", verse: 19)?.color == .gold)
    }

    @Test("reposer la même couleur retire le surlignage")
    func togglesOff() {
        let (model, highlights, _) = makeModel()
        model.toggleHighlight(19, in: chapter, color: .gold)
        model.toggleHighlight(19, in: chapter, color: .gold)

        #expect(highlights.vivants.isEmpty, "le même geste doit défaire")
    }

    @Test("poser une autre couleur remplace, sans dédoubler")
    func changesColor() {
        let (model, highlights, _) = makeModel()
        model.toggleHighlight(19, in: chapter, color: .gold)
        model.toggleHighlight(19, in: chapter, color: .sky)

        #expect(highlights.vivants.count == 1)
        #expect(model.highlight(chapterId: "bereshit-18", verse: 19)?.color == .sky)
    }

    @Test("un surlignage porteur d'une note n'est pas retiré par mégarde")
    func keepsNoted() {
        let (model, highlights, _) = makeModel()
        model.setNote("tsedaqah umishpat", verse: 19, in: chapter)
        model.toggleHighlight(19, in: chapter, color: .gold)

        #expect(highlights.vivants.count == 1, "reposer la couleur ne doit pas jeter la note")
        #expect(model.highlight(chapterId: "bereshit-18", verse: 19)?.note != nil)
    }

    @Test("vider une note la retire")
    func clearsNote() {
        let (model, _, _) = makeModel()
        model.setNote("un mot", verse: 19, in: chapter)
        model.setNote("   ", verse: 19, in: chapter)

        #expect(model.highlight(chapterId: "bereshit-18", verse: 19)?.note == nil)
    }

    // MARK: - Sélection de versets

    @Test("une couleur s'applique à toute la sélection")
    func appliesToSelection() {
        let (model, highlights, _) = makeModel()
        model.apply(.gold, to: [19, 20, 21], in: chapter)

        #expect(highlights.vivants.count == 3)
        #expect(model.highlight(chapterId: "bereshit-18", verse: 20)?.color == .gold)
    }

    @Test("reposer la couleur sur une sélection uniforme la retire")
    func togglesOffUniformSelection() {
        let (model, highlights, _) = makeModel()
        model.apply(.gold, to: [19, 20], in: chapter)
        model.apply(.gold, to: [19, 20], in: chapter)

        #expect(highlights.vivants.isEmpty)
    }

    @Test("une sélection mêlée est unifiée, pas dépeinte")
    func unifiesMixedSelection() {
        // Le piège du geste unique appliqué verset par verset : sur trois
        // versets dont un seul est déjà en or, « or » en retirerait un et en
        // peindrait deux. Le lecteur veut trois versets en or.
        let (model, highlights, _) = makeModel()
        model.apply(.gold, to: [19], in: chapter)
        model.apply(.gold, to: [19, 20, 21], in: chapter)

        #expect(highlights.vivants.count == 3)
        #expect([19, 20, 21].allSatisfy {
            model.highlight(chapterId: "bereshit-18", verse: $0)?.color == .gold
        })
    }

    @Test("retirer la couleur d'une sélection épargne les notes")
    func sparesNotesInSelection() {
        let (model, highlights, _) = makeModel()
        model.setNote("tsedaqah umishpat", verse: 19, in: chapter)
        model.apply(.gold, to: [19, 20], in: chapter)
        model.apply(.gold, to: [19, 20], in: chapter)

        #expect(highlights.vivants.count == 1, "le verset noté doit survivre")
        #expect(model.highlight(chapterId: "bereshit-18", verse: 19)?.note != nil)
    }

    @Test("l'effacement explicite emporte tout, note comprise")
    func clearRemovesEverything() {
        let (model, highlights, _) = makeModel()
        model.setNote("un mot", verse: 19, in: chapter)
        model.apply(.sky, to: [20], in: chapter)
        model.clearHighlights([19, 20], in: chapter)

        #expect(highlights.vivants.isEmpty)
    }

    @Test("on sait si une sélection porte déjà quelque chose")
    func detectsHighlightInSelection() {
        let (model, _, _) = makeModel()
        #expect(!model.hasHighlight([19, 20], in: chapter))

        model.apply(.olive, to: [20], in: chapter)
        #expect(model.hasHighlight([19, 20], in: chapter))
    }

    @Test("une sélection vide ne fait rien")
    func emptySelectionIsInert() {
        let (model, highlights, _) = makeModel()
        model.apply(.gold, to: [], in: chapter)

        #expect(highlights.vivants.isEmpty)
    }

    // MARK: - Le renvoi d'une sélection

    @Test("une sélection vide ne renvoie à rien, et ne plante pas")
    func emptyRangeIsSafe() {
        // Régression ONT-IOS-3 : « Fatal error: Index out of range ».
        // Désélectionner le dernier verset fermait l'app — SwiftUI réévalue
        // le corps de la barre sortante avec une sélection déjà vide.
        #expect(VerseRange.label([]).isEmpty)
        #expect(VerseRange.reference([], chapterTitle: "Bereshit 1") == "Bereshit 1")
    }

    @Test("un verset seul donne son numéro")
    func singleVerseRange() {
        #expect(VerseRange.reference([19], chapterTitle: "Bereshit 18") == "Bereshit 18:19")
    }

    @Test("des versets qui se suivent donnent un intervalle")
    func contiguousRange() {
        #expect(VerseRange.label([1, 2, 3]) == "1-3")
    }

    @Test("des versets épars gardent leurs trous")
    func scatteredRange() {
        #expect(VerseRange.label([1, 2, 3, 7, 9, 10]) == "1-3, 7, 9-10")
    }

    // MARK: - Les liens publics

    @Test("le lien public porte le domaine, la langue et le renvoi")
    func webLinkShape() throws {
        let base = try #require(Router.webBase, "ONTWebBaseURL absent de l'Info.plist")
        #expect(base.host == "ontbible.com")

        let lien = try #require(
            Router.webLink(book: "bereshit", chapter: "bereshit-1", verses: "1-3")
        )
        // Le segment de langue épargne une migration le jour d'une édition
        // anglaise ; le paramètre `v` rouvre au bon verset.
        #expect(lien.absoluteString == "https://ontbible.com/fr/lire/bereshit/bereshit-1?v=1-3")
    }

    @Test("un lien sans verset reste valide")
    func webLinkWithoutVerses() throws {
        let lien = try #require(Router.webLink(book: "bereshit", chapter: "bereshit-1"))
        #expect(lien.absoluteString == "https://ontbible.com/fr/lire/bereshit/bereshit-1")
    }

    @Test("un lien public ouvre l'unité au bon verset")
    func webLinkOpens() throws {
        let router = Router()
        let url = try #require(URL(string: "https://ontbible.com/fr/lire/bereshit/bereshit-1?v=12-15"))
        #expect(router.open(url))
        #expect(router.tab == .bible)
        #expect(router.pendingVerse == 12)
        // Et surtout : le passage est désigné, pas seulement atteint.
        #expect(router.pendingSelection == [12, 13, 14, 15])
    }

    @Test("un renvoi se relit dans les deux sens")
    func rangeRoundTrip() {
        // Le format est écrit par la vue et relu par le routeur. S'ils
        // divergent, un lien partagé n'ouvre plus le bon passage — d'où
        // l'aller-retour éprouvé plutôt que chaque sens séparément.
        for versets in [Set([7]), Set([1, 2, 3]), Set([1, 2, 3, 7, 9, 10])] {
            #expect(VerseRange.parse(VerseRange.label(versets)) == versets)
        }
    }

    @Test("un renvoi bricolé ne fait pas échouer le lien")
    func rangeIsForgiving() {
        #expect(VerseRange.parse("3-1") == [1, 2, 3], "les bornes à l'envers se lisent à l'endroit")
        #expect(VerseRange.parse("1,abc,3") == [1, 3], "un morceau illisible est ignoré")
        #expect(VerseRange.parse("0,-4") == [4], "les numéros nuls ou négatifs disparaissent")
        #expect(VerseRange.parse("1-99999999").isEmpty, "un intervalle absurde est refusé")
        #expect(VerseRange.parse("").isEmpty)
    }

    @Test("le premier verset d'un renvoi se lit dans l'URL")
    func firstVerseFromLink() throws {
        // C'est lui qui décide où rouvrir la page : un lien vers 12-15 doit
        // arriver au verset 12, pas en haut du chapitre.
        let url = try #require(URL(string: "https://ontbible.com/fr/lire/bereshit/bereshit-1?v=12-15,20"))
        #expect(Router.firstVerse(in: url) == 12)

        let simple = try #require(URL(string: "https://ontbible.com/fr/lire/bereshit/bereshit-1?v=7"))
        #expect(Router.firstVerse(in: simple) == 7)

        let aucun = try #require(URL(string: "https://ontbible.com/fr/lire/bereshit/bereshit-1"))
        #expect(Router.firstVerse(in: aucun) == nil)
    }

    @Test("un lien d'un autre domaine est refusé")
    func rejectsForeignLink() throws {
        let router = Router()
        let url = try #require(URL(string: "https://ailleurs.test/fr/lire/bereshit/bereshit-1"))
        #expect(!router.open(url))
    }

    // MARK: - Lecture continue

    @Test("toucher un verset en lecture continue le désigne")
    func verseLinkSelects() throws {
        // En prose continue il n'y a plus de ligne par verset : c'est le
        // moteur de texte qui dit lequel a été atteint, par un lien.
        let router = Router()
        let url = try #require(URL(string: "ont://verse/12"))
        #expect(router.open(url))
        #expect(router.tappedVerse?.id == 12)
    }

    @Test("un lien de verset bricolé ne fait rien")
    func malformedVerseLinkIsInert() throws {
        let router = Router()
        #expect(!router.open(try #require(URL(string: "ont://verse/abc"))))
        #expect(!router.open(try #require(URL(string: "ont://verse/"))))
        #expect(router.tappedVerse == nil)
    }

    @Test("le mode continu est un réglage persistant")
    func continuousPersists() {
        let (model, _, preferences) = makeModel()
        #expect(!model.preferences.continuous, "le mode d'étude reste le défaut")
        model.preferences.continuous = true
        #expect(preferences.preferences.continuous)
    }

    @Test("un réglage d'avant le mode continu se relit")
    func decodesBeforeContinuous() throws {
        let ancien = Data(#"{"showGloss":true,"showLevel3":true,"textSize":19,"lineSpacing":0.5,"theme":"parchment","bodyFont":"literata"}"#.utf8)
        let lu = try JSONDecoder().decode(ReadingPreferences.self, from: ancien)
        #expect(lu.continuous == false)
    }

    // MARK: - Réglages

    @Test("changer un réglage le persiste")
    func persistsPreferences() {
        let (model, _, preferences) = makeModel()
        model.preferences.showGloss = false

        #expect(!preferences.preferences.showGloss)
    }
}
