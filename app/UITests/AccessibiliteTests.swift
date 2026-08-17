import XCTest

/// Ce que l'app donne à lire à VoiceOver.
///
/// Un bloc de prose est un unique `Text` dont chaque fragment porte un lien —
/// le renvoi qui rend le verset touchable. SwiftUI en faisait autant
/// d'éléments : quatre-vingt-quinze pour Bereshit 11, annoncés « lien » et
/// coupés là où le balisage change, pas là où la phrase finit. Le texte
/// n'était pas muet ; il était haché.
@MainActor
final class AccessibiliteTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        app.open(URL(string: "ont://read/bereshit/bereshit-11")!)
        Thread.sleep(forTimeInterval: 4)
    }

    /// La prose ne se présente plus en miettes.
    func testLaProseNEstPasHacheeEnLiens() {
        XCTAssertEqual(
            app.links.count, 0,
            "la lecture expose encore des liens : VoiceOver les annoncera un à un"
        )
    }

    /// Et elle se présente en phrases, numéros de verset **dits**.
    func testLesVersetsSontAnnoncesEtLisibles() {
        let proses = app.staticTexts.allElementsBoundByIndex
            .map(\.label)
            .filter { $0.contains("Verset ") }
        XCTAssertFalse(proses.isEmpty, "aucun bloc de prose lisible n'est exposé")

        let premier = proses.first ?? ""
        XCTAssertTrue(
            premier.hasPrefix("Verset 1."),
            "le numéro du verset n'est pas prononcé — reçu : « \(premier.prefix(40)) »"
        )
        // Une section entière, pas un fragment : le défaut d'origine rendait
        // des bouts de quelques mots.
        XCTAssertGreaterThan(
            premier.count, 400,
            "le bloc annoncé est trop court pour être une section — \(premier.count) signes"
        )
    }

    /// Ce que la substitution ne doit **pas** coûter : l'appui reste vivant.
    ///
    /// La représentation ne remplace que l'arbre d'accessibilité ; la détection
    /// tactile ne passe pas par lui. Toucher un verset doit toujours ouvrir la
    /// carte d'actions.
    func testToucherUnVersetOuvreToujoursLaCarte() {
        let page = app.windows.firstMatch
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(
            app.buttons["Partager"].waitForExistence(timeout: 5),
            "toucher un verset n'ouvre plus la carte d'actions"
        )
    }
}
