import Foundation
import ONTKit
import Observation

/// Le modèle de la feature de lecture.
///
/// Il orchestre des **protocoles**, jamais des types concrets : c'est ce qui
/// permet à un test de le construire avec des doublures en mémoire, sans
/// bundle ni simulateur. L'app, elle, lui passe les dépôts qui lisent le
/// bundle et le disque.
@MainActor
@Observable
public final class ReadingModel {
    private let corpus: any CorpusRepository
    private let highlights: any HighlightRepository
    private let positions: any PositionRepository
    private let preferencesStore: any PreferencesRepository

    /// Les réglages de lecture, observables.
    ///
    /// Doublés en mémoire parce que SwiftUI doit voir le changement : le dépôt
    /// persiste, cette propriété notifie.
    public var preferences: ReadingPreferences {
        didSet { preferencesStore.preferences = preferences }
    }

    /// Incrémenté à chaque changement de surlignage, pour que les vues qui en
    /// dépendent se rafraîchissent — les dépôts ne sont pas observables, et
    /// c'est très bien ainsi : ils appartiennent au domaine.
    public private(set) var revision = 0

    public init(
        corpus: any CorpusRepository,
        highlights: any HighlightRepository,
        positions: any PositionRepository,
        preferences: any PreferencesRepository
    ) {
        self.corpus = corpus
        self.highlights = highlights
        self.positions = positions
        self.preferencesStore = preferences
        self.preferences = preferences.preferences
    }

    // MARK: - Corpus

    public var corpora: [Corpus] { (try? corpus.corpora()) ?? [] }
    public var allBooks: [BookOutline] { corpus.allBooks() }
    public var writtenBooks: [BookOutline] { corpus.writtenBooks() }

    public func outline(_ bookId: String) -> BookOutline? {
        allBooks.first { $0.id == bookId }
    }

    public func book(_ bookId: String) -> Book? {
        try? corpus.book(bookId)
    }

    public func chapter(book bookId: String, id chapterId: String) -> Chapter? {
        corpus.chapter(book: bookId, id: chapterId)
    }

    // MARK: - Surlignage

    public func highlight(chapterId: String, verse: Int) -> Highlight? {
        _ = revision
        return highlights.highlight(chapterId: chapterId, verse: verse)
    }

    /// Pose, change ou retire un surlignage.
    ///
    /// Reposer la même couleur le retire — c'est le geste qu'on attend, et ça
    /// évite un bouton « effacer » de plus dans le menu.
    public func toggleHighlight(_ verse: Int, in chapter: Chapter, color: HighlightColor) {
        if let existing = highlights.highlight(chapterId: chapter.id, verse: verse) {
            if existing.color == color, existing.note == nil {
                highlights.remove(existing)
            } else {
                var updated = existing
                updated.color = color
                updated.updatedAt = Date()
                highlights.save(updated)
            }
        } else {
            highlights.save(
                Highlight(
                    bookId: chapter.bookId,
                    chapterId: chapter.id,
                    verse: verse,
                    color: color
                )
            )
        }
        revision += 1
    }

    /// Applique une couleur à une sélection de versets.
    ///
    /// La règle du geste unique vaut encore, mais à l'échelle de la sélection :
    /// si **tous** les versets portent déjà cette couleur, on la retire ;
    /// sinon on l'applique à tous. Sans ça, choisir « or » sur trois versets
    /// dont un seul est déjà en or en retirerait un et en peindrait deux — un
    /// résultat que personne n'a demandé.
    public func apply(
        _ color: HighlightColor,
        to verses: Set<Int>,
        in chapter: Chapter
    ) {
        guard !verses.isEmpty else { return }

        let uniform = verses.allSatisfy {
            highlights.highlight(chapterId: chapter.id, verse: $0)?.color == color
        }

        for verse in verses.sorted() {
            let existing = highlights.highlight(chapterId: chapter.id, verse: verse)
            if uniform {
                // Une note vaut plus qu'une couleur : on dépose le surlignage,
                // on ne détruit pas ce que le lecteur a écrit.
                guard let existing else { continue }
                if existing.note == nil {
                    highlights.remove(existing)
                }
            } else if var existing {
                existing.color = color
                existing.updatedAt = Date()
                highlights.save(existing)
            } else {
                highlights.save(
                    Highlight(
                        bookId: chapter.bookId,
                        chapterId: chapter.id,
                        verse: verse,
                        color: color
                    )
                )
            }
        }
        revision += 1
    }

    /// Retire le surlignage — et la note avec — d'une sélection.
    public func clearHighlights(_ verses: Set<Int>, in chapter: Chapter) {
        for verse in verses {
            if let existing = highlights.highlight(chapterId: chapter.id, verse: verse) {
                highlights.remove(existing)
            }
        }
        revision += 1
    }

    /// Vrai si au moins un verset de la sélection porte un surlignage.
    public func hasHighlight(_ verses: Set<Int>, in chapter: Chapter) -> Bool {
        _ = revision
        return verses.contains { highlights.highlight(chapterId: chapter.id, verse: $0) != nil }
    }

    public func setNote(_ text: String, verse: Int, in chapter: Chapter) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if var existing = highlights.highlight(chapterId: chapter.id, verse: verse) {
            existing.note = trimmed.isEmpty ? nil : trimmed
            existing.updatedAt = Date()
            highlights.save(existing)
        } else if !trimmed.isEmpty {
            var new = Highlight(
                bookId: chapter.bookId,
                chapterId: chapter.id,
                verse: verse,
                color: .gold
            )
            new.note = trimmed
            highlights.save(new)
        }
        revision += 1
    }

    public func remove(_ highlight: Highlight) {
        highlights.remove(highlight)
        revision += 1
    }

    public var allHighlights: [Highlight] {
        _ = revision
        return highlights.all().sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Reprise

    public var position: ReadingPosition? {
        _ = revision
        return positions.position
    }

    public func remember(chapter: Chapter, verse: Int) {
        positions.remember(
            ReadingPosition(
                bookId: chapter.bookId,
                chapterId: chapter.id,
                chapterTitle: chapter.title,
                verse: verse
            )
        )
    }
}
