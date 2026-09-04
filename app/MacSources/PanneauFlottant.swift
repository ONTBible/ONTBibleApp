import AppKit
import ONTDesignSystem
import SwiftUI

// MARK: - La toile et les panneaux

/// La construction de Craft, lue pour de bon sur sa capture : **la fenêtre est
/// une toile, et deux panneaux flottent dessus** — la barre latérale *et* le
/// contenu, chacun ses coins ronds, des retraits fins, ni bordure ni ombre.
/// La séparation se fait au ton : la toile est plus sombre que ce qu'elle
/// porte.
///
/// ## Les trois états qu'il a fallu traverser
///
/// 1. la barre opaque soudée — « une bande dans la bande » ;
/// 2. une carte flottante *seule*, marges, ombre, filet — « pas natif, ça fait
///    bizarre », et l'auteur avait raison : un panneau unique contre une page
///    pleine est un objet collé sur un mur ;
/// 3. la lecture correcte de Craft — « non, la sidebar Craft elle flotte » :
///    elle flotte **avec** le contenu, sur une toile commune. C'est l'écosystème
///    qui fait le flottement, pas l'objet.
enum Toile {
    /// Le retrait des panneaux sur la toile.
    static let marge: CGFloat = 8
    /// Le coin d'un panneau — plus serré que la feuille : un panneau est un
    /// meuble, pas une carte.
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

/// Le panneau de la barre — la vitre et le voile, découpés au coin de la toile.
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
            }
            .clipShape(.rect(cornerRadius: Toile.coin))
            .padding(.leading, Toile.marge)
            .padding(.vertical, Toile.marge)
            .padding(.trailing, Toile.marge / 2)
            // **Le sol de la colonne est la toile.** Sans lui, la matière de
            // la colonne du système remplit les marges avec la même vitre que
            // le panneau — marges posées, marges invisibles, mesuré sur
            // capture. Même remède que pour le sol de page d'hier : recouvrir.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { CouleurDeToile().ignoresSafeArea() }
    }
}

/// Le panneau du contenu — la page de lecture, posée sur la même toile.
private struct PanneauDeContenu: ViewModifier {
    @Environment(\.ontTheme) private var theme

    func body(content: Content) -> some View {
        content
            .clipShape(.rect(cornerRadius: Toile.coin))
            .padding(.trailing, Toile.marge)
            .padding(.vertical, Toile.marge)
            .padding(.leading, Toile.marge / 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { CouleurDeToile().ignoresSafeArea() }
    }
}

/// La couleur de la toile — le fond du thème, assombri d'un voile noir.
///
/// Un cran plus sombre que la page : c'est cet écart, et lui seul, qui fait
/// lire les panneaux comme posés. Pas de couleur neuve.
private struct CouleurDeToile: View {
    @Environment(\.ontTheme) private var theme

    var body: some View {
        ZStack {
            theme.background
            Color.black.opacity(0.35)
        }
    }
}

/// La toile — sous les deux panneaux, jusqu'aux bords de la fenêtre.
private struct ToileDeFond: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background { CouleurDeToile().ignoresSafeArea() }
    }
}

extension View {
    /// La barre latérale en panneau sur la toile.
    func panneauFlottant() -> some View { modifier(PanneauDeBarre()) }
    /// Le contenu en panneau sur la toile.
    func panneauDeContenu() -> some View { modifier(PanneauDeContenu()) }
    /// La toile sous les panneaux — à poser sur le `NavigationSplitView`.
    func toileDeFond() -> some View { modifier(ToileDeFond()) }
}
