import ONTKit
import SwiftUI

/// Un livre posé **dans la barre latérale** de l'iPad.
///
/// Ce n'est pas un raccourci vers l'onglet Bible : c'est un endroit à part,
/// avec sa propre pile. On peut donc laisser *Bereshit* ouvert au chapitre 12
/// et aller lire ailleurs sans rien perdre — ce qu'une simple poussée dans le
/// chemin de la Bible ne permet pas, puisqu'il n'y en a qu'un.
///
/// La table des matières complète reste dans l'onglet Bible, slots vides
/// compris. Ici, seuls les livres rédigés sont proposés : une barre latérale
/// est une liste d'endroits où aller, et soixante-sept d'entre eux ne mènent
/// nulle part.
public struct BookTab: View {
    private let bookId: String

    public init(bookId: String) {
        self.bookId = bookId
    }

    @State private var path: [Router.Destination] = []

    public var body: some View {
        NavigationStack(path: $path) {
            BookView(bookId: bookId)
                .navigationDestination(for: Router.Destination.self) { destination in
                    switch destination {
                    case .book(let id):
                        BookView(bookId: id)
                    case .chapter(let book, let chapter):
                        ChapterLoader(bookId: book, chapterId: chapter)
                    }
                }
        }
    }
}
