import Foundation
import ONTKit
import Observation

/// Le modèle du Qahal.
@MainActor
@Observable
public final class QahalModel {
    private let corpus: any CorpusRepository
    private let daily: any DailyVerseRepository

    public private(set) var verseOfTheDay: (chapter: Chapter, verse: Verse)?

    public init(corpus: any CorpusRepository, daily: any DailyVerseRepository) {
        self.corpus = corpus
        self.daily = daily
    }

    /// Le verset du jour.
    ///
    /// ## Une seule source de vérité
    ///
    /// Le choix appartient à `DailySelection`, sur le vivier `daily.json` que
    /// produit le pipeline. Cette vue, le widget de l'écran d'accueil et la
    /// notification quotidienne interrogent tous les trois la **même**
    /// fonction sur le **même** vivier — c'est la seule façon qu'ils
    /// s'accordent, puisqu'ils vivent dans des processus différents et n'ont
    /// aucun moyen de se parler.
    ///
    /// Ce modèle tirait autrefois son propre verset, avec sa propre fenêtre de
    /// longueur et son propre modulo. Résultat : la carte du Qahal et le
    /// widget affichaient deux versets différents le même jour.
    ///
    /// Ce qui reste ici, c'est la **résolution** : le vivier est plat, adapté
    /// à un widget qui n'a ni le temps ni la mémoire de charger un livre. La
    /// carte du Qahal, elle, dispose du corpus et peut rendre le verset avec
    /// ses intraduisibles en or. Même verset, rendu plus riche.
    public func pick(on date: Date = Date()) {
        guard let choisi = DailySelection.verse(for: date, in: daily.pool()) else { return }
        guard
            let chapter = corpus.chapter(book: choisi.bookId, id: choisi.chapterId),
            let verse = chapter.verses.first(where: { $0.n == choisi.verse })
        else {
            // Le vivier nomme un verset que le corpus ne contient plus : le
            // pipeline et le bundle ont divergé. On préfère ne rien afficher
            // qu'afficher autre chose que ce qu'annonce le widget.
            verseOfTheDay = nil
            return
        }
        verseOfTheDay = (chapter, verse)
    }
}
