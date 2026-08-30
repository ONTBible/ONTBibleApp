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
        // **Invisible à VoiceOver, et c'est voulu.** Un lecteur d'écran
        // parcourt déjà la liste par ses en-têtes de section, qui portent les
        // mêmes lettres ; le rail lui offrirait vingt-six éléments redondants
        // dont aucun ne se manipule au doigt glissé.
        .accessibilityHidden(true)
    }
}
