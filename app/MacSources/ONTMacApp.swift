import LexiconFeature
import ONTData
import ONTDesignSystem
import ONTKit
import QahalFeature
import ReadingFeature
import SearchFeature
import os
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
    @State private var vault = ModeVault(
        montrer: { EtatMac.partage.composition.regarderLApercu($0) })

    var body: some Scene {
        // **`Window` et non `WindowGroup`.**
        //
        // Un groupe *peut* engendrer des fenêtres ; une `Window` ne le peut
        // pas. Et c'était le défaut : le **second** `ont://` ouvrait une
        // seconde fenêtre, décalée de 29 points, et chaque lien suivant une de
        // plus — mesuré, quatre liens, quatre fenêtres.
        //
        // Le délégué faisait pourtant son travail à chaque fois : la
        // navigation avait lieu **et** une scène naissait à côté.
        // `handlesExternalEvents` sur la vue ne l'empêche pas — il dit « cette
        // fenêtre sait recevoir », pas « n'en ouvre pas d'autre ». La forme
        // *scène* avec un ensemble vide fait pire, mesuré.
        //
        // Une liseuse n'a pas besoin de deux fenêtres : c'est un texte qu'on
        // lit, pas un document qu'on compare. Musique et Livres font de même.
        Window("La Bible ONT", id: "lecture") {
            AvecLaFonteDeLInterface {
                AvecOuverture(theme: etat.composition.reading.preferences.theme) {
                    RacineMac()
                }
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
                // Reprendre le vault de la session précédente, s'il y en
                // avait un.
                //
                // Dans une vue et non dans le corps de la scène : c'est la
                // même leçon que la fonte d'interface — ce qui est écrit hors
                // d'un corps de vue n'est ni observé ni forcément exécuté au
                // bon moment. `.task` s'attache au cycle de vie de la fenêtre,
                // qui est précisément quand l'auteur peut voir le bandeau
                // s'allumer.
                .task {
                    // **La même condition que le menu, au même endroit.**
                    //
                    // Le menu ne propose « Suivre un vault… » que si le
                    // pipeline est embarqué. Reprendre un vault suivi à la
                    // session précédente ne passait pas par lui : sur un build
                    // sans pipeline — le canal bêta —, l'auteur retrouvait le
                    // bandeau « pipeline non embarqué » **et aucun moyen de
                    // l'enlever**, « Cesser de suivre » étant dans le bloc
                    // caché. Mesuré sur le build 260831.1628.
                    //
                    // La garde est ici et non dans `reprendre()` : le modèle
                    // n'a pas à savoir ce que le bundle contient, et l'y
                    // mettre a cassé « La reprise du vault » — les tests
                    // s'exécutent dans un bundle qui n'embarque rien. Une
                    // décision de présentation appartient à la présentation.
                    if ModeVault.pipelineEmbarque != nil { vault.reprendre() }
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
        // **Plus de scène `Settings`.**
        //
        // Le compte vivait dans une fenêtre à part, ouverte par ⌘,. Deux
        // raisons de l'avoir ramené dans la barre latérale, en bas :
        //
        // - **c'est la place qu'Apple Music lui donne**, et l'auteur l'a
        //   demandée. Le compte n'est pas une destination parmi les livres,
        //   c'est *qui regarde* ;
        // - **une fenêtre à part est un second environnement**, et il divergeait.
        //   Sa fonte d'interface ne suivait pas ⌘= — trois relances pour s'en
        //   convaincre. Un écran de moins est une divergence de moins.
        //
        // ⌘, reste : il désigne maintenant la ligne du bas au lieu d'ouvrir une
        // fenêtre. Le geste que le lecteur connaît mène au même endroit.
        .commands {
            // Le Mac attend qu'on puisse changer de thème au clavier — et
            // avec un kératocône, on en change souvent, selon la lumière de
            // la pièce. Le réglage existe déjà dans l'écran de lecture ; ce
            // raccourci le double, il ne le remplace pas.
            CommandGroup(after: .newItem) {
                // **Le mode vault n'apparaît que là où il peut marcher.**
                //
                // Il a besoin du pipeline embarqué, et `livrer-le-mac.sh` ne
                // l'embarque que pour le canal interne. Proposer l'entrée dans
                // une livraison qui ne l'a pas, c'était promettre puis répondre
                // « pipeline non embarqué » — mesuré sur le build 260831.1425,
                // installé depuis TestFlight.
                if ModeVault.pipelineEmbarque != nil {
                    Divider()
                    Button("Suivre un vault…") { choisirLeVault() }
                        .keyboardShortcut("o", modifiers: [.command, .shift])
                    if vault.vault != nil {
                        Button("Cesser de suivre") { vault.arreter() }
                    }
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
            // ── Le compte, là où macOS le cherche
            //
            // Il n'est ni le texte ni sa mise en page : c'est le lecteur
            // lui-même. ⌘, est la place que le système lui donne, et il vivait
            // dans « Présentation », où rien ne l'appelait.
            CommandGroup(replacing: .appSettings) {
                Button("Le compte") { etat.composition.router.tab = .you }
                    .keyboardShortcut(",", modifiers: .command)
            }

            // ── « Aller » — le corpus, et où l'on est dedans
            //
            // **⌘ nu suivi d'un chiffre veut dire « va là ».** C'est l'idiome
            // que toutes les apps à onglets emploient, et il laisse ⌥⌘ suivi
            // d'un chiffre libre pour ce qui *change le texte* — les niveaux.
            // Le même doigt, deux registres : ⌘2 ouvre Qahal, ⌥⌘2 éteint les
            // gloses, et les deux ne se confondent jamais.
            //
            // **Et le raccourci de l'onglet courant ramène à sa racine**, comme
            // un clic sur la ligne déjà choisie — c'est ce que `TabView` fait
            // sur iOS, et le geste doit être le même au clavier et à la souris.
            CommandMenu("Aller") {
                Button("Reprendre") { etat.composition.router.aller(a: .reprendre) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Qahal") { etat.composition.router.aller(a: .qahal) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Bible") { etat.composition.router.aller(a: .bible) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Lexique") { etat.composition.router.aller(a: .lexicon) }
                    .keyboardShortcut("4", modifiers: .command)

                Divider()
                // ⌘[ est le retour de Safari, du Finder et de Xcode. On dépile
                // le chemin de la Bible plutôt que d'inventer une notion de
                // « précédent » que l'app n'a pas.
                Button("Revenir") {
                    if !etat.composition.router.biblePath.isEmpty {
                        etat.composition.router.biblePath.removeLast()
                    }
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(etat.composition.router.biblePath.isEmpty)
            }

            // ── « Le texte » — les trois niveaux, et la langue des noms
            //
            // **Les libellés sont ceux de l'écran de réglages, au mot près.**
            // Deux formulations pour un même réglage obligent le lecteur à
            // deviner qu'il s'agit du même, et elles finissent par diverger.
            //
            // ⌥⌘2 et ⌥⌘3 parce que c'est ainsi que le projet nomme ces
            // niveaux — « 2, la voix du projet », « 3, translittération et
            // hébreu ». Le chiffre est déjà dans le vocabulaire de qui lit ce
            // corpus ; une lettre serait un mnémonique de plus à retenir.
            //
            // Le **niveau 1 n'a pas d'entrée**, et c'est le point : le corps de
            // la traduction ne s'éteint pas. Un menu qui proposerait de le
            // masquer le ferait passer pour une option parmi d'autres.
            //
            // Et **pas ⌥⌘H pour l'hébreu**, si tentant soit-il : macOS le garde
            // pour « Masquer les autres ». Un raccourci qu'on croit libre et qui
            // ne l'est pas rend l'app muette sans rien dire.
            CommandMenu("Le texte") {
                Toggle("Gloses", isOn: etat.option(\.showGloss))
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Toggle("Translittération et hébreu", isOn: etat.option(\.showLevel3))
                    .keyboardShortcut("3", modifiers: [.command, .option])

                Divider()
                // Sous les niveaux et non avec eux : il ne change pas ce qui est
                // dit, mais le nom sous lequel on le cherche.
                Toggle("Le français reçu", isOn: etat.option(\.french))
                    .keyboardShortcut("f", modifiers: [.command, .option])
            }

            // ── « La lecture » — la forme que le texte prend sous l'œil
            //
            // **⌥⌘ bascule, ⌘⇧ règle par crans.** Les deux premiers s'allument
            // ou s'éteignent, avec leur coche ; les trois derniers se montent et
            // se descendent. Le modificateur dit lequel des deux avant même
            // qu'on lise l'entrée.
            //
            // Le corps du texte est ici et **la taille de l'interface ne l'est
            // pas** : deux gestes pour deux choses. On monte le corps très haut
            // pour lire, sans vouloir qu'une barre latérale enfle et mange la
            // place de ce texte.
            CommandMenu("La lecture") {
                Toggle("Versets à la suite", isOn: etat.option(\.continuous))
                    .keyboardShortcut("v", modifiers: [.command, .option])
                Toggle("Couper les mots", isOn: etat.option(\.hyphenation))
                    .keyboardShortcut("c", modifiers: [.command, .option])

                Divider()
                // **`=` et non `+`.** `⌘⇧+` demanderait Maj deux fois, ce qui ne
                // se tape pas : `⌘⇧=` est la frappe qui produit ce que tout le
                // monde appelle « ⌘⇧+ ».
                Button("Agrandir le texte") { etat.corps(de: 1) }
                    .keyboardShortcut("=", modifiers: [.command, .shift])
                Button("Réduire le texte") { etat.corps(de: -1) }
                    .keyboardShortcut("-", modifiers: [.command, .shift])

                Divider()
                // Le thème se change souvent — avec un kératocône, selon la
                // lumière de la pièce. Le réglage existe dans l'écran de
                // lecture ; ce raccourci le double, il ne le remplace pas.
                Button("Thème suivant") { etat.themeSuivant() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Button("Police suivante") { etat.policeSuivante() }
                    .keyboardShortcut("p", modifiers: [.command, .option])
            }

            // ── Présentation — la fenêtre, qui n'est ni le corpus ni sa lecture
            //
            // Ce qui reste ici ne touche pas au texte : ce sont les meubles.
            // **⌘ nu suivi d'une lettre ou d'un signe**, comme partout ailleurs
            // sur macOS.
            //
            // **Un seul `CommandGroup` à cet ancrage**, et non plusieurs : deux
            // groupes déclarés au même endroit se disputent la place, et l'un
            // des deux peut ne paraître nulle part — un raccourci qu'on croit
            // posé et qui n'existe pas. Les menus ci-dessus n'ont pas ce
            // problème : `CommandMenu` crée le sien.
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
                // là qu'une fois qu'on en a ouvert une. Le menu l'annonce avant.
                Button(etat.modeDeFiche.titreDeBascule) {
                    etat.modeDeFiche = etat.modeDeFiche.suivant
                }
                .keyboardShortcut("i", modifiers: [.command, .option])

                Divider()
                // **`=` et non `+`, et ce n'est pas un détail de forme.**
                //
                // Sur un clavier français, `+` s'obtient par Maj+`=`. Un
                // raccourci déclaré `⌘+` **sans** Maj ne peut donc correspondre
                // à aucune frappe réelle : le système livre « + » avec Maj, la
                // déclaration attend « + » sans, et rien ne se produit jamais.
                //
                // C'est ce que l'auteur constatait — « ⌘+ ne marche toujours
                // pas ». Le raccourci n'était pas cassé, il était **intypable**.
                Button("Agrandir l'interface") { etat.interface(de: 1) }
                    .keyboardShortcut("=", modifiers: .command)
                Button("Réduire l'interface") { etat.interface(de: -1) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Taille d'interface par défaut") { etat.interfaceParDefaut() }
                    .keyboardShortcut("0", modifiers: .command)
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
/// L'état du mode vault, en bas de fenêtre et non en alerte : il change à
/// chaque sauvegarde, et une alerte par phrase rendrait l'app inutilisable
/// pendant qu'on écrit.
///
/// **Monté par `RacineMac` et non par la scène.** Attaché en `safeAreaInset`
/// au-dessus de la vue, il vivait hors du `.ontTheme(…)` — donc sans les
/// couleurs du lecteur — et son encart n'atteignait pas la colonne latérale :
/// il recouvrait « Vous » au lieu de la remonter.
struct BandeauDuVault: View {
    let mode: ModeVault
    @Environment(\.ontTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbole).foregroundStyle(theme.accent)
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
        // **Les couleurs du lecteur, pas celles du système.**
        //
        // `.bar` posait un matériau gris dans une app dont le thème mystique
        // est or sur bordeaux : la bande jurait avec tout ce qu'elle bordait.
        // `surface` et `accent` la font suivre le thème, quel qu'il soit.
        .foregroundStyle(theme.ink)
        .background(theme.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.separator).frame(height: 1)
        }
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

/// Le délégué d'application — les liens, et le jeton d'appareil.
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
    private let journal = Logger(subsystem: "com.labibleont.ONT.mac", category: "push")

    /// **La fenêtre posée à une taille exacte, pour les captures de l'App Store.**
    ///
    /// Apple n'accepte que quatre tailles pour macOS — 1280 × 800, 1440 × 900,
    /// 2560 × 1600, 2880 × 1800 — et il n'existe **pas de simulateur macOS** :
    /// l'app tourne nativement, donc la capture est celle de la vraie fenêtre.
    /// Une fenêtre de 1440 × 900 points capturée en Retina rend 2880 × 1800,
    /// c'est-à-dire une taille acceptée, sans redimensionner après coup.
    ///
    /// ## Pourquoi un argument de lancement
    ///
    /// C'est ce que fait déjà `scripts/captures.sh` pour l'iPhone, avec
    /// `-ouvrir`. Et les deux autres voies sont fermées ici : `osascript` n'a
    /// pas l'accessibilité sur la machine de l'auteur, et les préférences de
    /// cadre de SwiftUI sont des clés de neuf cents caractères qui portent
    /// l'arbre de vues entier — écrire dedans, c'est parier sur une chaîne qui
    /// change à chaque modificateur ajouté.
    ///
    /// AppKit fait le reste : un argument `-clé valeur` au lancement devient un
    /// `UserDefaults`. Rien à analyser.
    ///
    ///     open -a "La Bible ONT" --args -tailleDeCapture 1440x900
    ///
    /// Sans l'argument, la méthode ne fait rien — aucun lecteur ne rencontre ce
    /// chemin.
    func applicationDidFinishLaunching(_ notification: Notification) {
        poserLaTailleDeCapture()
        // **Personne n'a le focus à l'ouverture.** Le premier répondeur de la
        // fenêtre recevait l'anneau du système — d'abord la carte « Reprendre »,
        // puis, celle-ci l'ayant décliné, le bouton de barre d'outils : un
        // cerceau mauve autour du commutateur de barre latérale, dès le
        // lancement, sur les captures de l'auteur comme sur les nôtres. Une
        // liseuse s'ouvre sur du texte, pas sur un anneau.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.windows.first(where: { $0.canBecomeMain })?.makeFirstResponder(nil)
        }
    }

    /// **Reposée à chaque fois, et pas seulement au lancement.**
    ///
    /// Avec **Stage Manager** actif, envoyer une `ont://` à une app déjà
    /// lancée gare sa fenêtre : elle devient une vignette en perspective de
    /// 115 × 128, et `CGWindowList` rapporte la vignette comme si c'était la
    /// fenêtre. Une capture prise là est nette, bien formée, et fausse.
    ///
    /// On ne touche pas au réglage de la machine pour autant — ce serait
    /// changer l'environnement de quelqu'un pour arranger un script. L'app se
    /// remet elle-même au premier plan et retrouve sa taille, sur ce seul
    /// chemin.
    private func poserLaTailleDeCapture() {
        guard let demande = UserDefaults.standard.string(forKey: "tailleDeCapture") else { return }
        let bouts = demande.split(separator: "x")
        guard bouts.count == 2,
            let largeur = Double(bouts[0]), let hauteur = Double(bouts[1])
        else { return }

        // Après le tour de boucle courant : au lancement la fenêtre n'existe pas
        // encore, et à l'ouverture d'une URL elle n'a pas fini d'être dégarée.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.activate()
            guard let fenetre = NSApp.windows.first(where: { $0.canBecomeMain }) else { return }
            fenetre.orderFrontRegardless()
            // **La taille de capture ne se mémorise pas.** Elle se posait, et
            // la restauration d'état la gardait : après une campagne de
            // captures, les lancements *normaux* de l'auteur rouvraient en
            // 1440 × 900 — le format d'App Store — au lieu du 1240 × 960 par
            // défaut. C'est comme ça que « la fenêtre n'a pas le bon ratio »
            // est revenu alors que `defaultSize` était juste.
            fenetre.isRestorable = false
            var cadre = fenetre.frame
            cadre.size = NSSize(width: largeur, height: hauteur)
            fenetre.setFrame(cadre, display: true)
            fenetre.center()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            for url in urls { EtatMac.partage.composition.router.open(url) }
        }
        // Sans effet hors du chemin des captures — voir plus haut.
        poserLaTailleDeCapture()
    }

    /// **La seconde raison d'avoir un délégué, et elle est de même nature.**
    ///
    /// SwiftUI n'expose pas plus le jeton d'appareil qu'il n'expose l'ouverture
    /// d'une URL : `didRegisterForRemoteNotificationsWithDeviceToken` est une
    /// méthode d'`NSApplicationDelegate`, et le système n'a pas d'autre voie
    /// pour le rendre. C'est le même délégué et la même leçon — ce qui est en
    /// jeu appartient au système, pas à l'app.
    func application(
        _ application: NSApplication,
        didRegisterForRemoteNotificationsWithDeviceToken jeton: Data
    ) {
        Task { await PushDistant.enregistrer(jeton) }
    }

    /// L'échec est **silencieux pour le lecteur**, et tracé pour nous.
    ///
    /// Il arrive pour des raisons qui ne le concernent pas — pas de réseau au
    /// lancement, capacité Push absente du profil, machine non enregistrée dans
    /// le compte développeur. Lui montrer une alerte reviendrait à lui
    /// reprocher notre configuration.
    ///
    /// C'est le cas courant sur cette machine aujourd'hui, et ce le restera
    /// tant qu'elle n'est pas enregistrée : sans profil, pas de droit
    /// `aps-environment` dans le binaire, donc pas de jeton.
    func application(
        _ application: NSApplication,
        didFailToRegisterForRemoteNotificationsWithError erreur: Error
    ) {
        journal.error("inscription aux notifications refusée — \(erreur.localizedDescription)")
    }
}
