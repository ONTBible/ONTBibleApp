import ONTDesignSystem
import SwiftUI

/// Pose la fonte par défaut de l'interface, **et la repose quand elle change**.
///
/// ## Pourquoi une vue, et non un modificateur posé sur la scène
///
/// `.environment(\.font, ONTUI.body)` écrit directement dans le corps de l'`App`
/// paraît équivalent. Il ne l'est pas : ce corps est celui d'une **scène**, et
/// rien n'y observe plus le facteur d'interface depuis qu'on a retiré le
/// `dynamicTypeSize` qui le lisait. La valeur est calculée une fois, à
/// l'ouverture, et l'environnement garde cette fonte-là pour toujours.
///
/// Le symptôme était déroutant : à ⌘=, les cadres grandissaient — `ONTSpacing`
/// et `ONTScaled` sont relus à chaque passage — et les textes qui n'écrivent
/// aucune fonte restaient figés. L'interface enflait autour d'un texte immobile.
///
/// Ici, la lecture de `ONTUI.body` a lieu dans le corps d'une **vue**.
/// `Observation` l'enregistre, et la vue est refaite dès que le facteur bouge.
///
/// C'est la même leçon que les fermetures de `.commands` qui ne voyaient pas la
/// même instance d'`App` : **ce qui est lu hors d'un corps de vue n'est pas
/// observé**, et le code a l'air juste.
struct AvecLaFonteDeLInterface<Contenu: View>: View {
    @ViewBuilder let contenu: Contenu

    var body: some View {
        contenu.environment(\.font, ONTUI.body)
    }
}
