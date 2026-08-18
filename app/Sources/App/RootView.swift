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

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.tab) {
            Tab("Qahal", systemImage: "person.2.fill", value: Router.TabID.qahal) {
                QahalTab()
            }
            Tab("Bible", systemImage: "book.closed.fill", value: Router.TabID.bible) {
                BibleTab { SearchView() }
            }
            Tab("Lexique", systemImage: "character.book.closed.fill", value: Router.TabID.lexicon) {
                LexiconTab()
            }
            Tab("Vous", systemImage: "person.crop.circle.fill", value: Router.TabID.you) {
                YouTab { schedule in
                    // Le seul endroit qui connaît `UserNotifications`. La
                    // feature ne fait que dire « le lecteur a changé d'avis ».
                    guard schedule.enabled else {
                        await DailyVerseNotifications.reschedule(schedule, pool: composition.dailyPool)
                        return true
                    }
                    guard await DailyVerseNotifications.requestAuthorization() else { return false }
                    await DailyVerseNotifications.reschedule(schedule, pool: composition.dailyPool)
                    return true
                }
            }

            // Les livres, seulement là où il y a une barre latérale pour les
            // recevoir. En largeur compacte — iPhone, ou iPad en Split View —
            // une `TabSection` retombe dans la barre du bas, et trois livres
            // de plus y feraient une barre débordée pour rien.
            //
            // Une liste vide, et non un `if` autour de la section : la classe
            // de largeur n'est pas encore connue au premier passage, donc un
            // `if` fait *apparaître* des onglets juste après le lancement. La
            // `TabView` perd alors la sélection qu'on lui avait donnée et
            // ouvre sur le premier livre — on lançait l'app sur « bible » et
            // elle s'ouvrait sur Bereshit. Avec un `ForEach` toujours présent,
            // seules les données changent, et la sélection tient.
            ForEach(corpusEnBarreLatérale) { corpus in
                TabSection(corpus.title) {
                    ForEach(livresRédigés(de: corpus)) { livre in
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
        .tabViewStyle(.sidebarAdaptable)
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
        .sheet(item: $router.openedLemma) { selection in
            TermSheet(lemma: selection.id)
                .ontTheme(from: reading.preferences)
        }
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

