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
        // ## Ce qui ne tient pas défile, plutôt que de se tronquer
        //
        // Le réglage précédent servait le segment **choisi** en entier et
        // tronquait les autres. Il tenait tant que la troncature laissait de
        // quoi reconnaître un mot. Au premier cran d'accessibilité — celui où
        // Gloire lit — « Intraduisibles » prenait toute la largeur et les trois
        // autres tombaient à « V », « T », « S ». Trois portes devenues
        // illisibles : ce n'est plus une troncature, c'est une disparition.
        //
        // `ViewThatFits` essaie la rangée entière d'abord et bascule sur la
        // même, qui défile, quand elle ne tient plus. Aucune mesure, aucun
        // seuil deviné — c'est le principe que ce fichier suivait déjà, appliqué
        // au cas qu'il ne couvrait pas.
        //
        // **Et rien ne change aux tailles ordinaires** : la première branche
        // l'emporte, avec ses espaces qui se partagent le reste.
        ViewThatFits(in: .horizontal) {
            rangee(defilante: false)
            ScrollView(.horizontal) {
                rangee(defilante: true)
            }
            .scrollIndicators(.hidden)
            // **Le rail commence à son début.** Sans ancrage, le défilement
            // s'ouvrait ailleurs et le segment choisi sortait par la gauche :
            // « Intraduisibles » réduit à un « s » et à un fragment de capsule.
            // Relevé sur l'iPhone de Gloire, sur la première version de ce
            // défilement.
            .defaultScrollAnchor(.leading)
        }
        .padding(3)
        .background {
            Capsule()
                .fill(ONTColors.surface(theme.mode))
                .overlay(Capsule().strokeBorder(ONTColors.separator(theme.mode)))
        }
    }

    /// La rangée des segments.
    ///
    /// `defilante` dit ce qui change entre les deux branches, et rien d'autre :
    /// dans un défilement, les `Spacer` s'effondrent à zéro et les segments se
    /// tasseraient à gauche — on les retire donc, et chacun garde sa marge.
    @ViewBuilder
    private func rangee(defilante: Bool) -> some View {
        // ## Le choisi entier, les autres jamais tronqués
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
                    // Le ressort de la maison : la capsule du choisi glisse et
                    // se pose avec le rebond, comme tout ce qui bouge ici.
                    ONTHaptique.cran()
                    withAnimation(ONTMouvement.ressort) { selection = segment.valeur }
                } label: {
                    Text(segment.libelle)
                        .font(ONTUI.subheadline.weight(choisi ? .semibold : .regular))
                        .foregroundStyle(
                            choisi ? ONTColors.onBrand(theme.mode) : ONTColors.inkSoft(theme.mode)
                        )
                        // **Une ligne, et plus de troncature.** Ce qui ne
                        // tient pas s'atteint en faisant glisser ; un libellé
                        // réduit à sa première lettre ne s'atteignait pas.
                        .lineLimit(1)
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
                        .fixedSize(horizontal: true, vertical: false)
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
                .buttonStyle(.ontPresse)

                if rang < segments.count - 1, !defilante {
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
