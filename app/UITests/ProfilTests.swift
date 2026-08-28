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
    ///
    /// **On le désigne par son identifiant, jamais par son invite** : l'invite
    /// s'efface dès qu'il y a du texte, donc un relevé qui la cherche trouve le
    /// champ vide et le perd rempli. C'est ce qui a fait échouer ce test au
    /// second passage, alors qu'il avait passé au premier.
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
        // Le nom d'usage se replie **à la frappe** : on tape ce qu'un lecteur
        // taperait vraiment — avec son arobase d'habitude et une majuscule — et
        // on vérifie ce qui reste.
        vider(app.textFields["profil.nomDUsage"])
        app.typeText("@Gloiiire_")

        vider(app.textFields["profil.prenom"])
        app.typeText("Gloire")
        vider(app.textFields["profil.nom"])
        app.typeText("Bikouta")
        // Un `TextField(axis: .vertical)` reste un **champ de texte** pour
        // l'accessibilité, jamais une `TextView` : il grandit, il ne change pas
        // de nature.
        vider(app.textFields["profil.bio"])
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

        // **On éprouve l'invariant, pas la fidélité du clavier.**
        //
        // Attendre « 19 / 280 » pour « Traducteur de l'ONT » a relevé « 27 » :
        // la saisie automatique d'iOS complète et corrige, et ce que le champ
        // porte n'est pas toujours ce qu'on a tapé. Le test mesurait donc le
        // clavier du simulateur au lieu du lien entre le champ et son
        // décompte — et il aurait rougi un jour pour un réglage de saisie.
        let ecrit = (app.textFields["profil.bio"].value as? String) ?? ""
        XCTAssertTrue(
            app.staticTexts["\(ecrit.count) / 280"].waitForExistence(timeout: 3),
            "le décompte ne suit pas ce que le champ porte (\(ecrit.count) signes) "
                + "— à l'écran : "
                + "\(Array(app.staticTexts.allElementsBoundByIndex.map(\.label).prefix(20)))")

        // Et le nom, lui, se relit tel qu'on l'a posé.
        XCTAssertEqual(
            app.textFields["profil.nomDUsage"].value as? String, "gloiiire_",
            "le nom d'usage ne s'est pas replié à la frappe")
        XCTAssertEqual(app.textFields["profil.prenom"].value as? String, "Gloire")
        XCTAssertEqual(app.textFields["profil.nom"].value as? String, "Bikouta")
    }
}
