import XCTest

/// Combien de temps la barre latérale tient-elle ?
///
/// Ouverte en **portrait**, elle se referme au premier choix : on touche un
/// livre, et la barre du haut revient. Ça ressemble à un défaut, et ça n'en est
/// pas un — c'est ce que fait iPadOS, et ce que fait Music. En portrait il n'y
/// a pas la largeur pour tenir une barre **et** une page : la barre est un
/// recouvrement, et un recouvrement se retire dès qu'on a choisi.
///
/// En **paysage**, il y a la place : elle reste à côté, et c'est là qu'elle
/// tient sa promesse.
///
/// On éprouve les deux. Le jour où le portrait se met à garder la barre, ou le
/// paysage à la lâcher, on veut l'apprendre ici — pas par quelqu'un qui trouve
/// ça bizarre.
@MainActor
final class BarreQuiTientTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDown() {
        // L'orientation est un état du simulateur : elle survit au test, et le
        // suivant partirait couché sans savoir pourquoi.
        XCUIDevice.shared.orientation = .portrait
    }

    private func retenir(_ nom: String) {
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = nom
        capture.lifetime = .keepAlways
        add(capture)
    }

    /// La bascule, quel que soit l'état.
    ///
    /// UIKit ne met pas la même majuscule des deux côtés — `ToggleSideBar`
    /// repliée, `ToggleSidebar` dépliée — donc on cherche sans en tenir compte.
    private var bascule: XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "identifier LIKE[c] 'ToggleSideBar'"))
            .firstMatch
    }

    /// Le signe le plus sûr que la barre est dépliée.
    ///
    /// Un livre n'existe **que** dans la barre latérale : jamais dans la barre
    /// d'onglets, où il n'y aurait pas la place.
    private var unLivre: XCUIElement { app.cells["Sefar Gibbaraya"] }

    /// Attend que la fenêtre soit vraiment couchée, ou vraiment debout.
    ///
    /// Dormir un nombre de secondes choisi au jugé marche jusqu'au jour où la
    /// machine est chargée : le geste part pendant la rotation, tombe à côté,
    /// et le test échoue sans que rien n'ait changé dans l'app. On regarde donc
    /// la fenêtre au lieu de parier sur une durée.
    private func attendreLaRotation(couchée: Bool, fichier: StaticString = #filePath, ligne: UInt = #line) {
        let limite = Date().addingTimeInterval(15)
        while Date() < limite {
            let cadre = app.windows.firstMatch.frame
            if (cadre.width > cadre.height) == couchée, cadre.width > 0 {
                // La fenêtre est en place ; laisser la mise en page se poser.
                Thread.sleep(forTimeInterval: 1.5)
                return
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTFail("la rotation n'a pas abouti", file: fichier, line: ligne)
    }

    private func ouvrirLaBarre(_ étape: String) {
        XCTAssertTrue(bascule.waitForExistence(timeout: 8), "pas de bascule \(étape)")
        bascule.tap()
        XCTAssertTrue(
            unLivre.waitForExistence(timeout: 8),
            "la barre ne s'est pas ouverte \(étape)"
        )
    }

    func testEnPaysageElleReste() {
        XCUIDevice.shared.orientation = .landscapeLeft
        attendreLaRotation(couchée: true)

        ouvrirLaBarre("en paysage")
        retenir("01-paysage-ouverte")

        app.cells["Lexique"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2)
        retenir("02-paysage-apres-un-choix")

        XCTAssertTrue(unLivre.exists, "la barre devait rester à côté de la page")
    }

    func testEnPortraitElleSeRetireApresLeChoix() {
        XCUIDevice.shared.orientation = .portrait
        attendreLaRotation(couchée: false)

        ouvrirLaBarre("en portrait")
        retenir("03-portrait-ouverte")

        app.cells["Lexique"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2)
        retenir("04-portrait-apres-un-choix")

        XCTAssertFalse(
            unLivre.exists,
            "le portrait garde la barre — iPadOS a changé, ou nous l'avons forcée"
        )
        // Et le choix a bien été pris : la barre s'est retirée en faisant son
        // travail, elle n'a pas simplement disparu.
        XCTAssertTrue(
            app.staticTexts["Lexique"].firstMatch.waitForExistence(timeout: 5),
            "le choix fait dans la barre n'a pas abouti"
        )
    }
}
