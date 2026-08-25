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
        // On ouvre une Bible pour la lire : la prose suivie est le défaut, et
        // le bloc par verset est le mode qu'on va chercher pour étudier.
        #expect(model.preferences.continuous, "la lecture suivie est le défaut")
        model.preferences.continuous = false
        #expect(!preferences.preferences.continuous)
    }

    @Test("un réglage d'avant le mode continu se relit")
    func decodesBeforeContinuous() throws {
        let ancien = Data(#"{"showGloss":true,"showLevel3":true,"textSize":19,"lineSpacing":0.5,"theme":"parchment","bodyFont":"literata"}"#.utf8)
        let lu = try JSONDecoder().decode(ReadingPreferences.self, from: ancien)
        // Clé absente : on retombe sur le défaut **du jour**, pas sur celui qui
        // avait cours quand ce réglage a été écrit. Un lecteur revenu d'une
        // vieille version reçoit donc la lecture suivie, comme un nouveau.
        #expect(lu.continuous, "une clé absente prend le défaut courant")
    }

    @Test("la remise à zéro épargne le rappel quotidien")
    func resetKeepsDailySchedule() {
        var reglages = ReadingPreferences.default
        reglages.daily = DailyVerseSchedule(enabled: true, hour: 6, minute: 30)
        reglages.textSize = 27
        reglages.theme = .mystique
        reglages.continuous = false

        let remis = reglages.resettingDisplay()

        #expect(remis.textSize == ReadingPreferences.default.textSize)
        #expect(remis.theme == ReadingPreferences.default.theme)
        #expect(remis.continuous == ReadingPreferences.default.continuous)
        // Le rappel a demandé une autorisation système et vit sur son propre
        // écran : le remettre au départ reprogrammerait des notifications que
        // personne n'a demandé de toucher.
        #expect(remis.daily == reglages.daily, "le rappel quotidien traverse la remise à zéro")
        #expect(!reglages.isDisplayDefault)
        #expect(remis.isDisplayDefault)
    }

    // MARK: - Réglages

    @Test("changer un réglage le persiste")
    func persistsPreferences() {
        let (model, _, preferences) = makeModel()
        model.preferences.showGloss = false

        #expect(!preferences.preferences.showGloss)
    }
}

/// Ce que le lecteur doit voir écrit, et savoir où il en est.
///
/// Ces deux épreuves couvrent un défaut qu'aucune des deux ne montre seule :
/// le sélecteur de renvoi disait « Bereshit 2 » et « Toute l'unité » quand le
/// sommaire disait déjà « Chapitre 2 », parce que le calcul était **écrit en
/// dur dans une vue** et n'existait qu'à un seul endroit. Il vit maintenant sur
/// `ChapterStub`, et c'est ce qui est éprouvé ici — pas le rendu.
@MainActor
struct RegistreDesUnitesTests {
    private func stub(n: Int, title: String = "Bereshit 2") -> ChapterStub {
        ChapterStub(
            id: "bereshit-2", n: n, title: title,
            status: .locked, verseCount: 21, reference: "2:4-25"
        )
    }

    @Test("le registre décide du mot, pas de la vue")
    func labelFollowsTheRegister() {
        #expect(stub(n: 2).label(french: true) == "Chapitre 2")
        #expect(stub(n: 2).label(french: false) == "Parashah 2")
    }

    /// Une introduction n'a pas de rang : elle garde son titre. Sans ce cas,
    /// le sommaire annoncerait « Chapitre 0 ».
    @Test("une introduction garde son titre")
    func introKeepsItsTitle() {
        let intro = stub(n: 0, title: "TOLEDOT ADAM VE-CHAVAH")
        #expect(intro.label(french: true) == "TOLEDOT ADAM VE-CHAVAH")
        #expect(intro.label(french: false) == "TOLEDOT ADAM VE-CHAVAH")
    }

    /// Le genre grammatical voyage avec le mot, sinon le point d'appel doit
    /// l'accorder lui-même — et il l'oubliera.
    @Test("le genre suit le mot")
    func genderTravelsWithTheWord() {
        #expect(LibelleDUnite.toutLe(french: true) == "Tout le chapitre")
        #expect(LibelleDUnite.toutLe(french: false) == "Toute la parashah")
    }

    /// **Le pluriel de *parashah* n'est pas français.**
    ///
    /// Il prend la marque hébraïque `-ot`, que le §2.5 du vault fixe. Écrire
    /// « parashahs » franciserait un intraduisible — exactement ce que le
    /// réglage cherche à défaire. C'est le genre de détail qu'un point d'appel
    /// pressé règle avec un `+ "s"`.
    @Test("le pluriel garde la marque hébraïque")
    func pluralKeepsTheHebrewMark() {
        #expect(LibelleDUnite.noms(french: true) == "chapitres")
        #expect(LibelleDUnite.noms(french: false) == "parashiot")
        #expect(LibelleDUnite.nom(french: false) == "parashah")
    }

    /// Le livre **et** le rang, pour le seul écran qui n'a pas d'autre repère.
    @Test("la pastille situe autant qu'elle nomme")
    func thePillSituatesAndNames() {
        #expect(
            LibelleDUnite.situe(livre: "Bereshit", rang: 6, french: true)
                == "Bereshit · Chapitre 6"
        )
        #expect(
            LibelleDUnite.situe(livre: "Bereshit", rang: 6, french: false)
                == "Bereshit · Parashah 6"
        )
    }
}

/// La position mémorisée **prévient** ceux qui la regardent.
///
/// `position` lit `revision` pour s'abonner : c'est ce qui fait qu'`@Observable`
/// la surveille, puisque la valeur vient d'un dépôt qu'il ne voit pas.
/// `remember` écrivait sans y toucher — donc sans le dire.
///
/// Ça ne se voyait pas : les deux vues qui lisent la position sont construites
/// à neuf quand on les ouvre, et lisaient la bonne valeur **par accident**. Le
/// sélecteur de renvoi s'appuie désormais dessus pour marquer le verset
/// courant.
@MainActor
struct PositionObservableTests {
    @Test("mémoriser une position fait bouger la révision")
    func rememberingBumpsTheRevision() {
        let model = ReadingModel(
            corpus: ReadingModelTests.FakeCorpus(),
            highlights: ReadingModelTests.FakeHighlights(),
            positions: ReadingModelTests.FakePositions(),
            preferences: ReadingModelTests.FakePreferences()
        )
        let avant = model.revision
        model.remember(
            chapter: Chapter(
                id: "bereshit-18", bookId: "bereshit", kind: .chapter, n: 18,
                title: "Bereshit 18", titleNodes: [], subtitle: nil, status: .locked,
                blocks: [], footer: nil, verseCount: 33, lemmas: []
            ),
            verse: 12
        )
        #expect(model.revision > avant, "sans ça, une vue à l'écran garde l'ancienne position")
        #expect(model.position?.verse == 12)
    }
}
