import ONTDesignSystem
import ONTKit
import ReadingFeature
import SwiftUI
import YouFeature

// MARK: - La barre latérale

/// La barre latérale de la liseuse, dessinée par l'app.
///
/// Une `List` et des lignes à nous, plutôt qu'une `List(selection:)` : la
/// sélection d'une liste système est peinte par AppKit avec l'accent du
/// système, ce qui est précisément ce qu'on vient de quitter. Le prix est de
/// dessiner soi-même l'état sélectionné et le survol ; le gain est que la barre
/// porte enfin la peau de l'app, et qu'elle suit le corps réglé au clavier.
struct BarreLateraleONT: View {
    @Environment(Router.self) private var router
    @Environment(ReadingModel.self) private var reading
    @Environment(AccountModel.self) private var compte
    @Environment(\.ontTheme) private var theme

    var body: some View {
        List {
            // **« Reprendre » dans sa propre section.**
            //
            // Le filet qui la sépare du reste n'est pas décoratif : il dit que
            // reprendre sa lecture n'est pas une destination de plus, c'est le
            // retour à celle qu'on avait quittée. Les trois suivantes sont des
            // lieux ; celle-ci est un signet.
            Section {
                LigneDeBarre(
                    cible: .reprendre, titre: "Reprendre", symbole: "bookmark.fill")
            }
            Section {
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
        // **Le compte en bas, épinglé.**
        //
        // C'est la place qu'Apple Music lui donne, et ce n'est pas une
        // convention arbitraire : le compte n'est pas une destination parmi
        // les livres, c'est **qui regarde**. Il ne défile donc pas avec eux, et
        // il reste atteignable quel que soit l'endroit du corpus où l'on est.
        //
        // `safeAreaInset` plutôt qu'une dernière section : une section
        // défilerait, et sur un corpus complet elle serait à soixante-dix
        // livres de là.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                LigneDeBarre(
                    cible: .you,
                    titre: compte.profil.nomDeBarre,
                    icone: .portrait(compte.profil, compte.portrait())
                )
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .background(theme.background)
        }
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
/// Ce qui tient lieu d'icône à une ligne.
///
/// Un enum plutôt qu'un générique : les deux cas sont fermés et le resteront —
/// un symbole du système pour une destination, le visage du lecteur pour son
/// compte. Un générique ferait porter à chaque appel un paramètre de type que
/// personne ne veut nommer.
enum IconeDeLigne {
    case symbole(String)
    case portrait(Profil, Data?)
}

struct LigneDeBarre: View {
    let cible: Router.TabID
    let titre: String
    let icone: IconeDeLigne

    @Environment(Router.self) private var router
    @Environment(\.ontTheme) private var theme
    @State private var survolée = false
    private var espace = ONTSpacing()
    private var échelle = ONTScaled()

    init(cible: Router.TabID, titre: String, icone: IconeDeLigne) {
        self.cible = cible
        self.titre = titre
        self.icone = icone
    }

    /// Le raccourci du cas courant.
    init(cible: Router.TabID, titre: String, symbole: String) {
        self.init(cible: cible, titre: titre, icone: .symbole(symbole))
    }

    private var choisie: Bool { router.tab == cible }

    var body: some View {
        Button {
            router.tab = cible
        } label: {
            HStack(spacing: espace.s) {
                switch icone {
                case .symbole(let nom):
                    Image(systemName: nom)
                        .font(.system(size: échelle(13)))
                        .frame(width: échelle(20))
                case .portrait(let profil, let octets):
                    // Le portrait remplit la même case qu'un symbole : sans ça
                    // le libellé du compte ne s'alignerait pas sur les autres,
                    // et l'œil verrait une ligne de travers avant de voir un
                    // visage.
                    Portrait(profil: profil, octets: octets, taille: échelle(20))
                }
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
