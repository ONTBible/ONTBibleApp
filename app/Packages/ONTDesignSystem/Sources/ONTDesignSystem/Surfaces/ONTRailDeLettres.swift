import SwiftUI

/// Le rail alphabétique — on y glisse le pouce, la liste saute.
///
/// ## Pourquoi il est dessiné et non demandé au système
///
/// `List` sait faire cet index sur watchOS, et **nulle part ailleurs** : sur
/// iOS, `sectionIndexTitles` n'existe que dans `UITableView`. L'envelopper pour
/// une bande de lettres coûterait un pont vers UIKit et la perte des styles de
/// liste de SwiftUI. Vingt lignes le dessinent.
///
/// ## Ce qui le rend utilisable, et qu'on n'obtient pas gratuitement
///
/// **Un seul geste continu.** Ce ne sont pas des boutons : on pose le pouce et
/// on descend. Des boutons obligeraient à viser une lettre haute de onze
/// points — impossible en marchant, et c'est le geste que Contacts a rendu
/// naturel depuis quinze ans.
///
/// **Un retour tactile à chaque lettre franchie.** Le pouce couvre le rail
/// qu'il touche : sans la vibration, on ne sait pas qu'on a changé de lettre
/// avant que la liste ait sauté. C'est le même `.selection` que la sélection de
/// versets, et pour la même raison — savoir sans regarder.
public struct ONTRailDeLettres: View {
    @Environment(\.ontTheme) private var theme

    let lettres: [String]
    /// Appelée à chaque changement de lettre sous le doigt.
    let vers: (String) -> Void

    /// La lettre sous le doigt, ou `nil` quand il n'y a pas de doigt.
    @State private var sousLeDoigt: String?

    /// Le pas entre deux lettres, en points.
    ///
    /// Contacts d'Apple tient ses vingt-sept lettres à quatorze points. Le
    /// Lexique en a moins — les tranches d'un glossaire hébreu ne couvrent pas
    /// tout l'alphabet —, donc la place ne manque pas, et l'auteur a demandé
    /// « un tout petit peu plus d'écart » après avoir vu les deux à l'écran.
    ///
    /// Quinze, arrêté à l'écran : quatorze serrait trop pour le nombre de
    /// lettres qu'a ce glossaire, dix-sept commençait à disperser. ==Un pas se
    /// juge sur l'appareil, pas sur la mesure d'à côté.==
    ///
    /// Sous les quarante-quatre points d'une cible tactile ordinaire, et ce
    /// n'est pas un oubli : ==un rail se parcourt au doigt glissé==, pas au
    /// tap précis. Le geste suit le doigt en continu et corrige de lui-même.
    private static let pas: CGFloat = 15

    public init(lettres: [String], vers: @escaping (String) -> Void) {
        self.lettres = lettres
        self.vers = vers
    }

    public var body: some View {
        GeometryReader { cadre in
            VStack(spacing: 0) {
                ForEach(lettres, id: \.self) { lettre in
                    Text(lettre)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(.rect)
            .gesture(
                // `minimumDistance: 0` : le geste doit prendre au premier
                // contact. À 10 — le défaut — un simple appui sur une lettre ne
                // ferait rien, et le rail paraîtrait mort.
                DragGesture(minimumDistance: 0)
                    .onChanged { position in
                        guard !lettres.isEmpty else { return }
                        let hauteur = cadre.size.height / CGFloat(lettres.count)
                        let rang = Int(position.location.y / max(hauteur, 1))
                        let lettre = lettres[min(max(rang, 0), lettres.count - 1)]

                        // **On n'appelle qu'au changement.** Un doigt immobile
                        // envoie des dizaines d'événements par seconde ; les
                        // suivre ferait vibrer en continu et redemanderait le
                        // même défilement à chaque image.
                        guard lettre != sousLeDoigt else { return }
                        sousLeDoigt = lettre
                        vers(lettre)
                    }
                    .onEnded { _ in sousLeDoigt = nil }
            )
            .sensoryFeedback(.selection, trigger: sousLeDoigt)
        }
        .frame(width: 22)
        // **Le rail se groupe, il ne s'étale pas.**
        //
        // Chaque lettre prend `maxHeight: .infinity` dans un `VStack` qui
        // remplissait toute la colonne : vingt lettres sur huit cents points
        // faisaient quarante points de pas, et le rail se lisait comme une
        // suite de lettres éparpillées le long du bord plutôt que comme un
        // index.
        //
        // Contacts d'Apple — la référence pour ce contrôle — tient ses
        // vingt-sept lettres sur un pas d'environ quatorze points, groupées et
        // centrées. Relevé par l'auteur le 22 septembre 2026, capture à
        // l'appui : « elles sont hyper explosées, sur Contacts c'est beaucoup
        // moins le cas ».
        //
        // ==Borner la hauteur plutôt que fixer celle de chaque lettre== : le
        // `GeometryReader` mesure alors la hauteur réduite, et le calcul du
        // geste — `hauteur / lettres.count` — reste juste sans qu'on y touche.
        // Sur un écran trop court pour le compte, le rail se resserre au lieu
        // de déborder.
        .frame(maxHeight: CGFloat(lettres.count) * Self.pas)
        // **Invisible à VoiceOver, et c'est voulu.** Un lecteur d'écran
        // parcourt déjà la liste par ses en-têtes de section, qui portent les
        // mêmes lettres ; le rail lui offrirait vingt-six éléments redondants
        // dont aucun ne se manipule au doigt glissé.
        .accessibilityHidden(true)
    }
}
