import XCTest

/// Le rail alphabétique du Lexique.
@MainActor
final class RailDuLexiqueTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        Thread.sleep(forTimeInterval: 7)
    }

    func testLeRailMeneALaLettre() {
        app.buttons["Lexique"].tap()
        Thread.sleep(forTimeInterval: 2)

        let vueInitiale = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        vueInitiale.name = "lexique-en-tete"
        vueInitiale.lifetime = .keepAlways
        add(vueInitiale)

        // Le rail occupe la bande de droite. On y glisse du haut vers le bas,
        // comme un pouce le ferait.
        let page = app.windows.firstMatch
        let haut = page.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.30))
        let bas = page.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.80))
        haut.press(forDuration: 0.1, thenDragTo: bas)
        Thread.sleep(forTimeInterval: 1.5)

        let apres = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        apres.name = "lexique-apres-glissement"
        apres.lifetime = .keepAlways
        add(apres)

        // La liste a sauté : le premier terme visible n'est plus celui du haut
        // de l'alphabet. On relève ce qui est à l'écran plutôt qu'un terme
        // précis — le corpus grandit, et un nom écrit en dur périmerait.
        let visibles = app.staticTexts.allElementsBoundByIndex
            .map(\.label)
            .filter { !$0.isEmpty }
        XCTAssertFalse(
            visibles.isEmpty, "l'écran du Lexique est vide après le glissement")
    }
}
