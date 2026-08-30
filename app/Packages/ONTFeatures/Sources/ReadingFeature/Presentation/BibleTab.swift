import ONTDesignSystem
import ONTKit
import SwiftUI

/// L'onglet de lecture — la table des matières des 70 slots, puis le texte.
///
/// L'ordre affiché est l'ordre **fonctionnel** du `corpus-order.md`, pas
/// l'alphabétique. Les slots encore vides restent visibles : le corpus est un
/// projet en cours, et les masquer donnerait une fausse idée de sa forme.
public struct BibleTab: View {
    @Environment(\.ontTheme) private var theme
    @Environment(ReadingModel.self) private var model
    @Environment(Router.self) private var router

    var spacing = ONTSpacing()

    /// Ce que la barre d'outils propose d'ouvrir — injecté par l'app pour que
    /// la lecture n'ait pas à connaître la feature de recherche.
    private let search: () -> AnyView

    public init<Search: View>(@ViewBuilder search: @escaping () -> Search) {
        self.search = { AnyView(search()) }
    }

    @State private var searching = false

    public var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.biblePath) {
            List {
                if let position = model.position {
                    Section {
                        ResumeRow(position: position) {
                            // Le verset, explicitement : « Reprendre » promet
                            // de rendre l'endroit, pas le chapitre. Il était
                            // omis, et la vue devait le retrouver toute seule
                            // dans la position enregistrée — un détour qui
                            // n'avait aucune raison d'exister.
                            router.open(
                                book: position.bookId,
                                chapter: position.chapterId,
                                verse: position.verse
                            )
                        }
                        .ontRow()
                    }
                }

                ForEach(model.corpora) { corpus in
                    Section {
                        ForEach(corpus.modes.sorted(by: { $0.order < $1.order })) { mode in
                            DisclosureGroup {
                                ForEach(disposer(mode)) { element in
                                    switch element.contenu {
                                    case .entete(let groupe):
                                        ConteneurLabel(groupe: groupe)
                                    case .livre(let book):
                                        BookRow(book: book)
                                    }
                                }
                            } label: {
                                ModeLabel(mode: mode)
                            }
                            .ontRow()
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(corpus.title)
                                .font(.custom(ONTFonts.display, size: 15))
                                .textCase(nil)
                                .foregroundStyle(ONTColors.brandInk(theme.mode))
                            // Le second nom, dans le registre choisi. Rien ne
                            // s'affiche quand il n'y a rien à dire — une
                            // section dont la glose redirait le pont n'en
                            // porte pas.
                            if let second = Registre.second(french: corpus.french, glose: corpus.glose, francaisRecu: model.preferences.french) {
                                Text(second)
                                    .font(ONTUI.caption)
                                    .textCase(nil)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .listStyle(ONTPlacement.listeGroupee)
            .ontScreen()
            .navigationTitle("La Bible ONT")
            .toolbar {
                ToolbarItem(placement: ONTPlacement.principale) {
                    Button("Rechercher", systemImage: "magnifyingglass") { searching = true }
                }
            }
            .sheet(isPresented: $searching) { search() }
            .navigationDestination(for: Router.Destination.self) { destination in
                switch destination {
                case .book(let id):
                    BookView(bookId: id)
                case .chapter(let book, let chapter):
                    ChapterLoader(bookId: book, chapterId: chapter)
                case .verses(let book, let chapter):
                    // **Le lecteur choisit où commencer avant d'ouvrir.**
                    //
                    // La sortie courte — « Tout le chapitre » — est en tête de
                    // cet écran, donc lire de bout en bout coûte un geste de
                    // plus qu'avant. C'est le prix demandé, et il achète la
                    // chose que le sommaire ne savait pas faire : arriver à un
                    // verset précis sans traverser la page pour le trouver.
                    ChoixDuVerset(book: book, chapter: chapter) { verse in
                        router.open(book: book, chapter: chapter, verse: verse)
                    }
                }
            }
        }
        .ontColumn()
    }
}

private struct ResumeRow: View {
    @Environment(\.ontTheme) private var theme
    let position: ReadingPosition
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            LabeledContent {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(ONTColors.accent(theme.mode))
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reprendre").font(ONTUI.subheadline.weight(.medium))
                    Text("\(position.chapterTitle):\(position.verse)")
                        .font(ONTUI.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // Sans forme de contact, `.buttonStyle(.plain)` ne rend touchable
            // que ce qui est **dessiné**. Le blanc entre le libellé et l'icône
            // n'était donc pas une cible : le doigt tombait à côté neuf fois
            // sur dix, et seule l'icône répondait du premier coup.
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct ModeLabel: View {
    @Environment(ReadingModel.self) private var model
    let mode: Mode

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(mode.title).font(ONTUI.headline)
                if let second = Registre.second(french: mode.french, glose: mode.glose, francaisRecu: model.preferences.french) {
                    Text(second).font(ONTUI.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(mode.books.filter { !$0.empty }.count)/\(mode.books.count)")
                .font(ONTUI.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct BookRow: View {
    @Environment(ReadingModel.self) private var model
    let book: BookOutline

    var body: some View {
        if book.empty {
            LabeledContent {
                Text("à venir").font(ONTUI.caption).foregroundStyle(.tertiary)
            } label: {
                title
            }
        } else {
            NavigationLink(value: Router.Destination.book(book.id)) {
                LabeledContent {
                    Text("\(book.verseCount) v.")
                        .font(ONTUI.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } label: {
                    title
                }
            }
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text("\(book.slot)")
                    .font(ONTUI.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 20, alignment: .trailing)
                // Le nom hébreu translittéré est le vrai titre du livre (§2.6).
                Text(book.title)
                    .font(ONTUI.body.italic())
                    .foregroundStyle(book.empty ? .secondary : .primary)
            }
            // Le second nom, dans le registre choisi. Le français n'est qu'un
            // pont de navigation pour le lecteur occidental — jamais la
            // désignation principale.
            //
            // **C'est ici que le registre comptait le plus, et c'est ici qu'il
            // manquait.** Les corpus et les modes tiennent en huit lignes ; les
            // livres en soixante-dix, et ce sont eux qu'on parcourt. Registre
            // éteint, la liste disait encore « Actes des Apôtres » là où le
            // site disait « les gevurot de YHWH par ses neviim ».
            if let second = Registre.second(french: book.french, glose: book.glose, francaisRecu: model.preferences.french) {
                Text(second)
                    .font(ONTUI.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 28)
            }
        }
    }
}

/// La liste des unités d'un livre.
struct BookView: View {
    @Environment(ReadingModel.self) private var model
    let bookId: String

    /// L'unité dont on choisit le verset, quand on a touché son nombre.
    @State private var versetsDe: VersetsAChoisir?

    var body: some View {
        if let outline = model.outline(bookId) {
            list(outline)
        } else {
            ContentUnavailableView(
                "Livre introuvable",
                systemImage: "book.closed",
                description: Text("« \(bookId) » n'est pas dans le corpus.")
            )
        }
    }

    @ViewBuilder
    private func list(_ outline: BookOutline) -> some View {
        List {
            if let intro = outline.intro {
                Section("Introduction") {
                    NavigationLink(
                        value: Router.Destination.chapter(book: outline.id, chapter: intro.id)
                    ) {
                        Label(intro.title, systemImage: "text.book.closed")
                    }
                    .ontRow()
                }
            }

            // **« Unités » est le mot du pipeline**, pas celui du lecteur.
            //
            // Il est juste — une unité ONT se ferme quand une fonction
            // s'accomplit — mais il est interne, et il donnait un troisième nom
            // à ce que les lignes en dessous appellent déjà « Chapitre 3 » ou
            // « Parashah 3 ». Trois mots pour une chose, sur un écran dont tout
            // le propos est de n'en enseigner qu'un.
            Section(model.preferences.french ? "Chapitres" : "Parashiot") {
                ForEach(outline.chapters) { chapter in
                    // **Deux gestes, deux intentions.**
                    //
                    // Toucher la ligne ouvre l'unité — c'est ce qu'on veut neuf
                    // fois sur dix, et ça doit rester d'un seul doigt. Toucher
                    // le **nombre de versets** ouvre la grille et mène au
                    // verset choisi.
                    //
                    // Le nombre porte déjà ce sens : il dit combien il y en a.
                    // En faire la porte de « lequel » n'ajoute pas un objet à
                    // la ligne — il donne un office à celui qui y était.
                    //
                    // `.borderless` n'est pas cosmétique : dans une liste, un
                    // bouton de style ordinaire laisse la ligne entière capter
                    // le toucher, et le nombre ne répondrait jamais.
                    NavigationLink(
                        value: Router.Destination.verses(book: outline.id, chapter: chapter.id)
                    ) {
                        ChapterRow(stub: chapter) {
                            versetsDe = VersetsAChoisir(book: outline.id, chapter: chapter.id)
                        }
                    }
                    .ontRow()
                }
            }
        }
        .ontScreen()
        .navigationTitle(outline.title)
        // Le sous-titre de barre est arrivé avec iOS 26. En dessous, on n'a
        // rien à mettre à la place : le nom français figure déjà dans la ligne
        // du livre qu'on vient de toucher, et l'inventer ailleurs — un
        // deuxième titre sous le premier — ferait une barre plus haute pour
        // redire ce qu'on sait déjà. Le lecteur d'iOS 18 perd une redite,
        // pas un renseignement.
        .modifier(
            SousTitreDeBarre(
                texte: Registre.second(french: outline.french, glose: outline.glose, francaisRecu: model.preferences.french)
                    ?? outline.french
            )
        )
        // La grille des versets, ouverte **directement** — le lecteur vient de
        // choisir son livre et son unité dans la page qui est dessous ; les
        // deux premières étapes du sélecteur lui redemanderaient ce qu'il
        // vient de dire.
        .sheet(item: $versetsDe) { cible in
            ReferencePicker(book: cible.book, chapter: cible.chapter)
                .ontTheme(from: model.preferences)
        }
    }
}

/// `navigationSubtitle` quand le système sait le poser, rien sinon.
private struct SousTitreDeBarre: ViewModifier {
    let texte: String

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.navigationSubtitle(texte)
        } else {
            content
        }
    }
}

private struct ChapterRow: View {
    @Environment(ReadingModel.self) private var model
    let stub: ChapterStub

    /// Ce que fait le nombre de versets quand on le touche.
    let choisirUnVerset: () -> Void

    /// Le libellé de l'unité, dans le registre choisi — le calcul vit dans
    /// `ChapterStub` parce que le sélecteur de renvoi le fait aussi.
    private var libelle: String { stub.label(french: model.preferences.french) }

    private var nom: String {
        LibelleDUnite.nom(french: model.preferences.french)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(libelle)
                if let reference = stub.reference {
                    Text(reference).font(ONTUI.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if stub.status == .brouillon {
                // Le §12 est explicite : un brouillon ne fait pas référence.
                // Le lecteur doit le savoir avant de citer.
                StatusPill("brouillon")
            }
            // Le nombre de versets **devient une porte**.
            //
            // Il disait déjà « combien » ; il dit maintenant aussi « lequel ».
            // C'est le seul endroit de la ligne où un second geste ne coûte
            // aucun objet de plus — et le seul dont le sens y menait déjà.
            //
            // `.borderless` est ce qui le rend touchable : dans une liste, un
            // bouton de style ordinaire laisse la ligne capter tout le
            // toucher, et le nombre ne répondrait jamais.
            Button(action: choisirUnVerset) {
                HStack(spacing: 3) {
                    Text("\(stub.verseCount)").font(ONTUI.caption.monospacedDigit())
                    Image(systemName: "list.number").font(ONTUI.caption2)
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
                .padding(.leading, 8)
                .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Choisir un verset — \(stub.verseCount) dans ce \(nom)")
        }
    }
}

/// L'unité dont on est en train de choisir le verset.
///
/// Un type à part plutôt qu'un booléen et deux chaînes : la feuille n'a de sens
/// que si les trois sont là ensemble, et `Identifiable` fait que SwiftUI la
/// repose quand on change d'unité sans la refermer.
private struct VersetsAChoisir: Identifiable {
    let book: String
    let chapter: String
    var id: String { "\(book)/\(chapter)" }
}

/// Charge le livre à la demande, puis affiche l'unité voulue.
struct ChapterLoader: View {
    @Environment(ReadingModel.self) private var model
    let bookId: String
    let chapterId: String

    var body: some View {
        if let chapter = model.chapter(book: bookId, id: chapterId) {
            // `.id(chapter.id)` : une unité n'est pas l'autre.
            //
            // Sans ça, SwiftUI réutilise la même `ChapterView` d'un chapitre au
            // suivant et lui **conserve son état**. Le rang du bloc visé était
            // donc celui de l'unité précédente : `.scrollPosition` cherchait un
            // bloc qui n'existe pas ici, le défilement partait au-delà du
            // contenu, et la page s'affichait vide. C'est ce qu'on voyait en
            // arrivant depuis un résultat de recherche.
            // `ChapterSwipe` et non `ChapterView` : c'est lui qui porte le
            // geste horizontal, et qui décide quelle unité est affichée.
            ChapterSwipe(depart: chapter)
                .id(chapter.id)
        } else {
            ContentUnavailableView(
                "\(LibelleDUnite.nom(french: model.preferences.french).localizedCapitalized) introuvable",
                systemImage: "questionmark.text.page",
                description: Text("« \(chapterId) » n'est pas dans ce livre.")
            )
        }
    }
}

// MARK: - Les conteneurs, et la fracture du Ḥurban

/// Ce que la liste d'un mode pose l'un après l'autre.
private struct Element: Identifiable {
    enum Contenu {
        case entete(Conteneur)
        case livre(BookOutline)
    }
    let id: String
    let contenu: Contenu
}

/// Intercale les en-têtes de conteneur dans la suite des livres.
///
/// L'ordre vient des **livres**, jamais de la liste des conteneurs : c'est le
/// corpus qui décide où tombe une coupure. Un identifiant porté par un livre
/// sans déclaration est ignoré — une table des matières qui refuserait de se
/// rendre pour un ornement coûterait plus au lecteur qu'il ne lui apporte.
private func disposer(_ mode: Mode) -> [Element] {
    var sortie: [Element] = []
    var courant: String?
    for livre in mode.books {
        if livre.groupId != courant {
            courant = livre.groupId
            if let id = courant, let g = mode.groups.first(where: { $0.id == id }) {
                sortie.append(Element(id: "entete-\(id)", contenu: .entete(g)))
            }
        }
        sortie.append(Element(id: livre.id, contenu: .livre(livre)))
    }
    return sortie
}

/// L'en-tête d'un conteneur, et sa césure quand il en a une.
///
/// **Deux poids, deux traitements.** Un conteneur qui regroupe reçoit un
/// intertitre discret ; celui qui fracture reçoit d'abord un filet appuyé et la
/// ligne qui dit ce que la fracture change pour lire.
///
/// C'est le *Ḥurban*, et lui seul. `corpus-order.md` le nomme **pivot
/// herméneutique** : les lettres d'avant parlent du Temple au présent —
/// *Igeret HaIvrim* est « le dernier mot du Bayit vivant » ; trois numéros plus
/// loin, il n'existe plus.
private struct ConteneurLabel: View {
    @Environment(\.ontTheme) private var theme
    @Environment(ReadingModel.self) private var model
    let groupe: Conteneur

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let rupture = groupe.rupture {
                // **Le filet est en or, et c'est un revirement.**
                //
                // Il a d'abord été posé en accentuation, au motif que l'or dit
                // l'intraduisible partout ailleurs et qu'une règle horizontale
                // n'en est pas un. L'argument était juste sur le mot, faux sur
                // la page : l'accentuation est une couleur *de texte*, et un
                // filet bordeaux au milieu d'un sommaire se lit comme une
                // alerte — quelque chose ne va pas —, alors qu'il annonce une
                // charnière.
                //
                // L'or est la couleur de direction artistique du projet, celle
                // des filets et des cadres. C'est ce que le lecteur y attend.
                Rectangle()
                    .fill(ONTColors.accent(theme.mode).opacity(0.7))
                    .frame(height: 2)
                    .padding(.top, 8)
                Text(rupture)
                    .font(ONTUI.footnote.italic())
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
            }
            Text(groupe.title)
                .font(ONTUI.caption.smallCaps())
                .foregroundStyle(.secondary)
            Text(model.preferences.french ? groupe.french : (groupe.glose ?? groupe.french))
                .font(ONTUI.caption2)
                .foregroundStyle(.tertiary)
        }
        .listRowSeparator(.hidden)
    }
}

