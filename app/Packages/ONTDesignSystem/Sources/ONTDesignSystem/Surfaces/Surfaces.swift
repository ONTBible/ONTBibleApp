import ONTKit
import SwiftUI

/// La page de lecture — fond du thème, largeur bornée, marges d'aération.
///
/// Au-delà d'une certaine largeur, l'œil ne retrouve plus le début de la ligne
/// suivante. La borne vaut surtout sur iPad, où rien ne limiterait sinon.
public struct ParchmentPage<Content: View>: View {
    @Environment(\.ontTheme) private var theme
    var spacing = ONTSpacing()

    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, spacing.page)
            .padding(.vertical, spacing.l)
            .frame(maxWidth: ONTLayout.readingWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            // **Le grain aussi, et pas seulement la couleur.**
            //
            // Ce fond est plein : il recouvre celui que `ontScreen()` a posé
            // dessous, grain compris. Tant que la colonne occupait tout l'écran
            // visible, l'effacement ne se voyait pas — il n'y avait rien à
            // côté pour le comparer.
            //
            // Le pli du glissement a changé ça : il soulève la page et découvre
            // la marge, qui porte le grain d'`ontScreen()`. Deux surfaces de
            // même couleur, l'une grainée et l'autre non, et la couture court
            // le long du pli. Relevé par l'auteur sur l'iPad, le 13 septembre
            // 2026.
            //
            // Le commentaire d'avant disait « pas de grain ici, il s'arrêterait
            // au bord du texte ». C'était vrai quand ce fond épousait la mesure
            // du texte ; il est borné à `pageWidth` depuis que la liseuse prend
            // toute la largeur, et sa bordure ne tombe donc plus là.
            //
            // Retirer ce fond plutôt que le grainer aurait été plus court, et
            // plus risqué : c'est lui qui rend la page opaque quand le pli la
            // soulève, et une page qu'on soulève doit avoir un dos.
            .background {
                theme.background.overlay(ONTGrain(theme: theme.mode))
            }
    }
}

/// La carte bordeaux — le verset du jour, les mises en exergue.
public struct BurgundyCard<Content: View>: View {
    var spacing = ONTSpacing()
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(spacing.page)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ONTColors.burgundy, in: RoundedRectangle(cornerRadius: ONTRadius.card))
            .foregroundStyle(ONTColors.gold)
    }
}

/// Un bloc secondaire, en retrait.
public struct QuietBlock<Content: View>: View {
    var spacing = ONTSpacing()
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                .quaternary.opacity(0.35),
                in: RoundedRectangle(cornerRadius: ONTRadius.block)
            )
    }
}

/// Une pastille d'état — « brouillon », « glose ».
public struct StatusPill: View {
    let label: String
    var tint: Color

    public init(_ label: String, tint: Color = ONTColors.gold) {
        self.label = label
        self.tint = tint
    }

    public var body: some View {
        Text(label)
            .font(ONTUI.caption2)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.3), in: Capsule())
    }
}

/// Un titre de section, dans le registre du projet.
public struct SectionCaption: View {
    let label: String
    var tint: Color

    public init(_ label: String, tint: Color = .secondary) {
        self.label = label
        self.tint = tint
    }

    public var body: some View {
        Text(label)
            .font(ONTUI.caption.smallCaps())
            .foregroundStyle(tint)
            // **Un en-tête s'annonce.**
            //
            // VoiceOver propose de sauter d'en-tête en en-tête — un geste, et
            // le lecteur passe à la section suivante. Sans cette marque, le
            // rotor ne trouve rien et un chapitre de quatre cents versets se
            // traverse **linéairement**, verset après verset.
            //
            // Le petit corps en petites capitales dit « titre » à l'œil ; il ne
            // dit rien à qui n'a pas l'œil. C'est toute la différence entre une
            // apparence et une structure.
            .accessibilityAddTraits(.isHeader)
    }
}

/// Le filet doré qui sépare l'en-tête d'une unité de son corps.
public struct GoldRule: View {
    var opacity: Double

    public init(opacity: Double = 1) {
        self.opacity = opacity
    }

    public var body: some View {
        Divider().overlay(ONTColors.gold.opacity(opacity))
    }
}
