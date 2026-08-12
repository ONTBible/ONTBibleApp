import Foundation
import ONTData
import ONTKit
import QahalFeature
import Testing

/// Le verset du jour.
struct DailyVerseTests {
    private var pool: [DailyVerse] {
        BundleDailyVerseRepository(bundle: .main).pool()
    }

    private let calendrier: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }()

    private func jour(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendrier.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    @Test("le vivier est embarqué et non vide")
    func poolIsBundled() {
        #expect(pool.count > 100, "\(pool.count) versets — le vivier n'est pas dans le bundle")
        #expect(pool.allSatisfy { !$0.text.isEmpty && !$0.reference.isEmpty })
    }

    @Test("le même jour donne toujours le même verset")
    func stableWithinADay() {
        // C'est ce qui permet à l'app, au widget et à la notification de
        // tomber d'accord sans jamais se parler. `Hasher` de Swift ne
        // conviendrait pas : il est salé au démarrage du processus.
        let matin = calendrier.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 6))!
        let soir = calendrier.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 23))!

        let a = DailySelection.verse(for: matin, in: pool, calendar: calendrier)
        let b = DailySelection.verse(for: soir, in: pool, calendar: calendrier)
        #expect(a == b)
    }

    @Test("deux jours voisins ne donnent pas deux versets voisins")
    func consecutiveDaysScatter() {
        // Sinon on lirait le corpus dans l'ordre, un verset par jour : ce
        // serait un plan de lecture, pas un verset du jour.
        let indices = (0..<10).map {
            DailySelection.index(
                for: jour(2026, 8, 12 + $0), count: 1000, calendar: calendrier
            )
        }
        let ecarts = zip(indices, indices.dropFirst()).map { abs($1 - $0) }
        #expect(ecarts.allSatisfy { $0 > 5 }, "indices trop proches : \(indices)")
    }

    @Test("le vivier entier défile avant qu'un verset revienne")
    func poolIsExhaustedBeforeRepeating() {
        // La propriété que le tirage au hasard ne donnait pas : un pas premier
        // avec la taille du vivier engendre le groupe entier.
        let taille = 251
        let indices = (0..<taille).map {
            DailySelection.index(for: jour(2026, 1, 1 + $0), count: taille, calendar: calendrier)
        }
        #expect(Set(indices).count == taille, "le cycle ne couvre pas tout le vivier")
    }

    @Test("un mois ne se répète pas")
    func aMonthDoesNotRepeat() {
        let verses = (0..<30).compactMap {
            DailySelection.verse(for: jour(2026, 8, 1 + $0), in: pool, calendar: calendrier)?.id
        }
        #expect(Set(verses).count == verses.count, "un verset revient dans le mois")
    }

    @Test("un vivier vide ne fait pas planter")
    func emptyPoolIsSafe() {
        #expect(DailySelection.verse(for: Date(), in: []) == nil)
        #expect(DailySelection.index(for: Date(), count: 0) == 0)
    }

    @Test("l'horaire du rappel est borné")
    func scheduleIsClamped() {
        #expect(DailyVerseSchedule(hour: 30, minute: 99).hour == 23)
        #expect(DailyVerseSchedule(hour: 30, minute: 99).minute == 59)
        #expect(DailyVerseSchedule(hour: -5, minute: -1).hour == 0)
    }

    @Test("un réglage d'avant le rappel se relit")
    func decodesLegacyPreferences() throws {
        let ancien = Data(#"{"showGloss":true,"showLevel3":true,"textSize":19,"lineSpacing":0.5,"theme":"parchment","bodyFont":"literata"}"#.utf8)
        let lu = try JSONDecoder().decode(ReadingPreferences.self, from: ancien)
        #expect(lu.daily.enabled == false)
        #expect(lu.daily.hour == 7)
    }
}

/// L'accord entre les endroits qui affichent le verset du jour.
///
/// Ils vivent dans des processus différents — l'app, le widget, la
/// notification — et n'ont aucun moyen de se parler. Leur seul point commun
/// est ce vivier et cette fonction. S'ils divergent, personne ne le voit avant
/// qu'un lecteur compare son écran d'accueil et son onglet Qahal.
@MainActor
struct DailySourceOfTruthTests {
    @Test("le vivier ne contient que des unités verrouillées")
    func poolIsLockedOnly() throws {
        // §12 : un brouillon ne fait pas référence, et n'a rien à faire sur un
        // écran d'accueil. La règle est appliquée par le pipeline, pas par
        // chacun des affichages — sinon elle finit appliquée à deux endroits
        // sur trois.
        let corpus = BundleCorpusRepository()
        let pool = BundleDailyVerseRepository().pool()
        #expect(!pool.isEmpty)

        for candidat in pool {
            let chapitre = try #require(
                corpus.chapter(book: candidat.bookId, id: candidat.chapterId),
                "\(candidat.reference) absent du corpus"
            )
            #expect(chapitre.status == .locked, "\(candidat.reference) est un brouillon")
        }
    }

    @Test("chaque verset du vivier existe dans le corpus")
    func poolResolvesAgainstCorpus() throws {
        // Le vivier est plat, le corpus est un arbre : deux fichiers produits
        // par le même pipeline. S'ils divergent, la carte du Qahal n'affiche
        // rien pendant que le widget affiche quelque chose.
        let corpus = BundleCorpusRepository()
        for candidat in BundleDailyVerseRepository().pool() {
            let chapitre = try #require(corpus.chapter(book: candidat.bookId, id: candidat.chapterId))
            #expect(
                chapitre.verses.contains { $0.n == candidat.verse },
                "\(candidat.reference) introuvable dans son unité"
            )
        }
    }

    @Test("le Qahal montre le verset que le widget montrerait")
    func qahalMatchesWidget() throws {
        // Le test qui compte. Avant, le Qahal avait son propre vivier
        // (110–300, verrouillées) et son propre tirage (`jours % n`), le
        // widget en avait d'autres (70–240, brassage) : deux versets
        // différents le même jour.
        let corpus = BundleCorpusRepository()
        let daily = BundleDailyVerseRepository()
        let model = QahalModel(corpus: corpus, daily: daily)

        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = TimeZone(identifier: "Europe/Paris")!

        for offset in 0..<20 {
            let jour = calendrier.date(
                from: DateComponents(year: 2026, month: 8, day: 12 + offset, hour: 9)
            )!
            model.pick(on: jour)

            let attendu = try #require(DailySelection.verse(for: jour, in: daily.pool()))
            let obtenu = try #require(model.verseOfTheDay, "rien au \(offset)ᵉ jour")
            #expect(obtenu.chapter.id == attendu.chapterId)
            #expect(obtenu.verse.n == attendu.verse)
        }
    }
}
