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
                    // capitales et en gris. Deux de ces trois traits sont de
                    // vrais écarts avec la barre de l'iPad, où l'en-tête lit
                    // « Kenesset » et non « KENESSET » : la casse et le gris
                    // restent donc à nous.
                    //
                    // **Le corps, lui, était l'erreur.** Il valait 14 comme
                    // les lignes, et un en-tête au corps de ses lignes n'est
                    // plus un en-tête : « Kenesset » se lisait comme un livre
                    // de plus. Sur l'iPad il est nettement plus petit. Il
                    // redescend donc à 10, l'encre avec.
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
                                .font(.custom(ONTFonts.navigation, size: ONTUI.points(10)))
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.down")
                                .font(.system(size: ONTUI.points(9), weight: .semibold))
                                .rotationEffect(.degrees(repliés.contains(corpus.id) ? -90 : 0))
                        }
                        .foregroundStyle(theme.ink.opacity(0.55))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.ontLigne)
                    .textCase(nil)
                    // **La géométrie des lignes, posée au padding — et rien
                    // qu'au padding.** `listRowInsets` est inerte sur un
                    // en-tête de section du style `sidebar` : mesuré, deux
                    // valeurs différentes ont rendu deux captures identiques.
                    // Les nombres visent les aplombs relevés : le chevron
                    // s'arrête au bord des capsules (318 pt dans une barre de
                    // 350), « Kenesset » à l'aplomb des icônes (39).
                    .padding(.leading, espace.s + 16)
                    .padding(.trailing, espace.s + 20)
                    .padding(.vertical, espace.xs)
                }
            }
        }
        .listStyle(.sidebar)
        // **Plus aucun fond ici — c'est le panneau qui porte la vitre.**
        //
        // La barre a peint sa surface pendant quatre jours, et c'était juste
        // tant qu'elle était une colonne. Depuis qu'elle flotte
        // (`panneauFlottant`, sur le Mac), son aplat bouchait la translucidité
        // qu'on venait d'installer : une vitre derrière un mur. Le voile du
        // thème vit dans le panneau, à demi-opacité, sur l'effet de vitre
        // arrière — et le bureau se devine au travers, comme chez Craft et
        // comme sur l'iPad.
        .scrollContentBackground(.hidden)
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
                // **La marge des autres lignes, et non la sienne.**
                //
                // `.listRowInsets` est **inerte** ici : ce modificateur n'agit
                // que sur une ligne de `List`, et celle-ci vit dans un
                // `safeAreaInset`. Il ne restait donc que 6 pt, là où une
                // ligne de la liste en a 26 — et la capsule dorée du compte
                // s'étalait sur toute la colonne.
                //
                // Relevé au pixel sur une capture de la fenêtre à 1440 × 900,
                // facteur 1 : la capsule d'une ligne choisie va de x 26,0 à
                // x 295,5 dans une colonne de 322 pt, celle du compte allait
                // de 6,0 à 315,5. Vingt points d'écart de chaque côté.
                //
                // Il ne suit pas le facteur d'interface, et c'est juste : ni
                // les `listRowInsets` de la ligne ni la marge propre au style
                // `sidebar` ne sont mis à l'échelle non plus. Vérifié à 1,5 —
                // la capsule monte de 36 à 54 pt de haut, et reste de 26,0 à
                // 295,5 en largeur, des deux côtés.
                .padding(.horizontal, LigneDeBarre.margeHorsListe)
                .padding(.vertical, 4)
            }
            // Aucun fond — la ligne du compte est dans le panneau, et le
            // panneau porte la vitre. Voir plus haut.
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
        ONTHaptique.cran()
        // Le ressort et non la rampe : le pli d'une section est le geste le
        // plus visible de la barre, c'est lui qui donne le tempérament.
        withAnimation(ONTMouvement.ressort) {
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

/// Une ligne de la barre latérale.
///
/// Le libellé est en Jost, la fonte de navigation du projet — c'est la règle du
/// site, que la barre d'AppKit ne pouvait pas suivre. Elle vaut ici doublement :
/// `Font.custom(_:size:)` suit Dynamic Type d'office, là où un `.system(size:)`
/// reste figé. La barre grandit donc avec ⌘=, ce qu'on lui demandait depuis le
/// début.
///
/// **En `navigation` et non en `display`.** La coupe SemiBold est celle des
/// titres ; posée sur une ligne de barre elle donnait un cran de graisse de
/// plus que la barre de l'iPad, que le système compose en graisse normale.
struct LigneDeBarre: View {
    /// La marge horizontale d'une ligne, capsule comprise — **relevée**, non
    /// choisie.
    ///
    /// Elle ne vaut pas les 10 pt de `.listRowInsets` ci-dessous : le style
    /// `sidebar` en ajoute du sien par-dessus, et seule la somme se voit. D'où
    /// la mesure plutôt que l'addition.
    ///
    /// Sert à la ligne du compte, qui vit hors de la `List` et ne peut donc pas
    /// se la faire poser par `.listRowInsets` — voir le commentaire là-bas.
    static let margeHorsListe: CGFloat = 26

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
                    .font(.custom(ONTFonts.navigation, size: ONTUI.points(13)))
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
        .buttonStyle(.ontLigne)
        .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .onHover { survolée = $0 }
        // Le survol se pose vite et se retire vite : au-delà, la barre traîne
        // derrière le curseur et donne l'impression que l'app rame. Le ressort
        // vif tient la même réponse, avec la détente de l'iPhone en plus.
        .animation(ONTMouvement.ressortVif, value: survolée)
        .animation(ONTMouvement.ressort, value: choisie)
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
