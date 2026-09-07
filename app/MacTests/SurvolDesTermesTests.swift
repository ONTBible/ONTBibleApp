import SwiftUI
import Testing

@testable import ONTDesignSystem
@testable import ONTKit

/// **Le voile de survol atteint-il seulement les runs ?**
///
/// Le mécanisme traverse trois couches : la marque posée dans
/// l'`AttributedString` (`AttributedStringKey`), son transport jusqu'au
/// `Text.Layout` (`TextAttribute`), et le dessin du voile dans le
/// `TextRenderer`. Chacune peut échouer **en silence** — un attribut qui ne
/// voyage pas donne exactement le même écran qu'un survol au repos, et le
/// défaut ne se verrait qu'à la souris, que personne ne peut simuler ici.
///
/// D'où le mode sonde : tous les runs marqués voilés, sans curseur. Si les
/// pixels ne bougent pas entre sonde et repos, la chaîne est morte quelque
/// part — et l'épreuve le dit avant qu'un lecteur ne le découvre.
@MainActor
@Suite("Le survol des termes")
struct SurvolDesTermesTests {
    private func pixels(sonde: Bool) -> Data? {
        let nodes: [Inline] = [
            .text("la "), .term("chesed", lemma: "chesed"), .text(" du corpus"),
        ]
        let corps = ONTTextRenderer.compose(nodes, theme: ONTTheme())
        let vue = Text(corps)
            .ontSurvolDesTermes(corps, sonde: sonde)
            .padding(8)
            .frame(width: 320)
        let rendu = ImageRenderer(content: vue)
        rendu.scale = 2
        return rendu.nsImage?.tiffRepresentation
    }

    @Test("la marque traverse jusqu'au dessin")
    func laMarqueTraverse() throws {
        let repos = try #require(pixels(sonde: false))
        let voile = try #require(pixels(sonde: true))
        #expect(
            repos != voile,
            "sonde et repos rendent les mêmes pixels — la marque n'atteint pas les runs")
    }

    /// Un texte **sans terme** ne doit pas bouger en sonde : le voile suit la
    /// marque, pas le mode.
    @Test("le voile ne se pose que sur les marques")
    func leVoileSuitLaMarque() throws {
        func nu(sonde: Bool) -> Data? {
            let corps = ONTTextRenderer.compose([.text("aucun terme ici")], theme: ONTTheme())
            let vue = Text(corps)
                .ontSurvolDesTermes(corps, sonde: sonde)
            .padding(8)
            .frame(width: 320)
            let rendu = ImageRenderer(content: vue)
            rendu.scale = 2
            return rendu.nsImage?.tiffRepresentation
        }
        let repos = try #require(nu(sonde: false))
        let voile = try #require(nu(sonde: true))
        #expect(repos == voile, "le voile s'est posé sans marque")
    }
}
