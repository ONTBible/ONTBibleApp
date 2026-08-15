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

    private var spacing = ONTSpacing()

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
                                ForEach(mode.books) { book in
                                    BookRow(book: book)
                                }
                            } label: {
                                ModeLabel(mode: mode)
                            }
                            .ontRow()
                        }
                    } header: {
                        Text(corpus.title)
                            .font(.custom(ONTFonts.display, size: 15))
                            .textCase(nil)
                            .foregroundStyle(ONTColors.brandInk(theme.mode))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .ontScreen()
            .navigationTitle("La Bible ONT")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
                }
            }
        }
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
                    Text("Reprendre").font(.subheadline.weight(.medium))
                    Text("\(position.chapterTitle):\(position.verse)")
                        .font(.caption)
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
    let mode: Mode

    var body: some View {
        HStack {
            Text(mode.title).font(.headline)
            Spacer()
            Text("\(mode.books.filter { !$0.empty }.count)/\(mode.books.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct BookRow: View {
    let book: BookOutline

    var body: some View {
        if book.empty {
            LabeledContent {
                Text("à venir").font(.caption).foregroundStyle(.tertiary)
            } label: {
                title
            }
        } else {
            NavigationLink(value: Router.Destination.book(book.id)) {
                LabeledContent {
                    Text("\(book.verseCount) v.")
                        .font(.caption.monospacedDigit())
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
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 20, alignment: .trailing)
                // Le nom hébreu translittéré est le vrai titre du livre (§2.6).
                Text(book.title)
                    .font(.body.italic())
                    .foregroundStyle(book.empty ? .secondary : .primary)
            }
            // Le français n'est qu'un pont de navigation pour le lecteur
            // occidental — jamais la désignation principale.
            Text(book.french)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.leading, 28)
        }
    }
}

/// La liste des unités d'un livre.
struct BookView: View {
    @Environment(ReadingModel.self) private var model
    let bookId: String

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

            Section("Unités") {
                ForEach(outline.chapters) { chapter in
                    NavigationLink(
                        value: Router.Destination.chapter(book: outline.id, chapter: chapter.id)
                    ) {
                        ChapterRow(stub: chapter)
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
        .modifier(SousTitreDeBarre(texte: outline.french))
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
    let stub: ChapterStub

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(stub.title)
                if let reference = stub.reference {
                    Text(reference).font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if stub.status == .brouillon {
                // Le §12 est explicite : un brouillon ne fait pas référence.
                // Le lecteur doit le savoir avant de citer.
                StatusPill("brouillon")
            }
            Text("\(stub.verseCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
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
                "Unité introuvable",
                systemImage: "questionmark.text.page",
                description: Text("« \(chapterId) » n'est pas dans ce livre.")
            )
        }
    }
}
