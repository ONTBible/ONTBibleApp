import AppKit
import ONTDesignSystem
import SwiftUI

// MARK: - La construction de Craft, mesurée au pixel

/// Trois lectures successives de la même capture, et c'est la **mesure** qui a
/// tranché (4 septembre 2026, balayages pixel par pixel) :
///
///     bord gauche  → fenêtre → barre (ton 76), sans gouttière ;
///     zone des feux → posés SUR la barre — elle monte jusqu'au bord ;
///     barre → contenu : 76 → **59 sur ~20 pt** → 35 ;
///     bord droit    : 35 → **59 sur ~23 pt** → fenêtre.
///
/// Donc : **la barre est soudée** — gauche, haut avec les feux, bas — et c'est
/// **le contenu qui flotte**, une page posée sur une toile visible en
/// gouttière. La hiérarchie des tons : barre > toile > page.
///
/// Les deux premières lectures — « tout est soudé », puis « tout flotte » —
/// avaient chacune la moitié. L'auteur a corrigé les deux fois ; la mesure a
/// clos le débat.
enum Toile {
    /// La gouttière autour de la page.
    static let marge: CGFloat = 10
    /// Le coin de la page posée.
    static let coin: CGFloat = 12
}

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

/// La barre — **soudée**, pleine hauteur, les feux posés dessus, sur sa vitre.
private struct PanneauDeBarre: ViewModifier {
    @Environment(\.ontTheme) private var theme

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    VitreArriere()
                    // Le voile du thème, aux deux tiers — la vitre seule est
                    // grise, la barre doit rester de la maison.
                    theme.surface.opacity(0.65)
                }
                // Jusqu'aux bords : chez Craft les feux sont posés sur la
                // barre, mesuré — elle ne commence pas sous la barre de titre.
                .ignoresSafeArea()
            }
    }
}

/// La page de lecture — **posée** : découpée, en retrait, la toile en gouttière.
private struct PanneauDeContenu: ViewModifier {
    func body(content: Content) -> some View {
        content
            .clipShape(.rect(cornerRadius: Toile.coin))
            .padding(.trailing, Toile.marge)
            .padding(.vertical, Toile.marge)
            .padding(.leading, Toile.marge)
            // Le sol de la colonne est la toile — sans lui, la matière du
            // système remplirait la gouttière, et la page serait posée sur
            // rien de visible.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { CouleurDeToile().ignoresSafeArea() }
    }
}

/// La toile — **entre** les deux tons, comme chez Craft (76 > 59 > 35) : plus
/// sombre que la barre, plus claire que la page. Le voile de surface sur le
/// fond — aucune couleur inventée.
private struct CouleurDeToile: View {
    @Environment(\.ontTheme) private var theme

    var body: some View {
        ZStack {
            theme.background
            theme.surface.opacity(0.6)
        }
    }
}

extension View {
    /// La barre soudée sur sa vitre.
    func panneauFlottant() -> some View { modifier(PanneauDeBarre()) }
    /// La page posée sur la toile.
    func panneauDeContenu() -> some View { modifier(PanneauDeContenu()) }
    /// Le fond de secours du séparateur de colonnes.
    func toileDeFond() -> some View {
        background { CouleurDeToile().ignoresSafeArea() }
    }
}
