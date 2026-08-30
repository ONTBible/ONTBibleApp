import LexiconFeature
import ONTDesignSystem
import ONTKit
import QahalFeature
import ReadingFeature
import SearchFeature
import SwiftUI
import YouFeature

/// La racine du Mac — une barre latérale que l'app dessine elle-même.
///
/// ## Pourquoi elle ne partage plus `RootView`
///
/// `RootView` monte une `TabView(.sidebarAdaptable)`, et c'est le bon objet sur
/// iPhone et iPad : la même barre s'y replie en onglets quand la place manque.
/// Sur le Mac, la place ne manque jamais, et cette barre-là **n'appartient pas
/// à l'app** — AppKit la dessine.
///
/// Trois défauts en découlaient, tous rapportés séparément, tous dus à ça :
///
/// - **la sélection sortait au rose vif.** `.tint()` ne l'atteint pas, et
///   `AccentColor` dans le catalogue non plus : quand le lecteur a choisi un
///   accent précis dans les Réglages du système — rose, ici —, macOS l'impose à
///   toutes les apps et ignore celui qu'elles déclarent. Une liseuse dont la
///   peau est or et bordeaux n'a aucun moyen de reprendre la main tant que ce
///   n'est pas elle qui peint ;
/// - **⌘= ne changeait rien.** Les libellés étaient rendus par AppKit, qui ne
///   lit pas le `dynamicTypeSize` de SwiftUI ;
/// - **la largeur ne se réglait pas.** `navigationSplitViewColumnWidth`
///   s'adresse à une colonne qu'on a déclarée, pas à celle qu'un style d'onglets
///   monte en interne.
///
/// J'ai corrigé les deux premiers séparément avant de voir qu'ils n'étaient
/// qu'un seul fait dit trois fois. Ce que le Mac demandait n'était pas une
/// teinte de plus : c'était de **dessiner sa propre barre**.
///
/// ## Ce que ça ne change pas
///
/// Le contenu. `QahalTab`, `BibleTab`, `LexiconTab`, `BookTab` et
/// `RepriseDeLecture` sont exactement les vues qu'iOS affiche, montées avec les
/// mêmes dépôts. Ce qui diverge ici est la **chrome** — et elle diverge parce
/// qu'un bureau et un téléphone ne naviguent pas pareil, pas par accident.
struct RacineMac: View {
    @Environment(Router.self) private var router
    @Environment(ReadingModel.self) private var reading
    @Environment(Composition.self) private var composition

    var body: some View {
        @Bindable var router = router

        NavigationSplitView {
            BarreLateraleONT()
                .navigationSplitViewColumnWidth(
                    min: 180,
                    ideal: Self.largeurDeBarreParDefaut,
                    max: 460)
        } detail: {
            Detail()
                .panneauDeFiche(shemot: composition.shemotSurDisque)
        }
        .navigationSplitViewStyle(.automatic)
        .ontTheme(from: reading.preferences)
        .ontNavigationChrome()
        // Toucher un intraduisible n'ouvre pas une page : ça soulève une fiche
        // par-dessus la lecture, qu'on referme sans perdre sa place.
        .environment(\.openURL, OpenURLAction { url in
            router.open(url) ? .handled : .systemAction
        })
        // Les liens `ont://` arrivent par `DelegueMac`, et non par
        // `onOpenURL` : celui-ci fait naître une seconde fenêtre.
        .onAppear { rabattreCeQuiNExistePas() }
        .onChange(of: reading.corpora.count) { rabattreCeQuiNExistePas() }
        .apercuDeFiche(shemot: composition.shemotSurDisque)
    }

    /// La largeur d'ouverture de la barre latérale, en points.
    ///
    /// Relevée sur la fenêtre que l'auteur a montrée en référence — 21 % d'une
    /// fenêtre de 1240 — et non choisie à l'œil : à la largeur que SwiftUI donne
    /// par défaut, « Toledot Adam ve-Chavah » sortait « Toledot A… ». Les noms
    /// des livres de l'ONT sont translittérés de l'hébreu et longs par nature ;
    /// la largeur doit être choisie pour eux.
    ///
    /// Ce qui suit l'ouverture ne nous regarde pas : AppKit enregistre lui-même
    /// la largeur donnée à la main, sous la clé « NSSplitView Subview Frames »
    /// des préférences — vérifié, elle y est. J'avais écrit une sonde pour la
    /// garder ; elle ne trouvait jamais rien, et elle était de toute façon
    /// inutile.
    static let largeurDeBarreParDefaut: CGFloat = 264

    /// Ramène la sélection sur la Bible quand ce qu'elle désigne a disparu.
    ///
    /// Deux cas : un livre retiré du corpus depuis la dernière session, et
    /// l'onglet « Vous » — qui n'existe pas ici, puisque le Mac met les réglages
    /// sous ⌘,. Sans ce rabattement, l'app rouvrirait sur un détail vide, et le
    /// lecteur n'aurait aucun moyen de comprendre pourquoi.
    private func rabattreCeQuiNExistePas() {
        switch router.tab {
        case .book(let id) where !reading.writtenBooks.contains(where: { $0.id == id }):
            router.tab = .bible
            if reading.outline(id) != nil { router.biblePath = [.book(id)] }
        default:
            break
        }
    }

    /// Le détail — la vue que la sélection désigne.
    private struct Detail: View {
        @Environment(Router.self) private var router

        var body: some View {
            switch router.tab {
            case .reprendre: RepriseDeLecture()
            case .qahal: QahalTab()
            case .bible: BibleTab { SearchView() }
            // Le compte, désigné par la ligne du bas ou par ⌘,. Les deux
            // fermetures rendent des valeurs fixes : le Mac ne programme pas de
            // verset quotidien et ne s'inscrit pas aux parutions — ce sont des
            // notifications d'appareil, et sa liseuse n'en pose pas.
            case .you:
                YouTab(onDailyChange: { _ in true }, onParutions: { _ in false })
            case .lexicon: LexiconTab()
            case .book(let id): BookTab(bookId: id)
            }
        }
    }
}
