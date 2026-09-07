import XCTest

/// L'écran des options de partage, et son aperçu.
///
/// Ce qui est éprouvé ici n'est pas la présence des bascules mais **le lien
/// entre elles et l'aperçu** : un aperçu qui ne bougerait pas serait pire que
/// pas d'aperçu du tout — on croirait avoir vu le résultat.
@MainActor
final class OptionsDePartageTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        Thread.sleep(forTimeInterval: 7)
    }

    /// L'aperçu affiché, relevé parmi les textes de l'écran.
    private func apercu() -> String {
        app.staticTexts.allElementsBoundByIndex
            .map(\.label)
            .first { $0.contains("Quand Elohim") } ?? ""
    }

    func testLApercuSuitLesBascules() {
        app.buttons["Vous"].tap()
        Thread.sleep(forTimeInterval: 1.5)

        let entree = app.staticTexts["Options de partage"]
        XCTAssertTrue(entree.waitForExistence(timeout: 5), "l'entrée est introuvable")
        entree.tap()
        Thread.sleep(forTimeInterval: 1.5)

        let avant = apercu()
        XCTAssertFalse(avant.isEmpty, "l'aperçu ne montre rien")
        XCTAssertTrue(avant.contains("«"), "les chevrons manquent à l'aperçu par défaut")
        XCTAssertTrue(avant.contains("1 Quand"), "les numéros manquent à l'aperçu par défaut")

        let vueAvant = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        vueAvant.name = "options-par-defaut"
        vueAvant.lifetime = .keepAlways
        add(vueAvant)

        // On éteint les guillemets et les numéros, et on regarde l'aperçu.
        // **On vise le curseur, pas la ligne.** Un `tap()` sur l'élément
        // atterrit en son centre, c'est-à-dire sur le libellé — que SwiftUI
        // n'écoute pas. Le curseur est à l'extrémité droite.
        let chevrons = app.switches["Guillemets"]
        let avantBascule = chevrons.value as? String
        chevrons.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: 0.6)
        let apresBascule = chevrons.value as? String
        XCTAssertNotEqual(
            avantBascule, apresBascule,
            "l'interrupteur n'a pas basculé — il valait \(avantBascule ?? "?")")

        app.switches["Numéros de versets"]
            .coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: 1)

        let apres = apercu()
        XCTAssertFalse(
            apres.contains("«"), "les chevrons sont restés — l'aperçu ne suit pas : « \(apres) »")
        XCTAssertFalse(
            apres.contains("1 Quand"), "les numéros sont restés : « \(apres) »")

        let vueApres = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        vueApres.name = "options-sans-chevrons-ni-numeros"
        vueApres.lifetime = .keepAlways
        add(vueApres)
    }
}
