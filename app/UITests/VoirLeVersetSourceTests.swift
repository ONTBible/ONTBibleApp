import XCTest

/// Un banc : faire le vrai geste et regarder l'écran.
///
/// `ImageRenderer` ne matérialise ni les zones défilantes ni les dispositions
/// sur mesure — trois tentatives, trois images vides. Le seul instrument qui
/// répond à « est-ce que ça se rend » est un doigt dans l'app.
@MainActor
final class VoirLeVersetSourceTests: XCTestCase {
    func testOuvrirParAppuiLong() throws {
        let app = XCUIApplication()
        app.launch()
        app.open(URL(string: "ont://read/bereshit/bereshit-1")!)
        Thread.sleep(forTimeInterval: 5)

        // Le premier verset, au tiers de la hauteur : sous le titre et le
        // sous-titre, dans le corps du texte.
        let fenetre = app.windows.firstMatch
        let cible = fenetre.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
        cible.press(forDuration: 0.9)
        Thread.sleep(forTimeInterval: 3)

        // **Une pièce jointe, et non `/tmp`.** Sur l'appareil, le bac à sable
        // refuse d'y écrire — « You don't have permission to save the file » —
        // et le banc meurt sur son propre relevé, avant d'avoir rien dit du
        // geste. `xcresulttool export attachments` les sort après coup.
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = "feuille-source"
        capture.lifetime = .keepAlways
        add(capture)

        // **Pas de `isHittable` ici.** XCUITest ne sait pas calculer le point
        // d'activation d'un mot hébreu — « Activation point invalid and no
        // suggested hit points » — et la sonde meurt sur la chose même qu'elle
        // venait constater. On lit les libellés, on ne les interroge pas.
        let visibles = app.staticTexts.allElementsBoundByIndex.map(\.label).prefix(16)
        print("À-L-ÉCRAN=\(Array(visibles))")
    }
}
