import ONTKit
import SwiftUI

/// **Le pavé d'appel en tête d'onglet** — un titre, une ligne qui l'explique,
/// une icône, et tout le pavé se touche.
///
/// ## Ce qu'il est, et ce qu'il n'est pas
///
/// Un hero ouvre **une seule porte**, la principale de son onglet : la feuille
/// de prononciation dans le Lexique, la reprise de lecture dans la Bible. Il
/// est doré et plein parce qu'il doit se voir d'un coup d'œil en arrivant.
///
/// Ce n'est ni une carte de contenu — qui se lit, ne se touche pas, et vit dans
/// `BurgundyCard` —, ni une rangée de liste, qui en porte des dizaines et doit
/// donc rester discrète. Un onglet a un hero ou n'en a pas ; il n'en a jamais
/// deux.
///
/// ## Pourquoi il est ici et non recopié
///
/// Il existait en un seul exemplaire, dans `HeroDePrononciation`, et le pavé
/// « Reprendre » de l'onglet Bible en était une **variante approximative** :
/// même intention, onze propriétés différentes — le fond, le rayon, les deux
/// fontes, la couleur du texte, le poids de l'icône, trois marges, la hauteur
/// plancher et le style de bouton.
///
/// Aucune de ces onze différences n'était une décision. Elles sont le résidu de
/// deux écritures séparées, et c'est exactement ce qu'un composant nommé
/// supprime.
///
/// > **Deux vues qui font la même chose finissent par ne plus la faire pareil.
/// > Ce n'est pas une question de rigueur : c'est ce que produit la recopie,
/// > par construction.**
///
/// Décision de l'auteur du 13 septembre 2026 : la DA du hero de prononciation
/// vaut pour les deux.
///
/// ## Ce que ses fontes ont coûté d'apprendre
///
/// `ONTUI.headline` et non la fonte d'affichage de la marque : celle-ci porte
/// un interligne large, fait pour un titre d'écran qui tient sur une ligne. Dès
/// que le libellé passe à deux lignes — et il y passe au premier cran
/// d'accessibilité — le blanc entre les deux fait le double de celui du
/// sous-titre, et le pavé se lit comme deux fragments au lieu d'un titre.
///
/// Mesuré, avec une hypothèse écartée en chemin : `relativeTo: .headline` n'y
/// change rien. La courbe d'échelle n'était pas en cause, l'interligne l'était.
public struct ONTHero: View {
    @Environment(\.ontTheme) private var theme
    private let spacing = ONTSpacing()

    private let titre: LocalizedStringKey
    private let sousTitre: LocalizedStringKey
    private let icone: String
    private let action: () -> Void

    /// - Parameters:
    ///   - titre: ce que le hero ouvre, en deux ou trois mots.
    ///   - sousTitre: la ligne qui le précise, jamais un second titre.
    ///   - icone: un symbole SF, tracé **léger** — il accompagne, il n'annonce
    ///     pas. L'annonce est le titre.
    public init(
        _ titre: LocalizedStringKey,
        sousTitre: LocalizedStringKey,
        icone: String,
        action: @escaping () -> Void
    ) {
        self.titre = titre
        self.sousTitre = sousTitre
        self.icone = icone
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: spacing.m) {
                VStack(alignment: .leading, spacing: spacing.xs) {
                    Text(titre).font(ONTUI.headline)
                    Text(sousTitre)
                        .font(ONTUI.footnote)
                        // **0,85 et non `.secondary`.** Sur un aplat doré, la
                        // hiérarchie sémantique du système part du fond de
                        // l'écran, pas de celui du pavé : elle rend un gris qui
                        // n'a rien à voir avec l'or. Une opacité de la même
                        // encre garde le rapport voulu sur les quatre thèmes.
                        .opacity(0.85)
                }
                .foregroundStyle(ONTColors.onBrandAccent(theme.mode))
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: icone)
                    .font(.system(size: ONTUI.points(22), weight: .light))
                    .foregroundStyle(ONTColors.onBrandAccent(theme.mode))
            }
            .padding(.horizontal, spacing.l)
            // **Une marge verticale, et non la hauteur minimale qui en tenait
            // lieu.** `minHeight` seul laisse le contenu coller aux bords dès
            // qu'il dépasse le plancher — ce qui arrive au deuxième cran
            // d'accessibilité. La marge tient dans tous les cas ; le plancher
            // ne sert plus qu'à donner sa présence au pavé quand le texte est
            // court.
            .padding(.vertical, spacing.m)
            .frame(minHeight: ONTUI.points(76))
            .background(
                RoundedRectangle(cornerRadius: ONTRadius.hero, style: .continuous)
                    .fill(ONTColors.brandInk(theme.mode))
            )
            .ontSurvol(
                dans: RoundedRectangle(cornerRadius: ONTRadius.hero, style: .continuous),
                souleve: true
            )
            .contentShape(.rect(cornerRadius: ONTRadius.hero))
        }
        .buttonStyle(.ontPresse)
    }
}
