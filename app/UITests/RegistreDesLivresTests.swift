import XCTest

/// Le second nom d'un livre suit-il « Le français reçu » ?
///
/// Il ne le suivait pas. Le corpus écrit une glose pour chaque livre, le site
/// l'affiche depuis toujours, et l'app la jetait à la traduction du schéma :
/// `BookOutline` ne déclarait pas le champ. Registre éteint, la liste disait
/// encore « Actes des Apôtres » là où `ontbible.com` disait « les gevurot de
/// YHWH par ses neviim ».
@MainActor
final class RegistreDesLivresTests: XCTestCase {
    private var app: XCUIApplication!
    private let glose = "les gevurot de YHWH par ses neviim"

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        Thread.sleep(forTimeInterval: 7)
    }

    /// La ligne du livre, dans la liste de sa section.
    ///
    /// **On touche la section par son rang, pas par son nom.** Deux corpus
    /// portent un « Ketouvim » ; c'est le second — celui de la Berit Hadashah —
    /// qui contient le livre. Un `staticTexts["Ketouvim"]` toucherait le
    /// premier venu, et le test dirait le contraire de ce qu'il mesure.
    func testLaLigneDuLivreDitLaGlose() {
        let sections = app.staticTexts.matching(identifier: "Ketouvim")
        XCTAssertEqual(
            sections.count, 2,
            "le corpus n'a plus deux sections « Ketouvim » — le rang ne veut plus rien dire"
        )
        sections.element(boundBy: 1).tap()
        Thread.sleep(forTimeInterval: 2)

        XCTAssertTrue(
            app.staticTexts[glose].waitForExistence(timeout: 5),
            "la ligne du livre ne porte pas la glose — à l'écran : "
                + "\(Array(app.staticTexts.allElementsBoundByIndex.map(\.label).prefix(20)))"
        )
        XCTAssertFalse(
            app.staticTexts["Actes des Apôtres"].exists,
            "la ligne du livre porte encore le pont français, registre éteint"
        )
    }

    /// Et la barre de la page du livre, l'autre endroit où le français
    /// s'affichait sans condition.
    func testLaBarreDuLivreDitLaGlose() {
        app.open(URL(string: "ont://read/gevurot-ha-neviim")!)
        Thread.sleep(forTimeInterval: 3)

        XCTAssertTrue(
            app.staticTexts[glose].waitForExistence(timeout: 5),
            "la barre du livre ne porte pas la glose"
        )
        XCTAssertFalse(
            app.staticTexts["Actes des Apôtres"].exists,
            "la barre du livre porte encore le pont français, registre éteint"
        )
    }
}
