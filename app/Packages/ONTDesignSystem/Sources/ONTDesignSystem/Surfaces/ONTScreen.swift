import ONTKit
import SwiftUI

/// L'écran type de l'ONT.
///
/// Sans ce modificateur, chaque écran hérite du fond que lui impose son
/// conteneur : une `List` groupée pose un gris système, une `List` simple pose
/// du blanc, et un `ScrollView` laisse passer le fond de la fenêtre. Le
/// résultat, ce sont quatre onglets qui ne se ressemblent pas — alors même
/// qu'un design system est en place.
///
/// `scrollContentBackground(.hidden)` est la clé : c'est le seul moyen de
/// retirer le fond qu'une `List` ou un `Form` dessine par-dessus le nôtre.
///
/// **Tout écran de premier niveau doit l'appliquer.** C'est la règle qui
/// garantit que l'app a une seule couleur de peau.
public struct ONTScreenModifier: ViewModifier {
    @Environment(\.ontTheme) private var theme

    public func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            // Le grain de la nuit se pose ici, et **seulement** ici : c'est le
            // point unique par lequel passe le fond de tous les écrans, donc le
            // seul endroit où il ne peut ni manquer quelque part, ni se
            // superposer à lui-même et doubler son opacité.
            .background {
                theme.background
                    .overlay(ONTGrain(theme: theme.mode))
                    .ignoresSafeArea()
            }
    }
}

/// La colonne de l'app — bornée en largeur, centrée, sur un fond qui reste plein.
///
/// Sur iPhone, elle ne fait rien : l'écran est plus étroit que la borne. Sur
/// iPad, elle est ce qui empêche l'app de s'étirer d'un bord à l'autre — une
/// carte de verset large de mille points, une liste dont les valeurs partent si
/// loin à droite qu'on ne sait plus à quelle ligne elles appartiennent.
///
/// ## Posée **autour** de la pile de navigation, et pas dedans
///
/// Le grand titre appartient à la barre de navigation. Borner seulement le
/// contenu laissait « Qahal » collé à la marge pendant que la carte se centrait
/// deux cents points plus loin : deux alignements pour une même page, ce qui se
/// lit comme un défaut. En bornant la pile entière, le titre suit sa page.
///
/// ## Les marges reçoivent le même fond que la colonne, grain compris
///
/// Il faut peindre de part et d'autre, sinon l'iPad montre le gris du système.
/// Et il faut y mettre le grain : mesuré, des marges plates sortaient à
/// (24, 9, 13) contre (27, 12, 16) au centre — trois points d'écart, un liseré
/// visible sur toute la hauteur.
///
/// Ça ne double pas le grain de la colonne, contrairement à ce que la mise en
/// garde d'`ONTScreenModifier` laisse craindre : le fond que l'écran pose
/// **dedans** est opaque, donc il couvre celui-ci au lieu de s'y ajouter. Ce
/// qu'on peint ici ne se voit que là où rien d'autre ne passe.
///
/// La peinture ne peut d'ailleurs pas venir d'ici : posée au-dehors, elle est
/// recouverte par le fond que la pile de navigation dessine pour elle-même —
/// une colonne noire entre deux marges aubergine. Chaque onglet garde donc son
/// `ontScreen()`.
public struct ONTColumnModifier: ViewModifier {
    @Environment(\.ontTheme) private var theme

    public func body(content: Content) -> some View {
        content
            .frame(maxWidth: ONTLayout.pageWidth)
            .frame(maxWidth: .infinity)
            .background {
                theme.background
                    .overlay(ONTGrain(theme: theme.mode))
                    .ignoresSafeArea()
            }
    }
}

/// La ligne de liste type — surface du thème, séparateur du thème.
public struct ONTRowModifier: ViewModifier {
    @Environment(\.ontTheme) private var theme
    private var spacing = ONTSpacing()

    public func body(content: Content) -> some View {
        content
            .listRowBackground(theme.surface)
            .listRowSeparatorTint(theme.separator)
            // **Les marges d'une rangée, sur le Mac.**
            //
            // iOS les donne avec `insetGrouped` — des groupes détachés, dont le
            // contenu respire. Le Mac n'a pas ce style ; `inset`, son plus
            // proche, en pose beaucoup moins, et le texte d'une fiche venait
            // toucher les deux bords de la feuille.
            //
            // Ce n'est pas une coquetterie : une colonne de lecture sans marge
            // fatigue, et l'œil perd sa ligne au retour. C'est la même raison
            // qui donne à la fenêtre une largeur minimale.
            //
            // On les pose sur la **rangée** plutôt que sur la feuille : chaque
            // écran qui emploie `ontRow` en profite, et un futur écran de
            // réglages n'aura pas à y penser.
            #if os(macOS)
                .listRowInsets(
                    EdgeInsets(
                        top: spacing.m, leading: spacing.page,
                        bottom: spacing.m, trailing: spacing.page))
            #endif
    }
}

extension View {
    /// Le fond de l'app, y compris sous une `List` ou un `Form`.
    public func ontScreen() -> some View { modifier(ONTScreenModifier()) }

    /// La surface d'une ligne de liste.
    public func ontRow() -> some View { modifier(ONTRowModifier()) }

    /// La colonne de l'app — à poser autour de la pile de navigation d'un onglet.
    public func ontColumn() -> some View { modifier(ONTColumnModifier()) }
}
