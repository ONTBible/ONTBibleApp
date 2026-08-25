import ONTDesignSystem
import ONTKit
import SwiftUI

/// Le sélecteur de renvoi — livre, unité, verset.
///
/// Le geste de YouVersion et de Bible Strong : une pastille en haut à gauche
/// qui dit où l'on est, et qu'on touche pour aller ailleurs. Trois étapes,
/// parce qu'il y a trois choses à choisir — mais on peut s'arrêter à la
/// deuxième, et c'est le cas courant.
///
/// Ce qu'il remplace : revenir à la table des matières, replier un livre,
/// en déplier un autre. Quatre gestes pour aller de *Bereshit* 1 à
/// *Bereshit* 18.
public struct ReferencePicker: View {
    @Environment(ReadingModel.self) private var model
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ontTheme) private var theme

    var spacing = ONTSpacing()
    var echelle = ONTScaled()

    /// L'unité ouverte — le sélecteur s'ouvre là, pas en haut de la liste.
    ///
    /// **Facultative**, parce qu'on entre ici par deux portes. Depuis la
    /// lecture, il y a une unité courante et le sélecteur la marque. Depuis le
    /// sommaire d'un livre, il n'y en a pas : on n'a rien ouvert, on choisit.
    private let current: Chapter?

    /// L'étape en cours. Un chemin, pas des onglets : on avance et on revient.
    private enum Etape: Hashable {
        case unites(book: String)
        case versets(book: String, chapter: String)
    }

    /// Où la feuille s'ouvre.
    private let depart: Etape?

    public init(current: Chapter) {
        self.current = current
        self.depart = nil
    }

    /// Le sélecteur ouvert **directement sur les versets** d'une unité.
    ///
    /// C'est la porte du sommaire : le lecteur y a déjà choisi son livre et son
    /// unité, la seule chose qui lui reste à dire est *où commencer*. Le faire
    /// repasser par les deux étapes précédentes serait lui redemander ce qu'il
    /// vient de répondre.
    public init(book: String, chapter: String) {
        self.current = nil
        self.depart = .versets(book: book, chapter: chapter)
    }

    @State private var chemin: [Etape] = []
    @State private var recherche = ""

    public var body: some View {
        NavigationStack(path: $chemin) {
            livres
                .navigationTitle("Aller à")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: Etape.self) { etape in
                    switch etape {
                    case .unites(let book):
                        unites(of: book)
                    case .versets(let book, let chapter):
                        versets(book: book, chapter: chapter)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer") { dismiss() }
                    }
                }
        }
        .onAppear {
            // On ouvre sur le livre courant : le lecteur cherche presque
            // toujours à côté de là où il est.
            chemin = depart.map { [$0] } ?? [.unites(book: current?.bookId ?? "")]
        }
    }

    // MARK: - 1. Les livres

    private var livres: some View {
        List {
            ForEach(model.corpora) { corpus in
                let livresDuCorpus = corpus.modes
                    .sorted { $0.order < $1.order }
                    .flatMap(\.books)
                    .filter { correspond($0) }

                if !livresDuCorpus.isEmpty {
                    Section {
                        ForEach(livresDuCorpus) { livre in
                            Button {
                                chemin = [.unites(book: livre.id)]
                            } label: {
                                LivreLigne(livre: livre, courant: livre.id == current?.bookId)
                                    // Même défaut que « Reprendre » : le vide à
                                    // droite du titre ne répondait pas.
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            // Un slot vide reste **visible mais éteint** : le
                            // corpus est un chantier, et masquer les vides
                            // donnerait une fausse idée de sa forme.
                            .disabled(livre.empty)
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
        }
        .listStyle(.insetGrouped)
        .searchable(text: $recherche, prompt: "Chercher un livre")
        .ontScreen()
    }

    private func correspond(_ livre: BookOutline) -> Bool {
        guard !recherche.isEmpty else { return true }
        let cherche = replie(recherche)
        return replie(livre.title).contains(cherche)
            || replie(livre.french).contains(cherche)
    }

    /// Replie une chaîne pour la comparaison : sans accents, sans casse.
    ///
    /// Sans ça, chercher « berechit » ne trouve pas « Bereshit », et chercher
    /// « genese » ne trouve pas « Genèse » — ce qui est précisément ce qu'un
    /// lecteur tape.
    private func replie(_ texte: String) -> String {
        texte.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    // MARK: - 2. Les unités

    @ViewBuilder
    private func unites(of bookId: String) -> some View {
        // L'**esquisse** du livre, pas le livre : elle porte déjà le numéro, le
        // titre, le statut et le nombre de versets de chaque unité. Charger
        // `books/bereshit.json` — 750 Ko d'arbre d'inline — pour dessiner une
        // grille de numéros serait payer très cher un renseignement qu'on a.
        let livre = model.outline(bookId)
        ScrollView {
            if let livre, !livre.empty {
                VStack(alignment: .leading, spacing: spacing.m) {
                    if let intro = livre.intro {
                        Button {
                            aller(book: bookId, chapter: intro.id, verse: nil)
                        } label: {
                            Label("Introduction", systemImage: "text.book.closed")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(theme.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(spacing.m)
                                .background(
                                    RoundedRectangle(cornerRadius: ONTRadius.card)
                                        .fill(theme.accent.opacity(0.10))
                                )
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }

                    LazyVGrid(columns: grille, spacing: spacing.s) {
                        ForEach(livre.chapters) { unite in
                            Case(
                                titre: "\(unite.n)",
                                courant: unite.id == current?.id,
                                brouillon: unite.status == .brouillon
                            ) {
                                chemin.append(.versets(book: bookId, chapter: unite.id))
                            }
                        }
                    }
                }
                .padding(spacing.m)
            } else {
                Indisponible(message: "Ce livre n'est pas encore rédigé.")
            }
        }
        .navigationTitle(livre?.title ?? bookId)
        .navigationBarTitleDisplayMode(.inline)
        .ontScreen()
    }

    // MARK: - 3. Les versets

    @ViewBuilder
    private func versets(book: String, chapter: String) -> some View {
        let unite = model.outline(book)?.chapters.first { $0.id == chapter }
        ScrollView {
            VStack(alignment: .leading, spacing: spacing.m) {
                // La sortie courte, en premier : neuf fois sur dix on veut
                // l'unité, pas un verset précis.
                Button {
                    aller(book: book, chapter: chapter, verse: nil)
                } label: {
                    Label(toutLUnite, systemImage: "text.justify.left")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(theme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(spacing.m)
                        .background(
                            RoundedRectangle(cornerRadius: ONTRadius.card)
                                .fill(theme.accent.opacity(0.10))
                        )
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)

                if let unite, unite.verseCount > 0 {
                    // **Le verset où l'on est se marque, comme le livre et
                    // l'unité aux deux étapes précédentes.**
                    //
                    // Il était câblé à `false` : les deux premières étapes
                    // disaient où l'on est, la troisième ne le disait pas, et
                    // le lecteur arrivait sur vingt et une cases identiques
                    // sans savoir laquelle il venait de quitter. VoiceOver ne
                    // l'annonçait pas non plus — `courant` porte aussi le trait
                    // `.isSelected`.
                    let courant = versetCourant(book: book, chapter: chapter)
                    LazyVGrid(columns: grille, spacing: spacing.s) {
                        ForEach(1...unite.verseCount, id: \.self) { n in
                            Case(titre: "\(n)", courant: n == courant, brouillon: false) {
                                aller(book: book, chapter: chapter, verse: n)
                            }
                        }
                    }
                }
            }
            .padding(spacing.m)
        }
        .navigationTitle(unite?.label(french: model.preferences.french) ?? chapter)
        .navigationBarTitleDisplayMode(.inline)
        .ontScreen()
    }

    /// Le verset que le lecteur quitte, s'il est dans l'unité qu'on regarde.
    ///
    /// La position mémorisée est **la sienne**, pas celle de l'unité affichée :
    /// on ne la retient que si les deux coïncident. Sans ce garde-fou, ouvrir
    /// une autre unité que celle qu'on lit allumerait une case au hasard —
    /// « verset 12 » de *Bereshit* 2 parce qu'on en était au 12 de *Bereshit*
    /// 18.
    private func versetCourant(book: String, chapter: String) -> Int? {
        guard let position = model.position,
              position.bookId == book,
              position.chapterId == chapter
        else { return nil }
        return position.verse
    }

    /// « Tout le chapitre » ou « Toute la parashah », selon le registre.
    ///
    /// Le libellé disait « Toute l'unité » — le mot du pipeline, juste et
    /// interne. Le lecteur, lui, vient de toucher « Chapitre 2 » ou
    /// « Parashah 2 » ; lui répondre « unité » introduit un troisième nom pour
    /// la même chose, au moment précis où le réglage cherche à n'en enseigner
    /// qu'un.
    private var toutLUnite: String {
        LibelleDUnite.toutLe(french: model.preferences.french)
    }

    private func aller(book: String, chapter: String, verse: Int?) {
        router.open(book: book, chapter: chapter, verse: verse)
        dismiss()
    }

    /// Le minimum suit le curseur, comme la case qu'il accueille — sinon des
    /// chiffres devenus plus larges débordent d'une colonne restée à 54. La
    /// grille étant `.adaptive`, monter le minimum ne casse rien : elle pose
    /// simplement moins de colonnes.
    private var grille: [GridItem] {
        [GridItem(.adaptive(minimum: echelle(54)), spacing: spacing.s)]
    }
}

// MARK: - Pièces

/// Une case de la grille — une unité ou un verset.
///
/// 54 points de côté au minimum : en dessous, on rate la cible en tenant le
/// téléphone d'une main, qui est la posture de lecture.
private struct Case: View {
    @Environment(\.ontTheme) private var theme
    var echelle = ONTScaled()

    let titre: String
    let courant: Bool
    let brouillon: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(titre)
                .font(.system(size: echelle(17), weight: courant ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(courant ? theme.surface : theme.ink)
                .frame(minWidth: echelle(54), minHeight: echelle(48))
                .background(
                    RoundedRectangle(cornerRadius: ONTRadius.card)
                        .fill(courant ? theme.accent : theme.ink.opacity(0.06))
                )
                .overlay(alignment: .topTrailing) {
                    // Un brouillon se signale sans se refuser : §12 dit qu'il
                    // ne fait pas référence, pas qu'on ne peut pas le lire.
                    if brouillon {
                        Circle()
                            .fill(ONTColors.accent(theme.mode))
                            .frame(width: 6, height: 6)
                            .padding(6)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(courant ? [.isButton, .isSelected] : .isButton)
    }
}

private struct LivreLigne: View {
    @Environment(\.ontTheme) private var theme

    let livre: BookOutline
    let courant: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text("\(livre.slot)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(theme.ink.opacity(0.35))
                .frame(width: 24, alignment: .trailing)

            VStack(alignment: .leading, spacing: 1) {
                Text(livre.title)
                    .font(.custom(ONTFonts.display, size: 16))
                    .foregroundStyle(livre.empty ? theme.ink.opacity(0.35) : theme.ink)
                Text(livre.french)
                    .font(.caption)
                    .foregroundStyle(theme.ink.opacity(0.45))
            }
            Spacer(minLength: 8)
            if courant {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(theme.accent)
            }
        }
        .contentShape(.rect)
    }
}

private struct Indisponible: View {
    @Environment(\.ontTheme) private var theme
    let message: String

    var body: some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(theme.ink.opacity(0.55))
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
    }
}
