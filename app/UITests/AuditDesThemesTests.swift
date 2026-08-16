import XCTest

/// Un balayage : chaque écran, dans le thème du moment.
///
/// Un thème ne se relit pas, il se regarde. Une couleur oubliée sur un écran
/// qu'on ouvre rarement ne se voit ni au compilateur, ni au test unitaire, ni
/// à la relecture — seulement à l'usage, et souvent par le lecteur avant nous.
///
/// Le thème n'est pas choisi ici : il est écrit dans les préférences avant le
/// lancement. C'est ce qui permet de rejouer le même parcours pour les quatre
/// sans dépendre de la navigation dans les réglages.
@MainActor
final class AuditDesThemesTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        Thread.sleep(forTimeInterval: 2)
    }

    private func retenir(_ nom: String) {
        let c = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        c.name = nom
        c.lifetime = .keepAlways
        add(c)
    }

    private func ouvrir(_ url: String, _ nom: String, attente: TimeInterval = 3) {
        app.open(URL(string: url)!)
        Thread.sleep(forTimeInterval: attente)
        retenir(nom)
    }

    private func toucher(_ libelle: String, _ nom: String, attente: TimeInterval = 2) {
        let b = app.buttons[libelle].firstMatch
        guard b.waitForExistence(timeout: 5) else {
            retenir("\(nom)-ABSENT")
            return
        }
        b.tap()
        Thread.sleep(forTimeInterval: attente)
        retenir(nom)
    }

    func testParcourirTousLesEcrans() {
        retenir("01-accueil")

        toucher("Qahal", "02-qahal")
        toucher("Vous", "03-vous")
        toucher("Lexique", "04-lexique")
        toucher("Bible", "05-bible-table")

        ouvrir("ont://read/bereshit/bereshit-3", "06-lecture")
        ouvrir("ont://read/bereshit/bereshit-3?v=2", "07-lecture-selection", attente: 4)

        // La fiche d'un intraduisible — l'écran qui a révélé l'oubli.
        ouvrir("ont://term/elohim", "08-fiche-terme", attente: 4)

        // Les réglages de lecture, atteints par la barre.
        ouvrir("ont://read/bereshit/bereshit-3", "09-retour-lecture")
        toucher("Lecture", "10-reglages-lecture", attente: 3)
    }
}
