import ONTDesignSystem
import ONTKit
import SwiftUI

/// Pose l'animation d'ouverture par-dessus l'app, le temps qu'elle dure.
///
/// # Pourquoi une enveloppe plutôt qu'un écran de plus
///
/// L'app se monte **derrière** pendant que l'ouverture joue. Elle a donc fini
/// de charger le corpus quand la montagne s'efface, et le lecteur ne subit pas
/// deux attentes l'une après l'autre.
///
/// L'inverse — jouer l'animation *puis* monter l'app — aurait rallongé le
/// démarrage de toute sa durée.
///
/// # Une fois par lancement, pas une fois par ouverture
///
/// Aucun drapeau, aucun enregistrement. La scène n'est construite qu'une fois
/// par lancement de processus : revenir de l'arrière-plan ne rejoue rien, et
/// une app tuée puis rouverte rejoue. C'est ce qui était demandé, et le système
/// le donne tout seul.
struct AvecOuverture<Contenu: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduireLeMouvement

    @State private var ouverte = true
    @State private var debut = Date()

    /// Le thème vers lequel l'ouverture se dissout.
    ///
    /// Passé plutôt qu'allé chercher dans l'environnement : l'ouverture ne
    /// dépend du thème que pour **finir**, et une vue qui réclame un modèle
    /// entier pour lire une seule valeur se rend plus difficile à éprouver
    /// qu'elle n'a besoin de l'être.
    private let theme: ReadingTheme
    private let contenu: Contenu

    init(theme: ReadingTheme, @ViewBuilder contenu: () -> Contenu) {
        self.theme = theme
        self.contenu = contenu()
    }

    var body: some View {
        ZStack {
            contenu

            if ouverte {
                ONTSplash(theme: theme, debut: debut)
                    .transition(.opacity)
                    // Au-dessus de tout, y compris des feuilles que l'app
                    // pourrait poser au montage.
                    .zIndex(1)
                    // Un appui l'écarte. Elle dure cinq secondes et demie, ce
                    // qui est long quand on ouvre l'app pour vérifier un
                    // verset : celui qui la connaît doit pouvoir passer outre
                    // sans que celui qui la découvre soit privé de la voir.
                    .onTapGesture { fermer() }
                    .accessibilityAction(named: "Passer l'ouverture") { fermer() }
            }
        }
        // **La barre d'état s'efface pendant l'ouverture.**
        //
        // Elle restait réglée sur le thème de lecture — sombre sur le
        // parchemin — et se retrouvait donc en icônes sombres sur la nuit :
        // illisible.
        //
        // La première correction posait `.preferredColorScheme(.dark)` ici, et
        // **elle a cassé les couleurs de toute l'app** : les titres sortaient
        // en blanc sur le parchemin, la barre d'onglets en gris. `RootView`
        // porte précisément cet avertissement — *un `preferredColorScheme`
        // posé au sommet ne se comporte pas comme un posé sous les onglets* —
        // et j'ai fait exactement ce qu'il déconseille.
        //
        // Masquer coûte moins et vaut mieux : l'ouverture n'a que faire de
        // l'heure et du réseau, et rien ne déborde sur l'app.
        .ontSansBarreDEtat(ouverte)
        .task {
            // Le lecteur qui a demandé moins de mouvement voit la montagne, pas
            // le balayage — et il la voit moins longtemps : l'attente et la
            // rémanence n'ont plus rien à accompagner.
            let duree = reduireLeMouvement ? 1.2 : ONTSplash.Minutage.total
            try? await Task.sleep(for: .seconds(duree))
            fermer()
        }
    }

    private func fermer() {
        guard ouverte else { return }
        withAnimation(.easeOut(duration: 0.45)) { ouverte = false }
    }
}
