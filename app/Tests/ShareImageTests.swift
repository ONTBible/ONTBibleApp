import Foundation
import ONTDesignSystem
import ONTKit
import Testing
import UIKit

/// L'image de partage.
@MainActor
struct ShareImageTests {
    private func verses(_ json: String) throws -> [Verse] {
        try JSONDecoder().decode([Verse].self, from: Data(json.utf8))
    }

    @Test("la carte sort au format carré attendu")
    func rendersSquare() throws {
        let v = try verses(#"[{"n":1,"nodes":[{"t":"text","v":"Quand "},{"t":"term","v":"Elohim","lemma":"elohim"},{"t":"text","v":" commença à orchestrer les Cieux et la Terre —"}]}]"#)
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
