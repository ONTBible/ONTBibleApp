import XCTest

/// La page des surlignages, telle qu'elle s'affiche.
///
/// Aucune route d'URL ne mène à un onglet — `ont://` ne connaît que les
/// passages, les termes et les partages. On y va donc comme le lecteur : en
/// touchant.
@MainActor
final class SurlignagesTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        Thread.sleep(forTimeInterval: 7)
    }

    func testLaPageMontreCeQuiAEteMarque() {
        app.buttons["Vous"].tap()
        Thread.sleep(forTimeInterval: 1.5)

        // Une `NavigationLink` dont le libellé est un `LabeledContent` ne
        // s'expose pas comme bouton : SwiftUI en fait deux textes, le titre et
        // son décompte. On touche le titre, et le toucher traverse jusqu'à la
        // ligne — un `descendants(matching: .any)` attrape au contraire le
        // premier conteneur venu, qui n'est pas touchable.
        let entree = app.staticTexts["Surlignages"]
        XCTAssertTrue(
            entree.waitForExistence(timeout: 5),
            "l'entrée « Surlignages » manque à l'onglet Vous — à l'écran : "
                + "\(Array(app.descendants(matching: .any).allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }.prefix(30)))")
        entree.tap()
        Thread.sleep(forTimeInterval: 2)

        let vue = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        vue.name = "mes-surlignages"
        vue.lifetime = .keepAlways
        add(vue)

        // Le livre en en-tête, et un verset marqué dessous.
        XCTAssertTrue(
            app.staticTexts["Bereshit"].waitForExistence(timeout: 5),
            "le livre ne fait pas d'en-tête — à l'écran : "
                + "\(Array(app.staticTexts.allElementsBoundByIndex.map(\.label).prefix(25)))")
    }
}
