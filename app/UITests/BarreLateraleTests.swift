import XCTest

/// La barre latérale de l'iPad — regarder, pas vérifier.
@MainActor
final class BarreLateraleTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    private func retenir(_ nom: String) {
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = nom
        capture.lifetime = .keepAlways
        add(capture)
    }

    private func arbre(_ nom: String) {
        let texte = XCTAttachment(string: app.debugDescription)
        texte.name = nom
        texte.lifetime = .keepAlways
        add(texte)
    }

    func testRegarderLaBarreLaterale() {
        Thread.sleep(forTimeInterval: 3)
        retenir("01-onglets-en-haut")
        arbre("arbre-au-depart")

        // `ToggleSideBar` replié, `ToggleSidebar` déplié : UIKit ne met pas la
        // même majuscule des deux côtés. On cherche donc sans en tenir compte.
        let bascule = app.buttons
            .matching(NSPredicate(format: "identifier LIKE[c] 'ToggleSideBar'"))
            .firstMatch
        XCTAssertTrue(bascule.waitForExistence(timeout: 5), "pas de bascule de barre latérale")
        bascule.tap()
        Thread.sleep(forTimeInterval: 2)
        retenir("02-barre-laterale")
        arbre("arbre-barre-laterale")

        // Un livre rédigé, ouvert depuis la barre latérale.
        let livre = app.cells["Sefar Gibbaraya"].firstMatch
        XCTAssertTrue(livre.waitForExistence(timeout: 5), "pas de livre dans la barre latérale")
        livre.tap()
        Thread.sleep(forTimeInterval: 2)
        retenir("03-un-livre-depuis-la-barre")

        // Et une unité, pour vérifier que la pile du livre est bien la sienne.
        let unite = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sefar'"))
            .element(boundBy: 0)
        if unite.waitForExistence(timeout: 3) {
            unite.tap()
            Thread.sleep(forTimeInterval: 3)
            retenir("04-une-unite")
        }

        // Et on revient aux onglets.
        bascule.tap()
        Thread.sleep(forTimeInterval: 2)
        retenir("05-retour-aux-onglets")
    }
}
