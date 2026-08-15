import UIKit
import XCTest

/// Ne rien vérifier : **regarder**.
///
/// Compter l'encre dit qu'une page n'est pas nue ; ça ne dit pas ce qu'elle
/// montre. Ce parcours attache une capture à chaque étape, pour qu'on puisse
/// les ouvrir une à une — c'est la seule façon de voir ce que voit une main.
@MainActor
final class RegarderTests: XCTestCase {
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

    private func glisser(dx0: CGFloat, dx1: CGFloat, dy: CGFloat = 0.55) {
        let page = app.windows.firstMatch
        page.coordinate(withNormalizedOffset: CGVector(dx: dx0, dy: dy))
            .press(forDuration: 0.08,
                   thenDragTo: page.coordinate(withNormalizedOffset: CGVector(dx: dx1, dy: dy)),
                   withVelocity: .default, thenHoldForDuration: 0.05)
    }

    func testRegarderBereshit11() {
        app.open(URL(string: "ont://read/bereshit/bereshit-11")!)
        Thread.sleep(forTimeInterval: 3)
        retenir("01-ouverture-ch11")

        // Descendre trois fois : le texte est-il là plus bas ?
        for pas in 1...3 {
            glisser(dx0: 0.5, dx1: 0.5, dy: 0.5)
            let page = app.windows.firstMatch
            page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82))
                .press(forDuration: 0.05,
                       thenDragTo: page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18)),
                       withVelocity: .default, thenHoldForDuration: 0.02)
            Thread.sleep(forTimeInterval: 0.8)
            retenir("02-descente-\(pas)")
        }

        // Y arriver par le geste, depuis le 10.
        app.open(URL(string: "ont://read/bereshit/bereshit-10")!)
        Thread.sleep(forTimeInterval: 3)
        retenir("03-ch10-avant-le-geste")
        glisser(dx0: 0.88, dx1: 0.08)
        Thread.sleep(forTimeInterval: 0.15)
        retenir("04-juste-apres-le-geste")
        Thread.sleep(forTimeInterval: 2)
        retenir("05-deux-secondes-apres")

        // Et deux gestes enchaînés, puis un retour au bord.
        glisser(dx0: 0.88, dx1: 0.08)
        glisser(dx0: 0.88, dx1: 0.08)
        Thread.sleep(forTimeInterval: 2)
        retenir("06-apres-deux-gestes-enchaines")
        glisser(dx0: 0.01, dx1: 0.92)
        Thread.sleep(forTimeInterval: 2)
        retenir("07-apres-retour-au-bord")
    }
}
