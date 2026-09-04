import AppKit
import ONTDesignSystem
import SwiftUI

// MARK: - La vitre de la barre latérale

/// La barre latérale translucide — **bord à bord, pleine hauteur**, comme
/// toute barre native du Mac.
///
/// ## L'aller-retour, parce qu'il a été tranché en main
///
/// Une version flottante — détachée des bords, coins ronds, ombre, à la
/// Craft — a été construite, montrée, prise en main, et **écartée par
/// l'auteur** le 4 septembre 2026 : « on voit que ce rendu est pas natif, ça
/// fait bizarre ». Il avait raison sur la sensation : les barres du Mac sont
/// des colonnes, pas des cartes. Ce qui est resté du voyage est le seul
/// morceau qui comptait — la **translucidité**.
///
/// ## Pourquoi `NSVisualEffectView`, et pas un matériau SwiftUI
///
/// `.ultraThinMaterial` compose **dans la fenêtre** : il floute ce que la
/// fenêtre dessine derrière la vue — or derrière la barre il n'y a que la
/// colonne. La translucidité des barres natives traverse la **fenêtre** :
/// c'est le bureau qu'on devine. Seul `NSVisualEffectView` en `.behindWindow`
/// fait ça.
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

/// La vitre et le voile du thème, sous toute la colonne.
private struct VitreDeBarre: ViewModifier {
    @Environment(\.ontTheme) private var theme

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    VitreArriere()
                    // Le voile du thème, aux deux tiers : la vitre seule est
                    // grise — celle du système — et la barre doit rester de la
                    // maison. À 0,65 l'aubergine reprend la main et le bureau
                    // se devine toujours ; à 0,8 on retrouvait un aplat et la
                    // vitre ne servait plus.
                    theme.surface.opacity(0.65)
                }
                // Jusqu'au haut de la fenêtre : une barre native court sous la
                // barre d'outils, elle ne commence pas en dessous.
                .ignoresSafeArea()
            }
    }
}

extension View {
    /// La barre latérale sur sa vitre — translucide, bord à bord.
    func panneauFlottant() -> some View { modifier(VitreDeBarre()) }
}
