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
    /// L'état partagé — voir `EtatMac` : les fermetures de `.commands` ne
    /// voient pas la même instance que la fenêtre, donc rien de mutable ne
    /// vit dans cette structure.
    private let etat = EtatMac.partage
    @State private var vault = ModeVault()

    var body: some Scene {
        WindowGroup {
            AvecOuverture(theme: etat.composition.reading.preferences.theme) {
                RootView()
            }
                .environment(etat.composition.router)
                .environment(etat.composition.reading)
                .environment(etat.composition.lexicon)
                .environment(etat.composition.search)
                .environment(etat.composition.qahal)
                .environment(etat.composition.you)
                .environment(etat.composition.account)
                .environment(etat.composition)
                // La colonne de lecture a besoin d'une largeur ; en dessous,
                // les gloses se hachent et le texte cesse d'être lisible —
                // ce que cette app existe précisément pour éviter.
                // **La teinte de l'app, et non celle du système.**
                //
                // Sans elle, le Mac colore les symboles de la barre latérale,
                // les coches et les curseurs avec l'accent choisi dans les
                // Réglages du lecteur — rose vif sur cette machine. Une liseuse
                // dont la peau est or et bordeaux se retrouve alors piquée
                // d'une couleur qui n'est ni l'une ni l'autre.
                //
                // iOS ne pose pas la question : il n'a pas d'accent système
                // qu'une app hérite sans le demander.
                .tint(ONTColors.accent(etat.composition.reading.preferences.theme))
                .dynamicTypeSize(
                    TaillesAuClavier.interface[
                        min(max(etat.tailleInterface, 0),
                            TaillesAuClavier.interface.count - 1)])
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
            // **Deux tailles, deux gestes.** ⌘± règle l'interface ; ⌘⌥± le
            // corps du texte, et rien d'autre. Les confondre serait un
            // contresens : on monte le corps très haut pour lire, sans vouloir
            // qu'une barre latérale enfle et mange la place de ce texte.
            //
            // **Deux tailles, deux gestes, un seul groupe de menu.**
            //
            // ⌘± règle l'interface ; ⌘⌃± le corps du texte, et rien d'autre.
            // Les confondre serait un contresens : on monte le corps très haut
            // pour lire, sans vouloir qu'une barre latérale enfle et mange la
            // place de ce texte.
            //
            // **Un seul `CommandGroup`**, et non trois : deux groupes déclarés
            // au même emplacement se disputent la place, et l'un des deux peut
            // ne pas paraître du tout — un raccourci qu'on croit posé et qui
            // n'existe nulle part.
            CommandGroup(after: .toolbar) {
                Divider()
                Button("Agrandir l'interface") { etat.interface(de: 1) }
                .keyboardShortcut("+", modifiers: .command)
                Button("Réduire l'interface") { etat.interface(de: -1) }
                .keyboardShortcut("-", modifiers: .command)
                Button("Taille d'interface par défaut") { etat.interfaceParDefaut() }
                .keyboardShortcut("0", modifiers: .command)

                Divider()
                // **⌃ et non ⌥.** `⌘⌥+` est pris par le zoom d'accessibilité du
                // système sur bien des machines : le raccourci partait au
                // zoom d'écran au lieu d'arriver ici.
                Button("Agrandir le texte") { etat.corps(de: 1) }
                    .keyboardShortcut("+", modifiers: [.command, .control])
                Button("Réduire le texte") { etat.corps(de: -1) }
                    .keyboardShortcut("-", modifiers: [.command, .control])

                Divider()
                Button("Thème suivant") { etat.themeSuivant() }
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
