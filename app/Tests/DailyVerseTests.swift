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

/// Le vivier du widget, qui est une **copie** et non un partage.
///
/// ## Pourquoi cette épreuve regarde le disque et non le bundle
///
/// `DailyVerseTests` ci-dessus compare le choix de l'app à `daily.pool()` —
/// le même vivier des deux côtés. Elle mesure donc l'accord de l'app **avec
/// elle-même**, et elle est restée verte pendant les sept semaines où le
/// widget montrait un autre verset.
///
/// ==Un contrôle qui interroge une seule des deux copies ne peut pas voir
/// qu'elles divergent.== Il faut aller lire les deux fichiers là où ils
/// vivent, et c'est pourquoi celle-ci passe par `#filePath`.
///
/// ## Ce qui s'était passé, et pourquoi ça ne se voyait pas
///
/// Une extension ne lit pas le bundle de l'app qui la contient : `project.yml`
/// recopie `daily.json` dans `Widget/Resources/`. **Mais rien ne faisait la
/// recopie.** Mesuré le 2 octobre 2026 — le fichier du widget datait du
/// 12 août à 01:47, jour de sa création, et portait 251 versets contre 254.
///
/// Et le défaut n'est pas « le widget a trois versets de retard ». C'est qu'il
/// montre **un autre verset** : `DailySelection` avance d'un pas premier avec
/// la **taille** du vivier, donc trois entrées de plus déplacent l'indice. Les
/// deux calculaient juste, sur deux viviers différents.
///
/// L'auteur l'a vu comme une inversion — « 4:6 dans l'app, 6:4 dans le
/// widget ». ==Deux versets tirés au hasard du même livre se ressemblent assez
/// pour qu'on lise une permutation de chiffres là où il y a deux textes
/// différents.==
struct VivierDuWidgetTests {
    private static func fichier(_ relatif: String) throws -> Data {
        let racine = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // app/
        return try Data(contentsOf: racine.appending(path: relatif))
    }

    /// Comparer les **octets**, et non le nombre d'entrées.
    ///
    /// Compter les versets laisserait passer un texte corrigé ou un renvoi
    /// réécrit — or le widget affiche `r` tel quel, et l'app compose le sien
    /// depuis le corpus. Deux viviers de même taille aux contenus différents
    /// donneraient le même indice et deux textes distincts.
    @Test("le vivier du widget est l'exact miroir de celui de l'app")
    func lesDeuxViviersConcordent() throws {
        let app = try Self.fichier("Resources/data/daily.json")
        let widget = try Self.fichier("Widget/Resources/daily.json")
        #expect(
            app == widget,
            """
            `Widget/Resources/daily.json` a divergé de celui de l'app \
            (\(app.count) octets contre \(widget.count)). \
            Le widget montrera un autre verset que la carte du Qahal : \
            la sélection dépend de la taille du vivier. \
            `scripts/corpus.sh` fait la copie — la relancer.
            """
        )
    }

    /// Et la conséquence, dite dans les termes du lecteur.
    ///
    /// L'épreuve ci-dessus suffit à barrer la régression ; celle-ci dit
    /// **pourquoi elle compte**, en mesurant ce que le lecteur verrait. Elle
    /// rougirait sur le jeu du 12 août avec sept jours d'écarts consécutifs.
    @Test("app et widget tombent sur le même verset, sept jours d'affilée")
    func lesDeuxTombentSurLeMemeVerset() throws {
        // Décodé par le **schéma engendré**, comme le fait
        // `BundleDailyVerseRepository` : écrire ici une structure de test
        // parallèle en ferait une seconde définition du format, qui divergerait
        // le jour où le pipeline change le fichier.
        let lire = { (chemin: String) throws -> [DailyVerse] in
            try JSONDecoder()
                .decode(ONTSchema.DailyFile.self, from: Self.fichier(chemin))
                // L'adaptateur `DailyVerse.init(_ dto:)` d'ONTData est interne
                // à son module : on repasse par l'initialiseur public.
                .verses.map { DailyVerse(b: $0.b, c: $0.c, n: $0.n, r: $0.r, t: $0.t) }
        }
        let app = try lire("Resources/data/daily.json")
        let widget = try lire("Widget/Resources/daily.json")

        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = TimeZone(identifier: "Europe/Paris")!
        let depart = calendrier.date(from: DateComponents(year: 2026, month: 10, day: 2))!

        for offset in 0..<7 {
            let jour = calendrier.date(byAdding: .day, value: offset, to: depart)!
            let a = try #require(DailySelection.verse(for: jour, in: app, calendar: calendrier))
            let w = try #require(DailySelection.verse(for: jour, in: widget, calendar: calendrier))
            let ecart: Comment = "jour \(offset) : l'app dit \(a.reference), le widget \(w.reference)"
            #expect(a.reference == w.reference, ecart)
        }
    }
}
