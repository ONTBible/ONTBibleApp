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
        case .you:
            router.tab = .bible
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
            case .bible, .you: BibleTab { SearchView() }
            case .lexicon: LexiconTab()
            case .book(let id): BookTab(bookId: id)
            }
        }
    }
}

// MARK: - La barre latérale

/// La barre latérale de la liseuse, dessinée par l'app.
///
/// Une `List` et des lignes à nous, plutôt qu'une `List(selection:)` : la
/// sélection d'une liste système est peinte par AppKit avec l'accent du
/// système, ce qui est précisément ce qu'on vient de quitter. Le prix est de
/// dessiner soi-même l'état sélectionné et le survol ; le gain est que la barre
/// porte enfin la peau de l'app, et qu'elle suit le corps réglé au clavier.
private struct BarreLateraleONT: View {
    @Environment(Router.self) private var router
    @Environment(ReadingModel.self) private var reading
    @Environment(\.ontTheme) private var theme

    var body: some View {
        List {
            Section {
                LigneDeBarre(
                    cible: .reprendre, titre: "Reprendre", symbole: "bookmark.fill")
                LigneDeBarre(cible: .qahal, titre: "Qahal", symbole: "person.2.fill")
                LigneDeBarre(cible: .bible, titre: "Bible", symbole: "book.closed.fill")
                LigneDeBarre(
                    cible: .lexicon, titre: "Lexique",
                    symbole: "character.book.closed.fill")
            }
            // Seulement les corpus qui ont un livre à proposer : un en-tête
            // « Berit Hadashah » suivi de rien annoncerait un rayon vide.
            ForEach(corpusPeuplés) { corpus in
                Section(corpus.title) {
                    ForEach(livresRédigés(de: corpus)) { livre in
                        LigneDeBarre(
                            cible: .book(livre.id), titre: livre.title,
                            symbole: "book.pages")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        // Le fond de la liseuse, et non celui du système : une barre grise
        // contre un parchemin ferait deux apps dans une fenêtre.
        .scrollContentBackground(.hidden)
        .background(theme.background)
    }

    private var corpusPeuplés: [Corpus] {
        reading.corpora.filter { !livresRédigés(de: $0).isEmpty }
    }

    private func livresRédigés(de corpus: Corpus) -> [BookOutline] {
        corpus.modes
            .sorted { $0.order < $1.order }
            .flatMap(\.books)
            .filter { !$0.empty }
    }
}

/// Une ligne de la barre latérale.
///
/// Le libellé est en Jost, la fonte de titraille et de navigation du projet —
/// c'est la règle du site, que la barre d'AppKit ne pouvait pas suivre. Elle
/// vaut ici doublement : `Font.custom(_:size:)` suit Dynamic Type d'office,
/// là où un `.system(size:)` reste figé. La barre grandit donc avec ⌘=, ce
/// qu'on lui demandait depuis le début.
private struct LigneDeBarre: View {
    let cible: Router.TabID
    let titre: String
    let symbole: String

    @Environment(Router.self) private var router
    @Environment(\.ontTheme) private var theme
    @State private var survolée = false
    private var espace = ONTSpacing()
    private var échelle = ONTScaled()

    init(cible: Router.TabID, titre: String, symbole: String) {
        self.cible = cible
        self.titre = titre
        self.symbole = symbole
    }

    private var choisie: Bool { router.tab == cible }

    var body: some View {
        Button {
            router.tab = cible
        } label: {
            HStack(spacing: espace.s) {
                Image(systemName: symbole)
                    .font(.system(size: échelle(13)))
                    .frame(width: échelle(20))
                Text(titre)
                    .font(.custom(ONTFonts.display, size: ONTUI.points(14)))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(encre)
            .padding(.horizontal, espace.s)
            .padding(.vertical, espace.xs + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fond, in: .rect(cornerRadius: ONTRadius.highlight + 2))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .onHover { survolée = $0 }
        // Le survol se pose vite et se retire vite : au-delà, la barre traîne
        // derrière le curseur et donne l'impression que l'app rame.
        .animation(.easeOut(duration: 0.12), value: survolée)
        .animation(.easeOut(duration: 0.14), value: choisie)
    }

    /// L'aplat de marque quand la ligne est choisie ; un voile d'encre au
    /// survol, qui dit « on peut cliquer » sans annoncer une sélection.
    private var fond: Color {
        if choisie { return ONTColors.brandInk(theme.mode) }
        if survolée { return theme.ink.opacity(0.07) }
        return .clear
    }

    private var encre: Color {
        choisie ? ONTColors.onBrand(theme.mode) : theme.ink
    }
}
