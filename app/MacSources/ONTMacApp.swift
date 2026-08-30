import LexiconFeature
import ONTData
import ONTDesignSystem
import ONTKit
import QahalFeature
import ReadingFeature
import SearchFeature
import AppKit
import SwiftUI
import YouFeature

/// La liseuse du Mac.
///
/// ## Ce qu'elle partage, et c'est presque tout
///
/// Les quatre paquets, donc le corpus, les thèmes, le moteur de rendu et les
/// seuils de contraste. La même `Composition` qu'iOS assemble les mêmes
/// dépôts sur les mêmes fichiers. **Rien de ce qui fait la lecture n'est
/// réécrit ici** — c'est ce qui permet à une correction de contraste de valoir
/// sur les deux plateformes sans qu'on y pense.
///
/// ## Ce qui diffère, et pourquoi
///
/// **Une fenêtre qu'on redimensionne**, avec une taille minimale : le rendu du
/// texte suppose une colonne, et une fenêtre réduite à une bande la casserait.
///
/// **Pas de `PushDelegate`** : les notifications distantes passent par un autre
/// mécanisme sur le Mac, et une liseuse de bureau n'en a pas besoin pour
/// rendre le service qu'on lui demande.
///
/// **L'ouverture animée, elle, reste.** J'avais commencé par l'écarter, en
/// pensant qu'elle couvrait le temps de chargement d'un téléphone — un Mac
/// l'ayant fait avant que la fenêtre paraisse, elle n'aurait été qu'un délai
/// qu'on s'impose.
///
/// C'était mal lire ce qu'elle fait. Elle ne masque rien : sa durée est fixe et
/// ne dépend d'aucun chargement. **Elle porte la marque** — la montagne est
/// l'identité de l'ONT, pas un cache-misère —, et l'écarter aurait retiré au
/// Mac le seul moment où l'app dit qui elle est.
///
/// La leçon est la même qu'ailleurs aujourd'hui : on retire une chose pour la
/// raison qu'on croit qu'elle a, et l'on découvre qu'elle en avait une autre.
@main
struct ONTMacApp: App {
    @State private var composition = Composition()
    @State private var vault = ModeVault()

    var body: some Scene {
        WindowGroup {
            AvecOuverture(theme: composition.reading.preferences.theme) {
                RootView()
            }
                .environment(composition.router)
                .environment(composition.reading)
                .environment(composition.lexicon)
                .environment(composition.search)
                .environment(composition.qahal)
                .environment(composition.you)
                .environment(composition.account)
                .environment(composition)
                // La colonne de lecture a besoin d'une largeur ; en dessous,
                // les gloses se hachent et le texte cesse d'être lisible —
                // ce que cette app existe précisément pour éviter.
                .frame(minWidth: 720, minHeight: 520)
                .environment(vault)
                // L'état du mode vault, en bas de fenêtre et non en alerte :
                // il change à chaque sauvegarde, et une alerte par phrase
                // rendrait l'app inutilisable pendant qu'on écrit.
                .safeAreaInset(edge: .bottom) {
                    if vault.vault != nil { BandeauDuVault(mode: vault) }
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            // Le Mac attend qu'on puisse changer de thème au clavier — et
            // avec un kératocône, on en change souvent, selon la lumière de
            // la pièce. Le réglage existe déjà dans l'écran de lecture ; ce
            // raccourci le double, il ne le remplace pas.
            CommandGroup(after: .newItem) {
                Divider()
                Button("Suivre un vault…") { choisirLeVault() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                if vault.vault != nil {
                    Button("Cesser de suivre") { vault.arreter() }
                }
            }
            CommandGroup(after: .toolbar) {
                Divider()
                Button("Thème suivant") {
                    let ordre = ReadingTheme.allCases
                    let actuel = composition.reading.preferences.theme
                    let suivant = ordre.firstIndex(of: actuel).map {
                        ordre[($0 + 1) % ordre.count]
                    }
                    if let suivant { composition.reading.preferences.theme = suivant }
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }
    }

    /// Demande le dossier du vault, et le suit.
    ///
    /// `NSOpenPanel` plutôt qu'un chemin dans les réglages : c'est lui qui
    /// donne à l'app le **droit** de lire hors de son bac à sable. Un chemin
    /// tapé à la main ne le donnerait pas, et l'app échouerait à la lecture
    /// sans que rien n'explique pourquoi.
    private func choisirLeVault() {
        let panneau = NSOpenPanel()
        panneau.canChooseDirectories = true
        panneau.canChooseFiles = false
        panneau.allowsMultipleSelection = false
        panneau.prompt = "Suivre"
        panneau.message = "Le dossier du vault — celui qui contient les brouillons."
        if panneau.runModal() == .OK, let url = panneau.url {
            vault.suivre(url)
        }
    }
}

/// L'état du mode vault, discret et permanent.
private struct BandeauDuVault: View {
    let mode: ModeVault

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbole)
            Text(libelle).font(.footnote.monospacedDigit())
            Spacer()
            if let vault = mode.vault {
                Text(vault.lastPathComponent)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var symbole: String {
        switch mode.etat {
        case .eteint, .enAttente: "eye"
        case .enCours: "arrow.triangle.2.circlepath"
        case .fait: "checkmark.circle"
        case .echec: "exclamationmark.triangle"
        }
    }

    private var libelle: String {
        switch mode.etat {
        case .eteint: "—"
        case .enAttente: "en attente d'une pause dans l'écriture"
        case .enCours: "reconstruction…"
        case .fait(let unites, let versets): "\(unites) unités, \(versets) versets"
        case .echec(let raison): raison
        }
    }
}
