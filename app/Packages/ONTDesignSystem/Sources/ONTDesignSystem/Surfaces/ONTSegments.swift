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
        // ## Le choisi entier, les autres tronqués s'il le faut
        //
        // Une ligne, toujours — on a essayé d'empiler quand ça ne rentrait
        // plus, et c'était pire : le contrôle changeait de forme sous les
        // doigts, et prenait trois fois la hauteur pour dire la même chose.
        //
        // Ce qui doit se lire en entier, c'est le segment **retenu** : lui seul
        // dit où l'on est. Les autres sont des portes qu'on reconnaît à leur
        // début — « Vocabulai… » suffit à savoir qu'on n'est pas dessus.
        //
        // `layoutPriority` le dit à la mise en page : le choisi est servi le
        // premier, à sa largeur naturelle ; le reste se partage ce qui demeure
        // et se tronque au besoin. Aucune mesure à faire, aucun seuil à deviner.
        HStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.element.valeur) { rang, segment in
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
                        .truncationMode(.tail)
                        // Une marge de part et d'autre : sans elle, deux
                        // libellés voisins se touchent et se lisent comme un
                        // seul mot.
                        .padding(.horizontal, spacing.m)
                        .padding(.vertical, spacing.s)
                        // Le choisi prend la largeur de son mot ; les autres se
                        // partagent ce qui reste. Lui donner l'infini **et** la
                        // priorité lui faisait tout prendre, et les deux autres
                        // disparaissaient — vu à l'écran avant d'être corrigé.
                        // ## Personne ne réclame l'infini
                        //
                        // Donner `maxWidth: .infinity` aux segments les force à
                        // se partager la place en parts fixes : le libellé le
                        // plus long se tronque alors même quand la ligne
                        // entière tiendrait. On laisse donc chacun prendre la
                        // largeur de son mot, et c'est l'**espace restant** qui
                        // se répartit entre eux.
                        //
                        // Quand la place manque, ces espaces se referment
                        // d'abord, puis les libellés se tronquent — sauf le
                        // choisi, que sa priorité sert le premier.
                        .fixedSize(horizontal: choisi, vertical: false)
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
                // Le choisi passe devant : il obtient sa largeur naturelle, et
                // les autres se serrent autour de lui.
                .layoutPriority(choisi ? 1 : 0)
                .accessibilityAddTraits(choisi ? [.isButton, .isSelected] : .isButton)

                if rang < segments.count - 1 {
                    Spacer(minLength: 0)
                }
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
