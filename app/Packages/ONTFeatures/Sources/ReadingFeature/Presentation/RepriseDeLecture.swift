import ONTDesignSystem
import ONTKit
import SwiftUI

/// L'unité où le lecteur en était, prête à lire.
///
/// ## Pourquoi cette porte existe
///
/// La liseuse du Mac veut « Reprendre » comme premier onglet de sa barre
/// latérale. Il lui faut donc l'écran de lecture — mais `ChapterView` est
/// **interne** à ce module, et le rendre public exposerait toute sa surface :
/// ses états de sélection, sa barre d'actions, ses feuilles.
///
/// Une porte étroite dit exactement ce qu'on autorise. C'est la même règle que
/// pour les ports d'`ONTKit` : on publie une intention, pas une implémentation.
///
/// ## Quand il n'y a rien à reprendre
///
/// Une installation neuve n'a pas de position. On le dit plutôt que de montrer
/// une page vide — un écran vide sans phrase laisse croire à une panne.
public struct RepriseDeLecture: View {
    @Environment(ReadingModel.self) private var model

    public init() {}

    private var unite: Chapter? {
        guard let position = model.position else { return nil }
        return model.chapter(book: position.bookId, id: position.chapterId)
    }

    public var body: some View {
        if let unite {
            ChapterView(chapter: unite)
        } else {
            ContentUnavailableView {
                Label("Rien à reprendre", systemImage: "bookmark")
            } description: {
                Text("Ouvrez une unité : elle vous attendra ici la prochaine fois.")
                .font(ONTUI.body)
            }
        }
    }
}
