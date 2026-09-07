import XCTest

/// Où l'entrée des options de partage se trouve dans l'onglet Vous.
@MainActor
final class OuSontLesOptionsTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        Thread.sleep(forTimeInterval: 7)
    }

    func testLEntreeEstDansLaSectionLecture() {
        app.buttons["Vous"].tap()
        Thread.sleep(forTimeInterval: 2)

        let entree = app.staticTexts["Options de partage"]
        XCTAssertTrue(entree.waitForExistence(timeout: 5), "l'entrée est introuvable")

        let vue = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        vue.name = "ou-sont-les-options"
        vue.lifetime = .keepAlways
        add(vue)
    }
}
