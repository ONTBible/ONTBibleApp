import XCTest

/// L'écran de profil, tel qu'il s'affiche.
@MainActor
final class ProfilTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        Thread.sleep(forTimeInterval: 7)
    }

    /// Vide un champ, quel que soit ce qu'il portait.
    private func vider(_ champ: XCUIElement) {
        champ.tap()
        guard let texte = champ.value as? String, !texte.isEmpty else { return }
        champ.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: texte.count))
    }

    func testLEcranDeProfilSeRemplitEtSeRelit() {
        app.buttons["Vous"].tap()
        Thread.sleep(forTimeInterval: 1.5)

        // L'en-tête réel n'existe qu'une fois connecté ; on passe donc par
        // l'aperçu de développement, en bas de l'écran. Il ouvre **le même**
        // éditeur — le profil est local, rien n'est simulé.
        let entree = app.staticTexts["Profil"]
        app.swipeUp()
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(entree.waitForExistence(timeout: 5), "l'entrée « Profil » est introuvable")
        entree.tap()
        Thread.sleep(forTimeInterval: 1.5)

        // **Vider avant d'écrire.** Le profil est persistant : sans ça le test
        // s'ajoute à ce que les essais précédents avaient laissé, et on relève
        // « GloireGloireGloire ». Un instrument qui accumule ne mesure pas deux
        // fois la même chose.
        vider(app.textFields["Prénom"])
        app.typeText("Gloire")
        vider(app.textFields["Nom"])
        app.typeText("Bikouta")
        // Un `TextField(axis: .vertical)` reste un **champ de texte** pour
        // l'accessibilité, jamais une `TextView` : il grandit, il ne change pas
        // de nature.
        vider(app.textFields["Quelques mots sur vous"])
        app.typeText("Traducteur de l'ONT")
        Thread.sleep(forTimeInterval: 1)

        // Le clavier masque la bio et la mention qui dit qui lit tout ça —
        // c'est-à-dire précisément ce que la capture doit montrer.
        app.swipeDown()
        Thread.sleep(forTimeInterval: 1)

        let vue = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        vue.name = "profil-rempli"
        vue.lifetime = .keepAlways
        add(vue)

        XCTAssertTrue(
            app.staticTexts["19 / 280"].waitForExistence(timeout: 3),
            "le décompte de la bio ne suit pas la frappe — à l'écran : "
                + "\(Array(app.staticTexts.allElementsBoundByIndex.map(\.label).prefix(20)))")
    }
}
