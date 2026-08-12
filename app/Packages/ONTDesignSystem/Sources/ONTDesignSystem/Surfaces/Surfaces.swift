import ONTKit
import SwiftUI

/// La page de lecture — fond du thème, largeur bornée, marges d'aération.
///
/// Au-delà d'une certaine largeur, l'œil ne retrouve plus le début de la ligne
/// suivante. La borne vaut surtout sur iPad, où rien ne limiterait sinon.
public struct ParchmentPage<Content: View>: View {
    @Environment(\.ontTheme) private var theme
    private var spacing = ONTSpacing()

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
            .background(theme.background)
    }
}

/// La carte bordeaux — le verset du jour, les mises en exergue.
public struct BurgundyCard<Content: View>: View {
    private var spacing = ONTSpacing()
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
    private var spacing = ONTSpacing()
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
            .font(.caption2)
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
            .font(.caption.smallCaps())
            .foregroundStyle(tint)
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
