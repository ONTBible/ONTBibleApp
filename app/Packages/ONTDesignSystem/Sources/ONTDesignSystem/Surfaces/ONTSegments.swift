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
    @Environment(\.dynamicTypeSize) private var taille
    @Namespace private var glissiere
    private var spacing = ONTSpacing()

    private let segments: [(valeur: Valeur, libelle: String)]
    @Binding private var selection: Valeur

    /// La largeur que la mise en page nous offre, relevée à la pose.
    @State private var offerte: CGFloat = 0

    /// La part de chacun, côte à côte. `nil` tant qu'on n'a pas mesuré, et
    /// quand on empile — un segment empilé prend toute la largeur.
    private var part: CGFloat? {
        guard !empile, offerte > 0, !segments.isEmpty else { return nil }
        return offerte / CGFloat(segments.count)
    }

    /// Empile-t-on ?
    private var empile: Bool { taille.isAccessibilitySize }

    @ViewBuilder
    private var boutons: some View {
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
                    // Une seule ligne côte à côte, libre une fois empilé : la
                    // largeur entière suffit presque toujours, et un mot coupé
                    // vaut mieux qu'un mot rétréci pour qui a monté son texte.
                    .lineLimit(empile ? nil : 1)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(empile ? 1 : 0.85)
                    .frame(maxWidth: empile ? .infinity : nil)
                    .frame(width: part, alignment: .center)
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

    public init(selection: Binding<Valeur>, segments: [(Valeur, String)]) {
        self._selection = selection
        self.segments = segments.map { (valeur: $0.0, libelle: $0.1) }
    }

    public var body: some View {
        // ## Côte à côte, ou l'un sous l'autre
        //
        // Un segmenté suppose que les libellés tiennent côte à côte. Aux crans
        // d'accessibilité, « Intraduisibles » et « Vocabulaire fixé » n'y
        // tiennent plus : ils se coupent en deux lignes, la pastille devient
        // ronde et le contrôle illisible. C'est le raisonnement qui a fait
        // choisir un menu pour le thème — ici on garde l'immédiateté, en
        // empilant plutôt qu'en repliant. Tout reste visible, à un doigt.
        Group {
            if empile {
                VStack(spacing: 4) { boutons }
            } else {
                HStack(spacing: 0) { boutons }
            }
        }
        .frame(maxWidth: .infinity)
        // ## Des parts mesurées, et non espérées
        //
        // `frame(maxWidth: .infinity)` ne partage pas en parts égales : il
        // autorise chaque vue à s'étendre, et la mise en page sert d'abord
        // celles qui **demandent** plus. Le segment au libellé le plus long
        // prenait donc davantage que son tiers, et sa pastille passait sous le
        // voisin — « Intraduisibles » recouvrait « Vocabulaire fixé ».
        //
        // On relève la largeur offerte et on la divise. Tant qu'elle est
        // inconnue, on laisse chacun prendre sa taille naturelle : une seule
        // image mal partagée vaut mieux qu'un contrôle qui n'apparaît pas.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { offerte = $0 }
        .padding(3)
        .background {
            // Une capsule côte à côte, un rectangle arrondi une fois empilé :
            // sur une hauteur de trois rangées, une capsule bombe en ovale et
            // le contrôle ressemble à un ballon.
            RoundedRectangle(cornerRadius: empile ? 22 : 999, style: .continuous)
                .fill(ONTColors.surface(theme.mode))
                .overlay(
                    RoundedRectangle(cornerRadius: empile ? 22 : 999, style: .continuous)
                        .strokeBorder(ONTColors.separator(theme.mode))
                )
        }
    }
}
