import UIKit
import XCTest

/// Ce que change un changement de thème, et ce qu'il oublie.
///
/// Rapporté à l'usage : « c'est seulement quand je rouvre que le thème se met
/// totalement correctement ». Autrement dit, quelque chose reste dans l'ancien
/// habit jusqu'au prochain lancement — et un écran qu'on ne quitte pas ne le
/// montre jamais.
///
/// Le parcours capture donc le **même écran** trois fois : avant, juste après
/// le changement, et après relance. Ce qui diffère entre la deuxième et la
/// troisième est précisément le défaut.
@MainActor
final class ChangementDeThemeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
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

    /// Le défaut rapporté : la feuille garde son ancien habit.
    ///
    /// On photographie **sans refermer**. Les premiers essais fermaient la
    /// feuille avant de regarder, et ne voyaient donc rien : l'écran de
    /// lecture, lui, se remet à jour tout de suite.
    func testLaFeuilleSuitLeThemeSansAttendre() {
        app.open(URL(string: "ont://read/bereshit/bereshit-1")!)
        Thread.sleep(forTimeInterval: 3)

        app.buttons["Lecture"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2)
        for _ in 0..<6 { app.swipeUp(); Thread.sleep(forTimeInterval: 0.7) }
        retenir("10-feuille-en-parchemin")

        // Le menu ouvert : c'est là que se voyait le liseré collé à la
        // première ligne, quelle que soit la valeur retenue.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Thème'"))
            .firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.5)
        retenir("09-menu-ouvert")
        app.buttons["Parchemin"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.5)

        basculer(vers: "Mystique")
        retenir("11-feuille-apres-mystique")
        exigerUneEncreClaire("après être passé au mystique, feuille ouverte")

        basculer(vers: "Clair")
        retenir("12-feuille-apres-clair")

        basculer(vers: "Sombre")
        retenir("13-feuille-apres-sombre")
        exigerUneEncreClaire("après être passé au sombre, feuille ouverte")

        basculer(vers: "Parchemin")
        retenir("14-feuille-apres-parchemin")

        // Et si l'on referme puis rouvre la feuille, sans relancer l'app ?
        basculer(vers: "Mystique")
        app.buttons["OK"].firstMatch.tap(); Thread.sleep(forTimeInterval: 2)
        app.buttons["Lecture"].firstMatch.tap(); Thread.sleep(forTimeInterval: 2)
        for _ in 0..<6 { app.swipeUp(); Thread.sleep(forTimeInterval: 0.7) }
        retenir("15-feuille-rouverte")
    }

    /// Sur un thème sombre, l'encre doit être **plus claire** que le fond.
    ///
    /// C'est l'invariant que le défaut violait, et il ne demande aucune
    /// coordonnée : « Thème » s'écrivait en noir sur l'aubergine parce que la
    /// feuille gardait le schéma de couleurs qu'elle avait à son ouverture.
    /// Une feuille dont l'encre est plus sombre que sa page n'a pas suivi.
    private func exigerUneEncreClaire(_ quand: String) {
        guard let image = XCUIScreen.main.screenshot().image.cgImage else { return }
        let l = image.width, h = image.height
        var octets = [UInt8](repeating: 0, count: l * h)
        guard let ctx = CGContext(data: &octets, width: l, height: h, bitsPerComponent: 8,
                                  bytesPerRow: l, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: 0) else { return }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: l, height: h))

        // Le bas de la feuille : les réglages, là où vivent les libellés.
        var e: [Int] = []
        for y in stride(from: Int(Double(h) * 0.62), to: Int(Double(h) * 0.90), by: 2) {
            for x in stride(from: Int(Double(l) * 0.06), to: Int(Double(l) * 0.94), by: 2) {
                e.append(Int(octets[y * l + x]))
            }
        }
        let fond = e.sorted()[e.count / 2]
        let encre = e.filter { abs($0 - fond) > 30 }
        guard encre.count > 300 else { return }
        let claire = encre.filter { $0 > fond }.count
        XCTAssertGreaterThan(
            Double(claire) / Double(encre.count), 0.6,
            "\(quand) : l'encre de la feuille reste plus sombre que sa page — "
                + "le schéma de couleurs n'a pas suivi le thème"
        )
    }

    /// Choisit un thème dans le menu, sans refermer la feuille.
    private func basculer(vers theme: String) {
        let choix = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Thème'")
        ).firstMatch
        guard choix.waitForExistence(timeout: 5) else { return }
        choix.tap(); Thread.sleep(forTimeInterval: 1.2)
        app.buttons[theme].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2.5)
    }

    /// Change le thème depuis les réglages de lecture.
    private func choisir(_ theme: String) {
        app.buttons["Lecture"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2)
        for _ in 0..<6 { app.swipeUp(); Thread.sleep(forTimeInterval: 0.7) }
        let choix = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Thème'")
        ).firstMatch
        guard choix.waitForExistence(timeout: 5) else { retenir("SELECTEUR-ABSENT"); return }
        choix.tap(); Thread.sleep(forTimeInterval: 1.2)
        app.buttons[theme].firstMatch.tap(); Thread.sleep(forTimeInterval: 1.5)
        app.buttons["OK"].firstMatch.tap(); Thread.sleep(forTimeInterval: 2)
    }

    /// Fait le tour des onglets et retient chacun.
    private func tourDesOnglets(_ moment: String) {
        for onglet in ["Qahal", "Bible", "Lexique", "Vous"] {
            app.buttons[onglet].firstMatch.tap()
            Thread.sleep(forTimeInterval: 2)
            retenir("\(moment)-\(onglet)")
        }
    }

    /// Tous les onglets, juste après le changement puis après relance.
    ///
    /// L'écran de lecture, lui, se remet à jour tout de suite — mesuré, écart
    /// nul entre les deux moments. Le défaut vit donc ailleurs, et un onglet
    /// qu'on ne visite pas au moment du changement est le suspect naturel.
    func testTousLesOngletsSuiventLeChangement() {
        app.open(URL(string: "ont://read/bereshit/bereshit-3")!)
        Thread.sleep(forTimeInterval: 3)
        choisir("Mystique")
        tourDesOnglets("A-juste-apres")

        app.terminate(); Thread.sleep(forTimeInterval: 1)
        app.launch(); Thread.sleep(forTimeInterval: 3)
        tourDesOnglets("B-apres-relance")

        // Et le retour au clair, l'autre sens du geste.
        app.open(URL(string: "ont://read/bereshit/bereshit-3")!)
        Thread.sleep(forTimeInterval: 3)
        choisir("Parchemin")
        tourDesOnglets("C-retour-juste-apres")

        app.terminate(); Thread.sleep(forTimeInterval: 1)
        app.launch(); Thread.sleep(forTimeInterval: 3)
        tourDesOnglets("D-retour-apres-relance")
    }


    func testUnChangementDeThemePrendEffetTOutDeSuite() {
        app.open(URL(string: "ont://read/bereshit/bereshit-3")!)
        Thread.sleep(forTimeInterval: 3)
        retenir("01-avant")

        // Les réglages, puis le thème.
        app.buttons["Lecture"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2)
        for _ in 0..<6 { app.swipeUp(); Thread.sleep(forTimeInterval: 0.8) }
        Thread.sleep(forTimeInterval: 1)
        retenir("02-reglages")

        // Le sélecteur s'annonce « Thème, <valeur courante> ».
        let choix = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Thème'")
        ).firstMatch
        if choix.waitForExistence(timeout: 5) {
            choix.tap()
            Thread.sleep(forTimeInterval: 1.5)
            retenir("03-menu-des-themes")
            app.buttons["Mystique"].firstMatch.tap()
            Thread.sleep(forTimeInterval: 2)
        } else {
            retenir("03-selecteur-ABSENT")
        }
        retenir("04-reglages-en-mystique")

        app.buttons["OK"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2.5)
        retenir("05-lecture-juste-apres")

        // Et la même page, après relance.
        app.terminate()
        Thread.sleep(forTimeInterval: 1)
        app.launch()
        Thread.sleep(forTimeInterval: 2)
        app.open(URL(string: "ont://read/bereshit/bereshit-3")!)
        Thread.sleep(forTimeInterval: 3)
        retenir("06-lecture-apres-relance")

        // Les onglets, où le chrome vit.
        app.buttons["Vous"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2)
        retenir("07-vous-apres-relance")
    }
}
