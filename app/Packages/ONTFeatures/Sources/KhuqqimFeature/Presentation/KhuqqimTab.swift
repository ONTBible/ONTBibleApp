import ONTDesignSystem
import ONTKit
import SwiftUI

/// L'onglet **Khuqqim** — חֻקִּים, ce qui est *gravé*.
///
/// ## Où il en est
///
/// C'est un squelette : la place dans la barre, la pile de navigation, le
/// grand titre. **Aucun contenu, et l'écran le dit.** Ce qu'est une entrée,
/// d'où elle vient et ce qu'on en lit ne sont pas encore arrêtés — les poser
/// en devinant reviendrait à figer une forme avant de savoir ce qu'elle porte.
///
/// ## Pourquoi un état vide qui s'annonce, plutôt qu'un écran blanc
///
/// Un écran vide sans un mot se lit comme une panne. Celui-ci dit ce qu'il
/// attend, ce qui est vrai — et il disparaîtra dès que la première entrée
/// arrivera.
public struct KhuqqimTab: View {
    @Environment(\.ontTheme) private var theme
    private var spacing = ONTSpacing()

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: spacing.m) {
                    Text("Khuqqim")
                        .font(.custom(ONTFonts.display, size: ONTUI.points(30)))
                        .foregroundStyle(theme.ink)
                    Text("ce qui est gravé")
                        .font(ONTUI.subheadline)
                        .foregroundStyle(.secondary)

                    EnAttenteDeContenu()
                        .padding(.top, spacing.xl)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, spacing.page)
                .padding(.top, spacing.l)
            }
            .ontScreen()
            .navigationTitle("Khuqqim")
            .ontTitreCompact()
        }
    }
}

/// L'état vide, tant qu'aucun khuq n'est écrit.
///
/// Il nomme ce qui manque au lieu de le masquer. Un état vide muet fait croire
/// à un défaut de chargement, et le lecteur relance l'app pour rien.
private struct EnAttenteDeContenu: View {
    @Environment(\.ontTheme) private var theme
    private var spacing = ONTSpacing()

    var body: some View {
        VStack(alignment: .leading, spacing: spacing.s) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: ONTUI.points(28), weight: .light))
                .foregroundStyle(ONTColors.brandInk(theme.mode))
            Text("Rien à lire pour l'instant")
                .font(ONTUI.headline)
                .foregroundStyle(theme.ink)
            Text("Cet onglet portera les khuqqim. Ils ne sont pas encore écrits.")
                .font(ONTUI.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
