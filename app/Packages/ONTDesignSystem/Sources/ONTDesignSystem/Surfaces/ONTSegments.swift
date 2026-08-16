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
        HStack(spacing: 0) {
            ForEach(segments, id: \.valeur) { segment in
                let choisi = segment.valeur == selection
                Button {
                    withAnimation(.snappy(duration: 0.22)) { selection = segment.valeur }
                } label: {
                    Text(segment.libelle)
                        .font(.subheadline.weight(choisi ? .semibold : .regular))
                        .foregroundStyle(
                            choisi ? ONTColors.onBrand(theme.mode) : ONTColors.inkSoft(theme.mode)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, spacing.s)
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
        .padding(3)
        .background {
            Capsule()
                .fill(ONTColors.surface(theme.mode))
                .overlay(Capsule().strokeBorder(ONTColors.separator(theme.mode)))
        }
    }
}
