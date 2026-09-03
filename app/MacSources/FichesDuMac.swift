import LexiconFeature
import ONTDesignSystem
import ONTKit
import ReadingFeature
import SwiftUI

/// Comment une fiche paraît sur le Mac.
///
/// Deux gestes, et le lecteur choisit — c'est l'usage de Notion, que l'auteur a
/// montré en référence, et il tient à une chose : **consulter n'est pas
/// naviguer**. On ouvre un nom pour le lire, puis on revient à sa ligne. Ni
/// l'une ni l'autre de ces présentations ne fait perdre la place.
enum ModeDeFiche: String, CaseIterable, Sendable {
    /// Au centre, par-dessus la lecture, sur un fond assombri.
    ///
    /// Le geste par défaut : la fiche est ce qu'on regarde, elle est au milieu,
    /// et l'on en sort d'un clic à côté. Elle est plus large qu'un panneau, ce
    /// qui compte pour un article de lexique — l'hébreu, la translittération et
    /// la glose y tiennent sur une ligne au lieu de trois.
    case apercu
    /// À droite, à côté du texte, sans rien couvrir.
    ///
    /// Pour comparer : la fiche et le verset qui l'a fait ouvrir sont lisibles
    /// en même temps. C'est ce qu'un bureau permet et qu'un téléphone ne
    /// permettra jamais.
    case cote

    var suivant: ModeDeFiche { self == .apercu ? .cote : .apercu }

    /// Le symbole qui annonce vers quoi l'on bascule, jamais où l'on est : un
    /// bouton dit ce qu'il fait.
    var symboleDeBascule: String {
        self == .apercu ? "rectangle.righthalf.inset.filled" : "rectangle.center.inset.filled"
    }

    var titreDeBascule: String {
        self == .apercu ? "Ouvrir sur le côté" : "Ouvrir au centre"
    }
}

/// Un geste sans argument, isolé au fil principal.
///
/// Nommé plutôt que réécrit dix fois : un type de fonction porteur d'un acteur
/// global est implicitement `@Sendable`, et l'oublier à un seul maillon casse
/// toute la chaîne avec un message qui ne dit pas lequel.
typealias Geste = @MainActor () -> Void

extension View {
    /// Le panneau des fiches, **à poser dans la colonne de détail**.
    ///
    /// Là et pas à la racine : une `NavigationSplitView` enveloppée dans une
    /// `HStack` cesse d'être la racine de sa fenêtre, et la mise en page
    /// s'effondre — mesuré, la fenêtre tombait de 1240 × 960 à 98 × 139 points.
    /// Le panneau se range donc **à côté du texte**, à l'intérieur du détail,
    /// ce qui est aussi ce que fait Notion : la barre latérale reste entière.
    func panneauDeFiche(shemot: any ShemotRepository) -> some View {
        modifier(PanneauDeFiche(shemot: shemot))
    }

    /// L'aperçu au centre, **à poser à la racine** — il assombrit toute la
    /// fenêtre, barre latérale comprise, comme une modale doit le faire.
    func apercuDeFiche(shemot: any ShemotRepository) -> some View {
        modifier(ApercuDeFicheModifier(shemot: shemot))
    }
}

/// Ce que les deux présentations ont besoin de savoir.
///
/// Un protocole plutôt qu'une copie : la fiche ouverte, la fermeture et la
/// bascule se calculent pareil des deux côtés, et deux copies divergeraient à
/// la première retouche.
@MainActor
private protocol PorteLesFiches {
    var router: Router { get }
    var reglages: EtatMac { get }
    var shemot: any ShemotRepository { get }
}

@MainActor
extension PorteLesFiches {
    var ouverte: Fiche? {
        if let choix = router.openedLemma { return .terme(choix.id) }
        if let choix = router.openedShem { return .shem(choix.id) }
        return nil
    }

    /// Le geste de fermeture, qui ne capture que le routeur.
    ///
    /// Et non la vue : elle porte un `any ShemotRepository`, que rien ne dit
    /// transportable, alors que `Router` est une classe isolée au fil principal
    /// — donc transportable d'office. Capturer au plus juste est ici la
    /// condition pour que la fermeture puisse traverser l'environnement.
    var fermeture: Geste {
        let routeur = router
        return { routeur.openedLemma = nil; routeur.openedShem = nil }
    }

    var bascule: Geste {
        let reglages = reglages
        return { reglages.modeDeFiche = reglages.modeDeFiche.suivant }
    }

    @ViewBuilder
    func vue(de fiche: Fiche) -> some View {
        switch fiche {
        case .terme(let lemme): TermSheet(lemma: lemme)
        case .shem(let lemme): ShemSheet(lemma: lemme, shemot: shemot)
        }
    }
}

/// Laquelle des deux fiches est ouverte.
///
/// Un enum plutôt que les deux propriétés du `Router` lues séparément : une
/// fiche de terme et une fiche de nom ne peuvent pas être ouvertes en même
/// temps, et l'écrire ainsi supprime l'état où les deux le seraient — celui
/// qu'on n'aurait jamais éprouvé.
enum Fiche: Equatable {
    case terme(String)
    case shem(String)
}

/// La présentation des fiches — un seul endroit qui sait laquelle est ouverte.
///
/// Un enum local plutôt que les deux propriétés du `Router` lues séparément :
/// une fiche de terme et une fiche de nom ne peuvent pas être ouvertes en même
/// temps, et l'écrire ainsi supprime l'état où les deux le seraient — celui
/// qu'on n'aurait jamais testé.
private struct PanneauDeFiche: ViewModifier, PorteLesFiches {
    let shemot: any ShemotRepository

    @Environment(Router.self) var router
    @Environment(ReadingModel.self) private var reading
    let reglages = EtatMac.partage

    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            content
            if reglages.modeDeFiche == .cote, let ouverte {
                PoigneeDePanneau(largeur: Binding(
                    get: { reglages.largeurDuPanneau },
                    set: { reglages.largeurDuPanneau = $0 }))
                CadreDeFiche(
                    mode: .cote, contenu: { vue(de: ouverte) },
                    basculer: bascule, fermer: fermeture
                )
                .frame(width: reglages.largeurDuPanneau)
                .ontTheme(from: reading.preferences)
                // Il vient du bord qu'il occupe : c'est le seul mouvement qui
                // dit « à côté » plutôt que « par-dessus ».
                .transition(.move(edge: .trailing))
            }
        }
        .animation(ONTMouvement.ressort, value: ouverte)
        .animation(ONTMouvement.ressort, value: reglages.modeDeFiche)
    }
}

private struct ApercuDeFicheModifier: ViewModifier, PorteLesFiches {
    let shemot: any ShemotRepository

    @Environment(Router.self) var router
    @Environment(ReadingModel.self) private var reading
    let reglages = EtatMac.partage

    func body(content: Content) -> some View {
        content
            .overlay {
                if reglages.modeDeFiche == .apercu, let ouverte {
                    ApercuDeFiche(basculer: bascule, fermer: fermeture) {
                        vue(de: ouverte)
                    }
                    .ontTheme(from: reading.preferences)
                }
            }
            // `arrivee` et non le ressort courant : la carte doit se poser
            // comme la feuille de l'iPad — l'amortissement de 0,86 qu'il y
            // avait là gommait tout dépassement, et la fiche s'arrêtait net.
            .animation(ONTMouvement.arrivee, value: ouverte)
            .animation(ONTMouvement.ressort, value: reglages.modeDeFiche)
    }
}

// MARK: - L'aperçu au centre

/// La carte posée au milieu de la fenêtre, et le voile qui l'isole.
private struct ApercuDeFiche<Contenu: View>: View {
    let basculer: Geste
    let fermer: Geste
    @ViewBuilder let contenu: () -> Contenu

    @Environment(\.ontTheme) private var theme

    var body: some View {
        ZStack {
            // Le voile assombrit la lecture sans l'effacer : on doit voir qu'on
            // est toujours dans son chapitre, sinon la fiche ressemble à une
            // page et l'on cherche le bouton retour.
            Rectangle()
                .fill(.black.opacity(theme.mode.isDark ? 0.46 : 0.24))
                .ignoresSafeArea()
                .onTapGesture(perform: fermer)
                .transition(.opacity)

            GeometryReader { geo in
                CadreDeFiche(mode: .apercu, contenu: contenu, basculer: basculer, fermer: fermer)
                    // Assez large pour qu'une glose tienne sur une ligne,
                    // borné pour qu'elle ne s'étale pas sur un grand écran :
                    // au-delà, l'œil perd le début de la ligne suivante. La
                    // hauteur est un plafond — voir `ONTFeuille`, même peau.
                    .frame(width: min(max(geo.size.width * 0.66, 460), 860))
                    .background(theme.background, in: .rect(cornerRadius: ONTRadius.feuille))
                    .clipShape(.rect(cornerRadius: ONTRadius.feuille))
                    .shadow(color: .black.opacity(0.32), radius: 38, y: 16)
                    // Après la peinture — un `frame(maxHeight:)` s'étire
                    // jusqu'à sa borne, voir `ONTFeuille` : posé avant, le
                    // fond suivait l'étirement.
                    .frame(maxHeight: min(geo.size.height * 0.84, 900))
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            // Elle vient de l'endroit qu'elle occupera, un peu plus petite :
            // un glissement depuis un bord ferait croire à un changement de
            // page, ce qu'elle n'est pas. 0,94 — le trajet qui rend le
            // dépassement du ressort visible.
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
        // ⎋ ferme, comme partout ailleurs sur le Mac. Un bouton invisible,
        // parce que `keyboardShortcut` s'attache à une commande et qu'il n'y a
        // pas de commande à montrer ici — la fiche a déjà sa croix.
        .background {
            Button("", action: fermer)
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
        }
    }
}

// MARK: - Le cadre commun

/// Ce que les deux présentations partagent : une barre de tête, et la fiche.
///
/// Un seul cadre pour les deux modes, et non deux mises en page : la bascule
/// doit se lire comme un déplacement de la même chose, pas comme l'ouverture
/// d'une autre. Deux cadres divergeraient à la première retouche.
private struct CadreDeFiche<Contenu: View>: View {
    let mode: ModeDeFiche
    @ViewBuilder let contenu: () -> Contenu
    let basculer: Geste
    let fermer: Geste

    @Environment(\.ontTheme) private var theme
    private var espace = ONTSpacing()
    private var échelle = ONTScaled()

    init(
        mode: ModeDeFiche,
        @ViewBuilder contenu: @escaping () -> Contenu,
        basculer: @escaping Geste,
        fermer: @escaping Geste
    ) {
        self.mode = mode
        self.contenu = contenu
        self.basculer = basculer
        self.fermer = fermer
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: espace.xs) {
                BoutonDeCadre(
                    symbole: mode.symboleDeBascule, titre: mode.titreDeBascule,
                    action: basculer)
                Spacer(minLength: 0)
                BoutonDeCadre(symbole: "xmark", titre: "Fermer", action: fermer)
            }
            .padding(.horizontal, espace.s)
            .padding(.vertical, espace.xs + 2)
            Divider()
            contenu()
                // La fiche porte son propre bouton « Fermer » dans sa barre
                // d'outils, et il appelle `dismiss` — qui ne ferme ni un
                // panneau ni une surimpression. On lui dit donc comment.
                .environment(\.ontFermer, ONTFermeture(fermer))
        }
        .background(theme.background)
    }
}

/// Un bouton de la barre de tête — discret au repos, marqué au survol.
private struct BoutonDeCadre: View {
    let symbole: String
    let titre: String
    let action: Geste

    @Environment(\.ontTheme) private var theme
    @State private var survolé = false
    private var échelle = ONTScaled()

    init(symbole: String, titre: String, action: @escaping Geste) {
        self.symbole = symbole
        self.titre = titre
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbole)
                .font(.system(size: échelle(12), weight: .medium))
                .frame(width: échelle(26), height: échelle(26))
                .foregroundStyle(survolé ? theme.ink : theme.ink.opacity(0.55))
                // Un cercle, comme la pastille de fermeture des feuilles
                // d'iOS — le carré arrondi se lisait « case à cocher ».
                .background(theme.ink.opacity(survolé ? 0.12 : 0.05), in: .circle)
                .contentShape(.circle)
                .scaleEffect(survolé ? 1.08 : 1)
        }
        .buttonStyle(.ontPresse)
        .help(titre)
        .accessibilityLabel(titre)
        .onHover { survolé = $0 }
        .animation(ONTMouvement.ressortVif, value: survolé)
    }
}

// MARK: - La poignée

/// Le bord qu'on tire pour élargir le panneau.
///
/// Deux points de largeur visibles, huit points de prise : une poignée qu'on
/// doit viser n'est pas une poignée. C'est le même écart que macOS laisse à ses
/// propres séparateurs de colonnes, et le curseur change comme là-bas.
private struct PoigneeDePanneau: View {
    @Binding var largeur: CGFloat
    @Environment(\.ontTheme) private var theme
    @State private var depart: CGFloat?

    var body: some View {
        Rectangle()
            .fill(theme.separator)
            .frame(width: 1)
            .frame(width: 8)
            .contentShape(.rect)
            .onHover { survol in
                // On repose le curseur en sortant : laissé tel quel, il garde
                // la flèche de redimensionnement au-dessus du texte.
                if survol { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { geste in
                        let base = depart ?? largeur
                        if depart == nil { depart = largeur }
                        largeur = EtatMac.largeurDePanneauValide(base - geste.translation.width)
                    }
                    .onEnded { _ in depart = nil }
            )
    }
}
