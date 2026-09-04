import AppKit
import ONTDesignSystem
import SwiftUI

// MARK: - Le panneau flottant de la barre latérale

/// La barre latérale de Craft : **détachée des bords, translucide, posée sur
/// la fenêtre** — pas une colonne pleine hauteur soudée au cadre.
///
/// C'est aussi ce que l'iPad donne d'office avec `sidebarAdaptable` : une barre
/// qui flotte sur le contenu, et dont on voit qu'elle est un objet. L'auteur
/// l'a demandée trois fois ; la voici.
///
/// ## Pourquoi `NSVisualEffectView`, et pas un matériau SwiftUI
///
/// `.ultraThinMaterial` de SwiftUI compose **dans la fenêtre** : il floute ce
/// que la fenêtre dessine derrière la vue — or derrière la barre il n'y a que
/// le fond de la colonne. La translucidité de Craft traverse la **fenêtre** :
/// c'est le bureau qu'on devine. Seul `NSVisualEffectView` en
/// `.behindWindow` fait ça.
///
/// Le verre du système (macOS 26) se pose par-dessus quand il existe — voir
/// `verreLiquide(_:)` — mais le socle reste l'effet de vitre arrière, qui
/// existe partout où l'app tourne.
private struct VitreArriere: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let vue = NSVisualEffectView()
        vue.blendingMode = .behindWindow
        vue.material = .sidebar
        vue.state = .active
        return vue
    }

    func updateNSView(_ vue: NSVisualEffectView, context: Context) {}
}

/// Le panneau — la vitre, le voile du thème, le coin rond, le filet.
private struct PanneauFlottant: ViewModifier {
    @Environment(\.ontTheme) private var theme

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    VitreArriere()
                    // Le voile du thème, aux deux tiers : la vitre seule est
                    // grise — celle du système — et à 0,5 la barre tirait
                    // encore au gris sur capture. À 0,65 l'aubergine reprend
                    // la main, le bureau se devine toujours ; à 0,8 on
                    // retrouvait un aplat et la vitre ne servait plus.
                    theme.surface.opacity(0.65)
                }
            }
            .clipShape(.rect(cornerRadius: 18))
            .overlay {
                // Le filet qui attrape la lumière — le bord d'un objet posé,
                // pas la bordure d'un cadre.
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(.white.opacity(theme.mode.isDark ? 0.08 : 0.28), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 18, y: 6)
            .padding(.leading, 12)
            .padding(.vertical, 12)
    }
}

extension View {
    /// La barre latérale en objet flottant — vitre, coin rond, marges.
    func panneauFlottant() -> some View { modifier(PanneauFlottant()) }
}
