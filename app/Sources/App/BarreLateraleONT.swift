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
    private var espace = ONTSpacing()

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
                Section {
                    // Le pli est fait à la main, et non par `Section(isExpanded:)`.
                    //
                    // Celui-ci replie bien, mais **dessine son propre chevron
                    // au survol** — l'auteur en a vu deux, le sien et le nôtre,
                    // dès que la souris passait sur l'en-tête. Et le sien
                    // n'apparaît qu'au survol, là où l'iPad l'affiche toujours.
                    // Deux raisons de ne pas le prendre, la seconde étant la
                    // vraie : on veut le témoin visible.
                    if !repliés.contains(corpus.id) {
                        ForEach(livresRédigés(de: corpus)) { livre in
                            LigneDeBarre(
                                cible: .book(livre.id), titre: livre.title,
                                symbole: "book.pages")
                        }
                    }
                } header: {
                    // **Un en-tête à nous, et non celui du système.**
                    //
                    // Celui du style `sidebar` compose en très petit, tout en
                    // capitales et en gris — trois écarts d'un coup avec la
                    // barre de l'iPad, relevés sur captures côte à côte. Le
                    // nom d'un corpus n'est pas une étiquette de rangement :
                    // « Kenesset » se lit, comme les livres en dessous.
                    //
                    // **Et le chevron est dessiné, pas hérité.**
                    // `Section(isExpanded:)` replie bien, mais n'affiche aucun
                    // témoin sous ce style — mesuré : la section se repliait
                    // sans que rien ne dise qu'elle le pouvait. Sur l'iPad il
                    // est toujours visible ; ici il l'est aussi.
                    Button {
                        basculer(corpus)
                    } label: {
                        HStack(spacing: espace.xs) {
                            Text(corpus.title)
                                .font(.custom(ONTFonts.display, size: ONTUI.points(14)))
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.down")
                                .font(.system(size: ONTUI.points(11), weight: .semibold))
                                .rotationEffect(.degrees(repliés.contains(corpus.id) ? -90 : 0))
                        }
                        .foregroundStyle(theme.ink.opacity(0.7))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .textCase(nil)
                    .padding(.vertical, espace.xs)
                }
            }
        }
        .listStyle(.sidebar)
        // **La surface, et non le fond de page.**
        //
        // Le fond du système ferait deux apps dans une fenêtre — une barre
        // grise contre un parchemin. Mais le fond de *page* faisait pire : la
        // barre et le contenu portaient exactement la même couleur, et rien ne
        // disait où l'une finissait. L'auteur l'a relevé en comparant avec
        // l'iPad, dont la barre native se détache du contenu.
        //
        // `surface` est le cran que la peau a déjà pour ça — en mystique,
        // l'aubergine passe de (0,094 · 0,035 · 0,051) à
        // (0,149 · 0,063 · 0,086). Aucune couleur n'est inventée : c'est le
        // même écart que celui des cartes sur le fond de page.
        .scrollContentBackground(.hidden)
        .background(theme.surface)
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
            // La même surface que la barre : la ligne du compte en fait partie,
            // elle n'est pas posée dessus.
            .background(theme.surface)
        }
    }

    /// Les corpus qu'on a repliés, par identifiant.
    ///
    /// Repliable comme sur l'iPad, dont chaque section porte son chevron. Sur
    /// un corpus complet — soixante-dix livres — c'est la différence entre une
    /// barre qu'on parcourt et une barre qu'on défile.
    ///
    /// L'état n'est pas gardé d'une session à l'autre, et c'est délibéré :
    /// rouvrir l'app sur une barre à moitié repliée ferait croire à un corpus
    /// amputé. Le pli est un geste de lecture, pas un réglage.
    @State private var repliés: Set<String> = []

    private func basculer(_ corpus: Corpus) {
        withAnimation(.easeOut(duration: 0.18)) {
            if repliés.contains(corpus.id) {
                repliés.remove(corpus.id)
            } else {
                repliés.insert(corpus.id)
            }
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
            // `aller(a:)` et non `tab = cible` : cliquer la ligne déjà choisie
            // ramène à la racine de sa pile, comme le fait `TabView` sur iOS.
            router.aller(a: cible)
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
            .padding(.horizontal, espace.s + 2)
            .padding(.vertical, espace.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            // **Une capsule, comme la barre native de l'iPad.**
            //
            // Le coin de 8 points venait du reste de l'app, où il est juste.
            // Ici il donnait une pastille rectangulaire là où l'iPad pose un
            // ovale plein — relevé sur capture, les deux côte à côte.
            .background(fond, in: .capsule)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
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
