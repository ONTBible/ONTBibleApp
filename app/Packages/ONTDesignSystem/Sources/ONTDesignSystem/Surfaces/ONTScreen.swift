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

/// La ligne de liste type — surface du thème, séparateur du thème.
public struct ONTRowModifier: ViewModifier {
    @Environment(\.ontTheme) private var theme

    public func body(content: Content) -> some View {
        content
            .listRowBackground(theme.surface)
            .listRowSeparatorTint(theme.separator)
    }
}

extension View {
    /// Le fond de l'app, y compris sous une `List` ou un `Form`.
    public func ontScreen() -> some View { modifier(ONTScreenModifier()) }

    /// La surface d'une ligne de liste.
    public func ontRow() -> some View { modifier(ONTRowModifier()) }
}
