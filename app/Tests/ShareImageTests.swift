import Foundation
import ONTDesignSystem
import ONTKit
import Testing
import UIKit

/// L'image de partage.
@MainActor
struct ShareImageTests {
    // Construits en Swift, et non décodés d'une chaîne JSON.
    //
    // Ce test porte sur le **rendu** d'une carte de partage. Le faire passer
    // par un décodeur l'attachait au format du pipeline : il cassait quand la
    // forme du JSON bougeait, en accusant la mise en page. Le décodage a ses
    // propres tests, dans ONTDataTests.
    private func verses(_ nodes: [Inline]) -> [Verse] {
        [Verse(n: 1, nodes: nodes)]
    }

    @Test("la carte sort au format carré attendu")
    func rendersSquare() throws {
        let v = verses([
            .text("Quand "),
            .term("Elohim", lemma: "elohim"),
            .text(" commença à orchestrer les Cieux et la Terre —"),
        ])
        let image = try #require(
            ONTShareImage.render(verses: v, reference: "Bereshit 1:1", theme: ONTTheme())
        )
        #expect(image.size.width == ONTVerseCard.side)
        #expect(image.size.height == ONTVerseCard.side)

        // Déposée pour inspection à l'œil : une image de partage se juge en la
        // regardant, pas en comptant ses pixels.
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("carte-partage.png")
        try #require(image.pngData()).write(to: url)
        print("CARTE_PARTAGE=\(url.path)")
    }

    @Test("un long passage ne déborde pas — le corps décroît")
    func longPassageShrinks() {
        #expect(ONTShareImage.size(forLength: 80) > ONTShareImage.size(forLength: 500))
        #expect(ONTShareImage.size(forLength: 2000) >= 32)
    }
}
