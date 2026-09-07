import LexiconFeature
import ONTDesignSystem
import ONTKit
import QahalFeature
import ReadingFeature
import SearchFeature
import SwiftUI
import YouFeature

/// La racine de l'app.
///
/// Quatre onglets. **Qahal** (קָהָל — l'assemblée) porte la part
/// communautaire ; **Bible** la lecture ; **Lexique** les intraduisibles ;
/// **Vous** le compte.
///
/// La `TabView` d'iOS 26 rend le Liquid Glass nativement — c'est ce qu'on ne
/// pouvait pas obtenir sans passer par SwiftUI.
///
/// ## Sur iPad, la barre se range sur le côté
///
/// `.sidebarAdaptable` — la même bascule que Music : sur iPhone, la barre
/// flottante ne bouge pas ; sur iPad, un bouton la change en barre latérale.
/// Et la barre latérale a de la place pour ce que quatre onglets ne peuvent
/// pas porter : les livres, directement.
struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(ReadingModel.self) private var reading
    @Environment(Composition.self) private var composition
    @Environment(\.horizontalSizeClass) private var largeur
    @State private var compteOuvert = false

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.tab) {
            OngletsFixes(
                enBarreLaterale: largeur == .regular,
                appliquer: appliquer,
                appliquerParutions: appliquerParutions)
            ForEach(corpusEnBarreLatérale) { corpus in
                RayonDeLivres(titre: corpus.title, livres: livresRédigés(de: corpus))
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // **Le compte en bas de la barre, comme Apple Music.**
        //
        // `tabViewSidebarBottomBar` est la seule façon d'épingler quelque chose
        // sous les onglets sans quitter la barre du système. Un `Tab` ne peut
        // pas y descendre : il prend sa place dans la liste, et c'est elle qui
        // l'ordonne — c'est ce qui a fait échouer les deux tentatives d'avant.
        //
        // Il ouvre une **feuille** plutôt que de désigner un onglet. Deux
        // raisons : « Vous » n'existe plus comme onglet en largeur régulière,
        // donc une sélection ne mènerait nulle part ; et un compte se consulte
        // puis se referme, il n'est pas un endroit où l'on reste. C'est aussi
        // ce que fait Music.
        .tabViewSidebarBottomBar {
            LigneDuCompte { compteOuvert = true }
        }
        .sheet(isPresented: $compteOuvert) {
            NavigationStack {
                YouTab(onDailyChange: appliquer, onParutions: appliquerParutions)
            }
            .ontTheme(from: reading.preferences)
        }
        // Un onglet-livre peut cesser d'exister sous les pieds du lecteur :
        // l'app passe en Split View, ou le livre choisi hier n'est plus au
        // corpus. La `TabView` n'aurait alors plus rien à afficher pour la
        // sélection enregistrée. On le ramène dans l'onglet Bible, à l'endroit
        // où il était — plutôt qu'un écran vide.
        .onChange(of: largeur, initial: true) { rabattreLOngletLivre() }
        // Le thème découle des réglages du lecteur, et suit Dynamic Type.
        .ontTheme(from: reading.preferences)
        // Jost dans les barres de navigation, comme le site. Une seule fois, à
        // la racine : le proxy d'apparence d'UIKit est global, l'appliquer plus
        // bas le ferait poser autant de fois qu'il y a d'écrans.
        .ontNavigationChrome()
        // Toucher un intraduisible n'ouvre pas une page : ça soulève une fiche
        // par-dessus la lecture, qu'on referme sans perdre sa place.
        .environment(\.openURL, OpenURLAction { url in
            router.open(url) ? .handled : .systemAction
        })
        .onOpenURL { router.open($0) }
        // ## Le thème est reposé **dans** la feuille, et il le faut
        //
        // Une feuille hérite de l'environnement de l'endroit où elle est
        // déclarée. Déclarée ici, au-dessus de `.ontTheme`, elle partait avec le
        // thème **par défaut** et le schéma **du système** : fond parchemin sous
        // des listes gris sombre, encre sombre sur fond sombre. Illisible, et
        // invisible à la relecture — le code disait bien `.ontTheme`, il le
        // disait juste à un rang que la feuille ne voyait pas.
        //
        // On a essayé de tout envelopper en remontant le thème au-dessus de la
        // feuille. Ça règle la feuille, et ça casse le reste : mesuré, le
        // parchemin sortait alors à (78,77,74) au lieu de (250,245,235), soit
        // trente pour cent de sa clarté. Un `preferredColorScheme` posé au
        // sommet ne se comporte pas comme un posé sous les onglets.
        //
        // On repose donc le thème là où il manque, plutôt que de déplacer celui
        // qui marche.
        // **Sur le Mac, une fiche est un panneau, pas une feuille.**
        //
        // Une feuille modale couvre le texte et interdit d'y revenir sans la
        // fermer. C'est le bon geste sur un téléphone, où il n'y a de place que
        // pour une chose à la fois. Sur un bureau, la place existe : on consulte
        // un nom **sans perdre sa ligne**, et l'on compare la fiche au verset
        // qui l'a fait ouvrir.
        //
        // Un `#if` et non une intention de `ONTPlateformes` : ce n'est pas la
        // même chose nommée deux fois, c'est un autre geste. Le code doit
        // montrer qu'on a décidé.
        .sheet(item: $router.openedLemma) { selection in
            TermSheet(lemma: selection.id)
                .ontTheme(from: reading.preferences)
        }
        // **Deux feuilles et non une.** Un nom propre et un intraduisible ne
        // vivent pas dans le même fichier, et une feuille commune devrait
        // deviner lequel des deux on vient de toucher — elle se tromperait pour
        // tout nom dont un concept porte le lemme.
        .sheet(item: $router.openedShem) { selection in
            ShemSheet(lemma: selection.id, shemot: composition.shemotSurDisque)
                .ontTheme(from: reading.preferences)
        }
    }

    /// Le seul endroit qui connaît `UserNotifications`.
    ///
    /// La feature ne fait que dire « le lecteur a changé d'avis ».
    private func appliquer(_ schedule: DailyVerseSchedule) async -> Bool {
        guard schedule.enabled else {
            await DailyVerseNotifications.reschedule(schedule, pool: composition.dailyPool)
            return true
        }
        guard await DailyVerseNotifications.requestAuthorization() else { return false }
        await DailyVerseNotifications.reschedule(schedule, pool: composition.dailyPool)
        return true
    }

    /// Le lecteur a changé d'avis sur les parutions.
    ///
    /// Activer demande l'autorisation puis enregistre le jeton ; couper
    /// l'efface du serveur avant de se désabonner d'Apple. L'ordre compte : se
    /// désabonner d'abord laisserait un jeton mort dans la table jusqu'à ce
    /// qu'une diffusion le heurte.
    private func appliquerParutions(_ actif: Bool) async -> Bool {
        // **iOS seulement.** Les notifications distantes passent par APNs et
        // un jeton d'appareil ; le Mac les gère autrement, et une liseuse de
        // bureau n'en a pas besoin pour rendre son service. On rend `false` :
        // le réglage ne s'allume pas, plutôt que de prétendre qu'il l'est.
        #if os(iOS)
            guard actif else {
                await PushDistant.desactiver()
                return true
            }
            return await PushDistant.activer()
        #else
            return false
        #endif
    }

    /// Les corpus à poser dans la barre latérale — aucun en largeur compacte.
    ///
    /// Seulement ceux qui ont un livre à proposer : un en-tête « Berit
    /// Hadashah » suivi de rien annoncerait un rayon vide. La table des
    /// matières, elle, garde ses soixante-dix slots — c'est là que la forme du
    /// corpus se lit, barre latérale ou pas.
    private var corpusEnBarreLatérale: [Corpus] {
        guard largeur == .regular else { return [] }
        return reading.corpora.filter { !livresRédigés(de: $0).isEmpty }
    }

    /// Les livres rédigés d'un corpus, dans l'ordre des slots.
    private func livresRédigés(de corpus: Corpus) -> [BookOutline] {
        corpus.modes
            .sorted { $0.order < $1.order }
            .flatMap(\.books)
            .filter { !$0.empty }
    }

    /// Ramène une sélection de livre dans l'onglet Bible quand la barre
    /// latérale n'est plus là pour la porter.
    private func rabattreLOngletLivre() {
        // **« Reprendre » disparaît avec la barre latérale.**
        //
        // Passer d'un iPad à une Split View étroite retire l'onglet sous les
        // pieds du lecteur, et le réglage enregistré peut aussi la désigner en
        // venant du Mac. Dans les deux cas la `TabView` n'aurait rien à
        // afficher. On la ramène sur la Bible, où la carte l'attend.
        if router.tab == .reprendre, largeur == .compact {
            router.tab = .bible
            return
        }
        guard let livre = router.tab.bookId else { return }
        // `.compact` explicitement, jamais `!= .regular` : au premier passage
        // la classe de largeur est encore `nil`, et rabattre là-dessus, c'est
        // renvoyer sur la Bible un lecteur qui avait quitté l'app sur un livre.
        let disparu = largeur == .compact
            || !reading.writtenBooks.contains { $0.id == livre }
        guard disparu else { return }

        router.tab = .bible
        // Seulement si le livre existe encore : sinon on pousserait le lecteur
        // sur un « Livre introuvable » qu'il n'a pas demandé.
        if reading.outline(livre) != nil {
            router.biblePath = [.book(livre)]
        }
    }
}


/// Le compte, en bas de la barre latérale.
///
/// Le nom du lecteur quand il en a donné un, « Vous » sinon — voir
/// `Profil.nomDeBarre`. Ce n'est pas une coquetterie : une barre qui dit
/// « Vous » à quelqu'un dont on connaît le prénom lui demande de se rappeler
/// qu'il est connecté, alors qu'on avait l'information sous la main.
private struct LigneDuCompte: View {
    let action: () -> Void

    @Environment(AccountModel.self) private var compte
    @Environment(\.ontTheme) private var theme
    private var espace = ONTSpacing()

    init(action: @escaping () -> Void) { self.action = action }

    var body: some View {
        Button(action: action) {
            HStack(spacing: espace.s) {
                Portrait(profil: compte.profil, octets: compte.portrait(), taille: 26)
                Text(compte.profil.nomDeBarre).lineLimit(1)
                    .font(ONTUI.ligneDeListe)
                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.ink)
            .padding(.horizontal, espace.m)
            .padding(.vertical, espace.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Les quatre onglets de toujours.
///
/// Un type nommé, et pas un bloc dans le `body` : écrit d'un seul tenant, le
/// vérificateur de types renonçait — « unable to type-check this expression in
/// reasonable time », puis « failed to produce diagnostic ». Ça passait ici
/// sous Xcode 27 et échouait sous le 26.3 de l'intégration continue : la
/// limite est un budget de temps, donc elle dépend de la machine, et on ne
/// l'apprend que sur la plus lente.
///
/// Un `TabContent` avec son `body` déclaré ne laisse plus rien à deviner :
/// chaque morceau est résolu pour lui-même, jamais dans le même souffle que
/// les autres.
private struct OngletsFixes: TabContent {
    /// Vrai quand la barre latérale est déployée — l'iPad, pas l'iPhone.
    let enBarreLaterale: Bool
    
    @Environment(AccountModel.self) private var compte

    let appliquer: (DailyVerseSchedule) async -> Bool
    let appliquerParutions: (Bool) async -> Bool

    var body: some TabContent<Router.TabID> {
        // **« Reprendre » en tête — un `Tab` nu, jamais une `TabSection`.**
        //
        // Elle a été rendue **cinquième** une soirée durant, alors qu'elle était
        // déclarée la première. La cause n'était pas l'onglet : c'était la
        // `TabSection` sans titre qui l'enveloppait, pour poser un filet.
        // `.sidebarAdaptable` hisse les `Tab` isolés **au-dessus** des sections,
        // quel que soit l'ordre d'écriture — et la section dessinait en prime
        // son bouton de repli, un chevron nu flottant sous « Vous ».
        //
        // Sans elle, l'ordre déclaré est l'ordre rendu : les cinq onglets sont
        // alors du même rang. On perd le filet, et c'est le prix — cette barre
        // appartient au système, on ne lui dicte pas sa mise en ordre. On peut
        // seulement cesser de la contrarier.
        //
        // **En largeur régulière seulement.** Sur un iPhone, la barre flottante
        // n'a de place que pour quatre onglets ; un cinquième rétrécirait les
        // autres, et « Reprendre » y est déjà une carte en tête de la Bible.
        if enBarreLaterale {
            Tab(
                "Reprendre", systemImage: "bookmark.fill",
                value: Router.TabID.reprendre
            ) {
                RepriseDeLecture()
            }
        }
        Tab("Qahal", systemImage: "person.2.fill", value: Router.TabID.qahal) {
            QahalTab()
        }
        Tab("Bible", systemImage: "book.closed.fill", value: Router.TabID.bible) {
            BibleTab { SearchView() }
        }
        Tab("Lexique", systemImage: "character.book.closed.fill", value: Router.TabID.lexicon) {
            LexiconTab()
        }
        // **« Vous » n'est un onglet que sur l'iPhone.**
        //
        // En barre latérale, il est épinglé **en bas** — voir
        // `tabViewSidebarBottomBar` sur la racine. C'est la place qu'Apple Music
        // lui donne sur iPad, et ce n'est pas une convention arbitraire : le
        // compte n'est pas une destination parmi les livres, c'est *qui
        // regarde*. Il ne défile donc pas avec eux, et reste atteignable de
        // n'importe quel endroit du corpus.
        //
        // Le laisser **aussi** dans la liste le montrerait deux fois.
        if !enBarreLaterale {
            // **Le portrait dans l'onglet, quand il y en a un.**
            //
            // Un lecteur connecté doit se reconnaître dans sa barre. Mais une
            // barre d'onglets veut une `Image`, pas une vue — voir
            // `PortraitDOnglet` : lui donner autre chose ne produit pas une
            // erreur, ça produit un onglet **sans icône**, mesuré à l'écran.
            //
            // Sans portrait, le symbole du système : c'est la bonne icône pour
            // qui n'a pas de compte, et le système sait l'animer.
            if let rond = PortraitDOnglet.rond(compte.portrait()) {
                Tab(value: Router.TabID.you) {
                    YouTab(onDailyChange: appliquer, onParutions: appliquerParutions)
                } label: {
                    Label { Text("Vous") } icon: { rond }
                }
            } else {
                Tab(
                    "Vous", systemImage: "person.crop.circle.fill",
                    value: Router.TabID.you
                ) {
                    YouTab(onDailyChange: appliquer, onParutions: appliquerParutions)
                }
            }
        }
    }
}

/// Un corpus et ses livres, tels qu'ils paraissent dans la barre latérale.
private struct RayonDeLivres: TabContent {
    let titre: String
    let livres: [BookOutline]

    var body: some TabContent<Router.TabID> {
        TabSection(titre) {
            ForEach(livres) { livre in
                Tab(
                    livre.title,
                    systemImage: "book.pages",
                    value: Router.TabID.book(livre.id)
                ) {
                    BookTab(bookId: livre.id)
                }
            }
        }
    }
}
