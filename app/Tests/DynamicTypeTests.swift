import ONTDesignSystem
import SwiftUI
import Testing
import UIKit

/// Les jetons qui doivent grandir avec « Taille du texte ».
///
/// ## Pourquoi ces tests existent
///
/// `ONTSpacing` et `ONTScaled` sont des `DynamicProperty` : SwiftUI ne les
/// alimente qu'à une condition, être **stockés** dans la vue. Déclarés en
/// propriété calculée — `{ ONTSpacing() }` au lieu de `= ONTSpacing()` — ils
/// fabriquent une instance neuve à chaque lecture, que SwiftUI n'a jamais vue
/// et n'a donc jamais reliée à l'environnement. SwiftUI le dit lui-même dans
/// la console, mais seulement à l'exécution : « Accessing Environment's value
/// outside of being installed on a View. This will always read the default
/// value and will not update. »
///
/// Rien ne signale l'erreur : ça compile, ça s'affiche, et les valeurs sont
/// simplement figées. La grille d'espacement se croit à l'échelle et ne l'est
/// pas. C'est invisible à la relecture, et invisible à l'écran tant qu'on ne
/// bouge pas le curseur des réglages.
///
/// On mesure donc pour de vrai : un rendu au cran par défaut, un rendu au cran
/// le plus grand, et on compare les hauteurs.
struct DynamicTypeTests {
    /// Rend la vue et retourne sa hauteur en points.
    @MainActor
    private func hauteur(_ vue: some View, _ categorie: ContentSizeCategory) -> CGFloat {
        let rendu = ImageRenderer(content: vue.environment(\.sizeCategory, categorie))
        rendu.scale = 1
        return rendu.uiImage?.size.height ?? 0
    }

    @Test("un ONTSpacing stocké grandit avec le curseur")
    @MainActor
    func storedSpacingScales() {
        let petit = hauteur(BarreStockee(), .large)
        let grand = hauteur(BarreStockee(), .accessibilityExtraExtraExtraLarge)
        #expect(petit > 0, "le rendu a échoué, la mesure ne veut rien dire")
        #expect(
            grand > petit,
            "ONTSpacing stocké ne suit pas Dynamic Type — \(petit) pt au cran par défaut, \(grand) pt au plus grand"
        )
    }

    @Test("un ONTSpacing calculé reste figé — c'est le piège")
    @MainActor
    func computedSpacingIsFrozen() {
        let petit = hauteur(BarreCalculee(), .large)
        let grand = hauteur(BarreCalculee(), .accessibilityExtraExtraExtraLarge)
        #expect(petit > 0, "le rendu a échoué, la mesure ne veut rien dire")
        // Ce test **documente** le piège plutôt que de le corriger : si un jour
        // SwiftUI se met à alimenter les propriétés calculées, il tombera, et
        // on saura qu'on peut relâcher la règle.
        #expect(
            grand == petit,
            "une propriété calculée s'est mise à suivre le curseur — la règle du stocké a peut-être changé"
        )
    }

    @Test("ONTScaled grandit avec le curseur")
    @MainActor
    func scaledTokenScales() {
        let petit = hauteur(BarreEchelle(), .large)
        let grand = hauteur(BarreEchelle(), .accessibilityExtraExtraExtraLarge)
        #expect(petit > 0, "le rendu a échoué, la mesure ne veut rien dire")
        #expect(
            grand > petit,
            "ONTScaled ne suit pas Dynamic Type — \(petit) pt au cran par défaut, \(grand) pt au plus grand"
        )
    }
}

// MARK: - Les trois témoins

/// La déclaration correcte : stockée, donc alimentée par SwiftUI.
private struct BarreStockee: View {
    private var spacing = ONTSpacing()

    var body: some View {
        Color.clear.frame(width: 10, height: spacing.xxl)
    }
}

/// La déclaration piégeuse : calculée, donc jamais alimentée.
///
/// Volontairement écrite ainsi. Toute réécriture automatique qui la
/// « corrigerait » en propriété stockée ferait tomber son test — c'est le
/// filet, pas une négligence.
private struct BarreCalculee: View {
    private var spacing: ONTSpacing { ONTSpacing() }

    var body: some View {
        Color.clear.frame(width: 10, height: spacing.xxl)
    }
}

private struct BarreEchelle: View {
    private var echelle = ONTScaled()

    var body: some View {
        Color.clear.frame(width: 10, height: echelle(32))
    }
}
