import XCTest

/// Le verset du jour mène au texte.
///
/// La carte donnait un verset sans dire d'où il venait — un fragment sans son
/// avant ni son après, alors que le renvoi était écrit dessus.
@MainActor
final class VersetDuJourTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        Thread.sleep(forTimeInterval: 7)
    }

    func testToucherLaCarteOuvreLePassage() {
        app.buttons["Qahal"].tap()
        Thread.sleep(forTimeInterval: 2)

        // Le renvoi porté par la carte — « Bereshit 3:15 » ou autre selon le
        // jour. On le retient **avant** de toucher : c'est lui qui dira si l'on
        // est arrivé au bon endroit, et il change tous les jours.
        let renvoi = app.staticTexts.allElementsBoundByIndex
            .map(\.label)
            .first { $0.contains(":") && $0.count < 40 }
        XCTAssertNotNil(renvoi, "la carte du verset du jour ne porte pas de renvoi")

        // Toucher la carte, pas le bouton de partage : on vise le texte du
        // verset, qui est la plus grande surface de la carte.
        app.staticTexts[renvoi ?? ""].tap()
        Thread.sleep(forTimeInterval: 3)

        let vue = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        vue.name = "arrive-sur-le-passage"
        vue.lifetime = .keepAlways
        add(vue)

        XCTAssertTrue(
            app.buttons["Bible"].isSelected,
            "l'onglet Bible n'est pas au premier plan après le toucher")

        // Et le livre du renvoi est bien celui qu'on lit.
        let livre = String((renvoi ?? "").split(separator: ":").first ?? "")
            .split(separator: " ").dropLast().joined(separator: " ")
        XCTAssertFalse(livre.isEmpty, "le renvoi « \(renvoi ?? "") » ne nomme pas de livre")
        XCTAssertTrue(
            app.staticTexts.allElementsBoundByIndex.contains { $0.label.contains(livre) },
            "« \(livre) » ne paraît nulle part après le toucher")
    }
}
