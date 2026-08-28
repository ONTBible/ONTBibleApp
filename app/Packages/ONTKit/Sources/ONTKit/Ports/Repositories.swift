import Foundation

/// Les ports — ce que le domaine attend du monde extérieur.
///
/// Un protocole par responsabilité, et non un gros objet qui saurait tout
/// faire. C'est ce qui permet à une vue de déclarer exactement ce dont elle a
/// besoin, et à un test de fournir une doublure de trois lignes plutôt qu'un
/// bundle complet.

// MARK: - Corpus

/// L'accès au texte.
public protocol CorpusRepository: Sendable {
    /// L'arborescence des 70 slots — assez légère pour le lancement.
    func corpora() throws -> [Corpus]
    /// Le contenu complet d'un livre, chargé à la demande.
    func book(_ id: String) throws -> Book
}

extension CorpusRepository {
    /// Tous les livres, dans l'ordre canonique des slots.
    public func allBooks() -> [BookOutline] {
        ((try? corpora()) ?? []).flatMap { corpus in
            corpus.modes.sorted { $0.order < $1.order }.flatMap(\.books)
        }
    }

    /// Les seuls livres qui portent du texte aujourd'hui.
    public func writtenBooks() -> [BookOutline] {
        allBooks().filter { !$0.empty }
    }

    /// Une unité précise, introduction comprise.
    public func chapter(book bookId: String, id chapterId: String) -> Chapter? {
        guard let book = try? book(bookId) else { return nil }
        if book.intro?.id == chapterId { return book.intro }
        return book.chapters.first { $0.id == chapterId }
    }
}

// MARK: - Lexique

/// L'accès au glossaire des intraduisibles.
public protocol GlossaryRepository: Sendable {
    func entries() throws -> [GlossaryEntry]
    /// Les passages où un lemme paraît.
    func occurrences(of lemma: String) -> [Occurrence]
}

// MARK: - Recherche

/// L'index de recherche.
public protocol SearchIndex: Sendable {
    func records() -> [SearchRecord]
}

// MARK: - Ce que le lecteur produit

/// Les surlignages et les notes.
public protocol HighlightRepository: AnyObject {
    /// Ce qui se **montre** — les pierres tombales en sont exclues.
    func all() -> [Highlight]
    /// Ce qui se **synchronise** — pierres tombales comprises.
    ///
    /// Deux méthodes et non une, parce que les deux besoins sont opposés : une
    /// liste d'annotations ne doit pas afficher ce qui est supprimé, et un
    /// envoi qui omettrait les suppressions les perdrait.
    func allForSync() -> [Highlight]
    func highlight(chapterId: String, verse: Int) -> Highlight?
    func save(_ highlight: Highlight)
    func remove(_ highlight: Highlight)
}

/// La position de lecture.
public protocol PositionRepository: AnyObject {
    var position: ReadingPosition? { get }
    func remember(_ position: ReadingPosition)
}

/// Les réglages de lecture.
public protocol PreferencesRepository: AnyObject {
    var preferences: ReadingPreferences { get set }
}

/// Le vivier du verset du jour.
///
/// Un port à part et non une méthode de `CorpusRepository` : le widget n'a
/// besoin que de celui-ci, et lui donner accès au corpus entier l'obligerait à
/// charger un arbre de 750 Ko pour afficher trois lignes.
public protocol DailyVerseRepository: Sendable {
    func pool() -> [DailyVerse]
}

/// Le profil du lecteur.
///
/// Un port à part et non un champ des réglages : le profil se **supprime**
/// avec le compte, là où les réglages de lecture survivent à une
/// déconnexion. Les mêmes données dans le même dépôt finiraient par partir
/// ensemble, ou par rester ensemble — et l'une des deux serait fausse.
public protocol ProfilRepository: AnyObject {
    var profil: Profil { get set }
    /// Écrit le portrait et rend le nom du fichier.
    func enregistrerLePortrait(_ donnees: Data) throws -> String
    /// Les octets du portrait, ou `nil` s'il n'y en a pas.
    func portrait() -> Data?
    /// Tout effacer — appelé par l'effacement du compte.
    func oublier()
}
