import ONTKit
import SwiftUI

/// Le thème — un seul objet qui porte toutes les décisions visuelles.
///
/// Injecté par l'environnement, il évite qu'une vue accumule les lectures
/// séparées (accent, espacement, couleur d'encre…). On lit le thème, et on
/// prend ses membres.
/// `Equatable` pour que les vues qui en dépendent puissent être comparées, et
/// donc **sautées** quand rien de ce qu'elles rendent n'a changé. Voir la prose
/// continue, où une recomposition inutile coûte une mise en page entière.
public struct ONTTheme: Sendable, Equatable {
    public var preferences: ReadingPreferences
    /// La taille du corps, déjà mise à l'échelle par Dynamic Type.
    public var scaledTextSize: CGFloat

    public init(
        preferences: ReadingPreferences = .default,
        scaledTextSize: CGFloat? = nil
    ) {
        self.preferences = preferences
        self.scaledTextSize = scaledTextSize ?? preferences.textSize
    }

    public var mode: ReadingTheme { preferences.theme }
    public var background: Color { ONTColors.background(mode) }
    public var ink: Color { ONTColors.ink(mode) }
    public var surface: Color { ONTColors.surface(mode) }
    public var separator: Color { ONTColors.separator(mode) }
    public var accent: Color { ONTColors.accent(mode) }

    public var type: ONTTypography {
        ONTTypography(size: scaledTextSize, theme: mode, face: preferences.bodyFont)
    }

    /// L'interligne effectif, en points.
    public var lineSpacing: CGFloat {
        scaledTextSize * preferences.lineSpacing * 0.5
    }

    /// L'écart entre deux versets.
    public var verseSpacing: CGFloat {
        scaledTextSize * preferences.lineSpacing
    }

    /// Le souffle d'interlettrage des fonds sombres, en points.
    ///
    /// La halation : sur une nuit, un texte clair déborde optiquement dans le
    /// noir qui l'entoure, les lettres paraissent plus grasses et finissent par
    /// se toucher. Le site corrige par `letter-spacing: 0.006em` et note que ce
    /// n'est pas un goût.
    ///
    /// Proportionnel au corps, donc `0,006 × la taille` : un interlettrage fixe
    /// serait invisible à 15 pt et béant à 28. Rien sur les fonds clairs, où le
    /// phénomène joue en sens inverse.
    public var tracking: CGFloat { mode.isDark ? scaledTextSize * 0.006 : 0 }

    /// Le jeu de couleurs système que ce thème implique.
    public var colorScheme: ColorScheme { mode.isDark ? .dark : .light }
}

private struct ONTThemeKey: EnvironmentKey {
    static let defaultValue = ONTTheme()
}

extension EnvironmentValues {
    public var ontTheme: ONTTheme {
        get { self[ONTThemeKey.self] }
        set { self[ONTThemeKey.self] = newValue }
    }
}

extension View {
    /// Pose le thème et ce qui en découle pour tout le sous-arbre.
    public func ontTheme(_ theme: ONTTheme) -> some View {
        environment(\.ontTheme, theme)
            // La teinte suit le thème. Posée en bordeaux pour tout le monde,
            // elle rendait l'onglet actif et chaque bouton système illisibles
            // sur les fonds sombres — 1,2:1, du bordeaux sur du bordeaux.
            .tint(ONTColors.brandInk(theme.mode))
    }
}

/// Applique la taille du corps mise à l'échelle par Dynamic Type.
///
/// `@ScaledMetric` ne peut vivre que dans une `View` ou un `DynamicProperty` :
/// ce modificateur est le pont entre la préférence brute du lecteur et le
/// thème que les vues consomment.
public struct ScaledThemeModifier: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    let preferences: ReadingPreferences

    public init(preferences: ReadingPreferences) {
        self.preferences = preferences
    }

    public func body(content: Content) -> some View {
        content.ontTheme(
            ONTTheme(
                preferences: preferences,
                scaledTextSize: preferences.textSize * scale
            )
        )
    }
}

extension View {
    /// Le point d'entrée : construit le thème depuis les réglages du lecteur,
    /// en tenant compte du réglage système de taille de police.
    public func ontTheme(from preferences: ReadingPreferences) -> some View {
        modifier(ScaledThemeModifier(preferences: preferences))
    }
}
