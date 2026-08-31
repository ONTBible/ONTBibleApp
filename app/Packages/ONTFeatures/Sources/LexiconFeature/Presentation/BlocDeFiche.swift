import ONTDesignSystem
import ONTKit
import SwiftUI

/// Un bloc de fiche, quel qu'il soit.
///
/// **Partagé par les deux feuilles** — celle d'un intraduisible et celle d'un
/// Shem. Elles diffèrent par ce qu'elles annoncent autour ; le corps d'une
/// fiche, lui, se rend de la même façon, et le dédoubler ferait diverger les
/// deux au premier bloc ajouté au domaine.
///
/// **La fiche ne rendait que ses paragraphes**, et tout le reste tombait sans
/// rien dire — exactement comme le pipeline jetait les titres avant de les
/// émettre. Deux silences en série : celui qui écrivait la fiche ne pouvait pas
/// savoir lequel des deux l'avait mangée.
///
/// Une fiche porte maintenant trois mouvements — la racine dans les six
/// ruachim, le porteur, les renvois — et sans leurs titres ils arrivent collés
/// en un seul flot.
struct BlocDeFiche: View {
    @Environment(\.ontTheme) private var theme
    let block: Block

    var body: some View {
        switch block {
        case .paragraph(let nodes):
            Text(ONTTextRenderer.compose(nodes, theme: theme))
                .lineSpacing(4)

        case .heading(let level, let nodes):
            // **Les niveaux se resserrent au lieu de se suivre.** Un `##` de
            // fiche est déjà sous un en-tête de section du formulaire ; lui
            // donner une taille de titre le ferait rivaliser avec « Ce qu'il
            // signifie », qui le contient. Deux tailles suffisent, et la
            // seconde n'est qu'une nuance.
            Text(ONTTextRenderer.compose(nodes, theme: theme))
                .font(level <= 2 ? .subheadline.weight(.semibold) : .footnote.weight(.semibold))
                .foregroundStyle(theme.accent)
                .padding(.top, 6)
                // Un titre est un en-tête pour VoiceOver, sans quoi il se lit
                // comme une phrase de plus dans le flot.
                .accessibilityAddTraits(.isHeader)

        case .list(_, let items):
            // Le « Voir aussi » est une liste, et c'est le bloc qui devenait le
            // plus illisible collé à la prose.
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("·").foregroundStyle(theme.accent)
                            .font(ONTUI.ligneDeListe)
                        Text(ONTTextRenderer.compose(item, theme: theme))
                    }
                }
            }

        case .quote(let nodes):
            Text(ONTTextRenderer.compose(nodes, theme: theme))
                .italic()
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Capsule().fill(theme.accent.opacity(0.4)).frame(width: 2)
                }

        case .rule:
            Divider()

        // Une fiche ne porte ni versets ni tableaux. Les nommer plutôt que les
        // laisser à un `default` fait que l'ajout d'un cas au domaine casse ici
        // — c'est le seul endroit qui le dirait.
        case .verses, .table:
            EmptyView()
        }
    }
}
