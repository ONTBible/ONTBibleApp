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
    /// Voir `DelegueMac` — il existe pour une seule raison : recevoir les liens
    /// avant que SwiftUI n'en fasse une fenêtre de plus.
    @NSApplicationDelegateAdaptor(DelegueMac.self) private var delegue
    @State private var vault = ModeVault()

    var body: some Scene {
        WindowGroup {
            AvecOuverture(theme: etat.composition.reading.preferences.theme) {
                RacineMac()
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
                // Pas de `.dynamicTypeSize` : mesuré inerte sur macOS — voir
                // `ONTEchelleUI` et l'épreuve qui le montre. L'échelle passe
                // par `EtatMac.appliquerLEchelle`, qui la pose dans le design
                // system.
                .frame(minWidth: 720, minHeight: 520)
                .environment(vault)
                // **Cette fenêtre-ci sait recevoir les liens.**
                //
                // La forme *vue* de `handlesExternalEvents`, et non la forme
                // *scène* : la première dit « celle-ci sait faire », la seconde
                // dit seulement « ce groupe sait faire » — et SwiftUI ouvre
                // alors une fenêtre neuve pour le prouver. Mesuré : deux
                // fenêtres, dont la première rétractée à 99 × 144 points.
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                // L'état du mode vault, en bas de fenêtre et non en alerte :
                // il change à chaque sauvegarde, et une alerte par phrase
                // rendrait l'app inutilisable pendant qu'on écrit.
                .safeAreaInset(edge: .bottom) {
                    if vault.vault != nil { BandeauDuVault(mode: vault) }
                }
        }
        // **La taille d'ouverture, mesurée et non choisie.**
        //
        // 1240 × 960, soit un rapport de **1,29** — celui de la fenêtre que
        // l'auteur a montrée en référence, relevé au pixel sur sa capture plutôt
        // qu'estimé à l'œil.
        //
        // Ce rapport n'est pas décoratif : plus large, la colonne de lecture
        // laisse deux marges vides que rien n'occupe ; plus étroit, les gloses
        // se hachent. C'est la forme d'une page, et c'est ce que l'app est.
        //
        // `defaultSize` ne s'applique qu'à la **première** ouverture : macOS
        // restaure ensuite la taille que le lecteur a donnée, ce qui est le
        // comportement voulu — on propose, on n'impose pas.
        .defaultSize(width: 1240, height: 960)
        .windowResizability(.contentMinSize)
        // **Les réglages où le Mac les attend.** `Settings` reçoit ⌘, du
        // système, apparaît dans le menu de l'app, et se ferme comme une
        // fenêtre de réglages — trois choses qu'un onglet ne peut pas donner.
        Settings {
            YouTab(onDailyChange: { _ in true }, onParutions: { _ in false })
                .environment(etat.composition.router)
                .environment(etat.composition.reading)
                .environment(etat.composition.lexicon)
                .environment(etat.composition.search)
                .environment(etat.composition.qahal)
                .environment(etat.composition.you)
                .environment(etat.composition.account)
                .environment(etat.composition)
                .ontTheme(from: etat.composition.reading.preferences)
                .frame(minWidth: 620, minHeight: 520)
        }

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
                // **La barre latérale, par l'action du système.**
                //
                // Elle n'est pas à nous : `TabView(.sidebarAdaptable)` la
                // fabrique, et aucun état de la vue ne la commande. On demande
                // donc au répondeur de faire ce qu'il sait faire — c'est le
                // même chemin que le bouton de la barre d'outils emprunte.
                //
                // ⌘B plutôt que le ⌃⌘S d'AppKit : c'est le geste que les apps
                // de lecture ont adopté, et le lecteur le connaît d'ailleurs.
                Button("Masquer ou afficher la barre latérale") {
                    NSApp.keyWindow?.firstResponder?.tryToPerform(
                        Selector(("toggleSidebar:")), with: nil)
                }
                .keyboardShortcut("b", modifiers: .command)

                // **Où paraissent les fiches.** Le réglage est aussi dans la
                // barre de tête de la fiche elle-même — mais on ne le trouve
                // là qu'une fois qu'on en a ouvert une. Le menu l'annonce
                // avant.
                Button(etat.modeDeFiche.titreDeBascule) {
                    etat.modeDeFiche = etat.modeDeFiche.suivant
                }
                .keyboardShortcut("i", modifiers: [.command, .option])

                Divider()
                Button("Agrandir l'interface") { etat.interface(de: 1) }
                // **`=` et non `+`, et ce n'est pas un détail de forme.**
                //
                // Sur un clavier français, `+` s'obtient par Maj+`=`. Un
                // raccourci déclaré `⌘+` **sans** Maj ne peut donc correspondre
                // à aucune frappe réelle : le système livre « + » avec Maj, la
                // déclaration attend « + » sans, et rien ne se produit jamais.
                //
                // C'est ce que l'auteur constatait — « ⌘+ ne marche toujours
                // pas ». Le raccourci n'était pas cassé, il était **intypable**.
                //
                // `⌘=` se tape directement, et le menu l'affiche tel quel.
                .keyboardShortcut("=", modifiers: .command)
                Button("Réduire l'interface") { etat.interface(de: -1) }
                .keyboardShortcut("-", modifiers: .command)
                Button("Taille d'interface par défaut") { etat.interfaceParDefaut() }
                .keyboardShortcut("0", modifiers: .command)

                Divider()
                // **⌃ et non ⌥.** `⌘⌥+` est pris par le zoom d'accessibilité du
                // système sur bien des machines : le raccourci partait au
                // zoom d'écran au lieu d'arriver ici.
                // Le corps du texte sur **⌘⇧**, à la demande de l'auteur.
                //
                // `=` là aussi : `⌘⇧+` demanderait Maj **deux fois**, ce qui ne
                // se tape pas. `⌘⇧=` est la frappe qui produit ce que tout le
                // monde appelle « ⌘⇧+ ».
                Button("Agrandir le texte") { etat.corps(de: 1) }
                    .keyboardShortcut("=", modifiers: [.command, .shift])
                Button("Réduire le texte") { etat.corps(de: -1) }
                    .keyboardShortcut("-", modifiers: [.command, .shift])

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
            Text(libelle).font(ONTUI.footnote.monospacedDigit())
            Spacer()
            if let vault = mode.vault {
                Text(vault.lastPathComponent)
                    .font(ONTUI.footnote)
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

/// Le délégué d'application — pour les liens, et rien d'autre.
///
/// ## Pourquoi il faut en passer par là
///
/// `ont://term/bara` ouvrait une **seconde fenêtre**, et rétractait la première
/// à 99 × 144 points au passage — mesuré, deux fenêtres au lieu d'une, dont une
/// vide. SwiftUI traite un événement externe que personne ne revendique comme
/// une raison d'ouvrir une scène ; `handlesExternalEvents(matching:)` n'y a rien
/// changé, essayé avec le schéma puis avec `*`.
///
/// Un délégué qui implémente `application(_:open:)` consomme l'événement avant
/// ce mécanisme. C'est le seul endroit du Mac où l'on redescend sous SwiftUI, et
/// c'est pour la même raison que partout ailleurs aujourd'hui : ce qui est en
/// jeu appartient au système, pas à l'app.
final class DelegueMac: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            for url in urls { EtatMac.partage.composition.router.open(url) }
        }
    }
}
