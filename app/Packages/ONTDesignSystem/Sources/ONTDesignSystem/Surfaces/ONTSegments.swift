import SwiftUI

/// Un choix entre quelques portées, dans les couleurs du thème.
///
/// ## Pourquoi pas `.pickerStyle(.segmented)`
///
/// Le segmenté d'iOS ne se teinte pas. Il prend le gris du système et le garde,
/// quel que soit `tint` : sur la nuit aubergine, il pose un rectangle neutre au
/// milieu d'un écran chaud, et c'est le dernier morceau de l'app qui trahissait
/// encore le thème. On le refait donc, en trois vues.
///
/// ## Ce qu'on garde du modèle d'Apple
///
/// La glissière : le fond du segment choisi se **déplace** d'un segment à
/// l'autre au lieu d'apparaître. C'est ce qui distingue un choix parmi peu d'un
/// simple bouton, et `matchedGeometryEffect` le rend sans qu'on calcule rien.
///
/// Et l'accessibilité : chaque segment est un vrai bouton, marqué sélectionné
/// pour celui qui l'est. VoiceOver annonce donc « Dans le texte, sélectionné »
/// comme il le ferait du contrôle d'Apple.
public struct ONTSegments<Valeur: Hashable>: View {
    @Environment(\.ontTheme) private var theme
    @Namespace private var glissiere
    private var spacing = ONTSpacing()

    private let segments: [(valeur: Valeur, libelle: String)]
    @Binding private var selection: Valeur

    public init(selection: Binding<Valeur>, segments: [(Valeur, String)]) {
        self._selection = selection
        self.segments = segments.map { (valeur: $0.0, libelle: $0.1) }
    }

    public var body: some View {
        // ## Essayer, puis se rabattre
        //
        // `ViewThatFits` pose la première disposition qui tient dans la place
        // offerte, et se rabat sur la suivante sinon. C'est exactement la
        // question ici, et c'est SwiftUI qui la tranche — pas un seuil de
        // Dynamic Type, pas une mesure que j'aurais faite à côté.
        //
        // Deux tentatives précédentes ont échoué, et il vaut mieux les écrire :
        // un seuil sur les crans d'accessibilité laissait trois libellés collés
        // pour qui monte son texte sans les atteindre ; et une copie invisible
        // posée en arrière-plan mesurait la largeur **offerte**, jamais celle
        // dont les mots ont besoin — un arrière-plan reçoit la taille de ce
        // qu'il habille.
        ViewThatFits(in: .horizontal) {
            ligne
            colonne
        }
        .frame(maxWidth: .infinity)
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(ONTColors.surface(theme.mode))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(ONTColors.separator(theme.mode))
                )
        }
    }

    /// Côte à côte, chacun à la largeur de son mot.
    ///
    /// Des parts égales seraient plus régulières, mais elles obligeraient le
    /// libellé le plus long à se tronquer ou à rétrécir bien avant que la ligne
    /// entière soit pleine. Un mot entier vaut mieux qu'une grille.
    private var ligne: some View {
        HStack(spacing: 0) {
            ForEach(segments, id: \.valeur) { segment in
                bouton(segment, pleineLargeur: false)
            }
        }
    }

    /// L'un sous l'autre, chacun sur toute la largeur.
    private var colonne: some View {
        VStack(spacing: 4) {
            ForEach(segments, id: \.valeur) { segment in
                bouton(segment, pleineLargeur: true)
            }
        }
    }

    private func bouton(
        _ segment: (valeur: Valeur, libelle: String),
        pleineLargeur: Bool
    ) -> some View {
        let choisi = segment.valeur == selection
        return Button {
            withAnimation(.snappy(duration: 0.22)) { selection = segment.valeur }
        } label: {
            Text(segment.libelle)
                .font(.subheadline.weight(choisi ? .semibold : .regular))
                .foregroundStyle(
                    choisi ? ONTColors.onBrand(theme.mode) : ONTColors.inkSoft(theme.mode)
                )
                .lineLimit(1)
                .padding(.horizontal, spacing.m)
                .padding(.vertical, spacing.s)
                .frame(maxWidth: pleineLargeur ? .infinity : nil)
                .background {
                    if choisi {
                        Capsule()
                            .fill(ONTColors.brandInk(theme.mode))
                            .matchedGeometryEffect(id: "choisi", in: glissiere)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(choisi ? [.isButton, .isSelected] : .isButton)
    }
}
