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
    @Environment(ModeVault.self) private var vault

    var body: some View {
        @Bindable var router = router

        // **Une rangée et non un encart.**
        //
        // La bande du vault était posée en `safeAreaInset` **au-dessus** de
        // cette vue, depuis la scène. Deux conséquences, et la même cause :
        // elle vivait hors du `.ontTheme(…)`.
        //
        //   — elle portait le matériau gris du système dans une app dont le
        //     thème mystique est or sur bordeaux ;
        //   — et son encart n'atteignait pas la colonne latérale : elle
        //     **recouvrait « Vous »** au lieu de la remonter.
        //
        // Dans une `VStack`, elle occupe une place réelle — rien ne peut plus
        // se retrouver derrière elle — et elle hérite du thème du lecteur.
        VStack(spacing: 0) {
            NavigationSplitView {
                BarreLateraleONT()
                    .navigationSplitViewColumnWidth(
                        min: 180,
                        ideal: Self.largeurDeBarreParDefaut,
                        max: 460)
            } detail: {
                Detail()
                    // Les listes du détail reprennent la fonte du système à leurs
                    // lignes ; ces deux styles la leur rendent. Mesuré au pixel —
                    // voir `FonteDesListes`. Posé sur le détail et non sur toute la
                    // racine : la barre latérale déclare déjà ses fontes, et lui
                    // imposer un style de libellé changerait ce qu'elle a réglé.
                    .fonteDesListes()
                    .panneauDeFiche(shemot: composition.shemotSurDisque)
            }
            .navigationSplitViewStyle(.automatic)

            if vault.vault != nil { BandeauDuVault(mode: vault) }
        }
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
        @Environment(Composition.self) private var composition

        var body: some View {
            switch router.tab {
            case .reprendre: RepriseDeLecture()
            case .qahal: QahalTab()
            case .bible: BibleTab { SearchView() }
            // Le compte, désigné par la ligne du bas ou par ⌘,.
            case .you:
                YouTab(onDailyChange: programmerLeVerset, onParutions: appliquerLesParutions)
            case .lexicon: LexiconTab()
            case .book(let id): BookTab(bookId: id)
            }
        }

        /// Le verset du jour, programmé pour de bon.
        ///
        /// Les deux fermetures rendaient des valeurs fixes — `true` pour le
        /// verset, `false` pour les parutions — sur une note affirmant que « le
        /// Mac ne pose pas de notifications d'appareil ». **C'était une
        /// déclaration sans la chose** : `true` allumait un interrupteur qui ne
        /// programmait rien, et `false` en montrait un qui refusait de
        /// s'allumer sans que rien ne l'explique.
        ///
        /// Rien ne l'empêchait : `UserNotifications` existe sur macOS, et
        /// `DailyVerseNotifications` n'a jamais eu une ligne propre à iOS. Elle
        /// était déjà compilée dans cette cible ; personne ne l'appelait.
        private func programmerLeVerset(_ horaire: DailyVerseSchedule) async -> Bool {
            guard await DailyVerseNotifications.requestAuthorization() else { return false }
            await DailyVerseNotifications.reschedule(horaire, pool: composition.dailyPool)
            return true
        }

        /// Les parutions — le même chemin qu'iOS, au nom de l'application près.
        ///
        /// Couper efface le jeton du serveur **avant** de se désabonner
        /// d'Apple. L'ordre compte : se désabonner d'abord laisserait un jeton
        /// mort dans la table jusqu'à ce qu'une diffusion le heurte.
        private func appliquerLesParutions(_ actif: Bool) async -> Bool {
            guard actif else {
                await PushDistant.desactiver()
                return true
            }
            return await PushDistant.activer()
        }
    }
}
