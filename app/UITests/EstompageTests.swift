import UIKit
import XCTest

/// Ce que la sélection doit faire au reste de la page.
///
/// Désigner un verset baisse tous les autres — c'est ce qui le désigne. Le
/// moteur qui l'accomplit demande à SwiftUI de rasteriser la section hors
/// écran, et une section trop haute pour un tampon perdait tout son dessin.
/// La parade — ne poser le moteur que sous un plafond — a d'abord été réglée
/// sur la limite du **simulateur**, 8192 px, moitié moins que celle d'un
/// téléphone. Sur l'appareil, presque aucune section ne passait, et
/// l'estompage ne se produisait plus jamais.
@MainActor
final class EstompageTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    /// La part d'encre **franche** parmi toute l'encre de la page.
    ///
    /// Une proportion, et non un compte : le compte dépend de l'endroit où la
    /// page s'est arrêtée, et comparer deux écrans qui ne montrent pas les
    /// mêmes lignes ne dit rien. La proportion, elle, dit une seule chose —
    /// « ce texte est-il à pleine encre, ou baissé » — et elle la dit où que
    /// l'on soit dans le chapitre.
    ///
    /// C'est la leçon d'une première version qui comparait des comptes bruts :
    /// elle a rapporté un défaut là où il n'y en avait pas, parce que la
    /// sélection fait remonter la page.
    private func partDEncreFranche() -> Double {
        guard let image = XCUIScreen.main.screenshot().image.cgImage else { return -1 }
        let l = image.width, h = image.height
        var octets = [UInt8](repeating: 0, count: l * h)
        guard let ctx = CGContext(data: &octets, width: l, height: h, bitsPerComponent: 8,
                                  bytesPerRow: l, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: 0) else { return -1 }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: l, height: h))

        var e: [Int] = []
        for y in stride(from: Int(Double(h) * 0.20), to: Int(Double(h) * 0.50), by: 2) {
            for x in stride(from: Int(Double(l) * 0.06), to: Int(Double(l) * 0.94), by: 2) {
                e.append(Int(octets[y * l + x]))
            }
        }
        // L'écart au fond compte en valeur absolue : sur un thème sombre,
        // l'encre est plus **claire** que la page, et une mesure signée y
        // verrait une page blanche.
        let fond = e.sorted()[e.count / 2]
        let encre = e.filter { abs($0 - fond) > 25 }
        guard encre.count > 500 else { return -1 }
        let franche = encre.filter { abs($0 - fond) > 90 }
        return Double(franche.count) / Double(encre.count)
    }

    /// Sans sélection, la page est à pleine encre.
    /// Avec, l'essentiel doit être baissé.
    func testDesignerUnVersetBaisseLeReste() {
        // Bereshit 19 : ses sections dépassent le plafond du simulateur, et
        // c'est exactement là que la parade se voyait.
        app.open(URL(string: "ont://read/bereshit/bereshit-19")!)
        Thread.sleep(forTimeInterval: 4)
        let pleine = partDEncreFranche()
        XCTAssertGreaterThan(pleine, 0, "page de départ illisible")

        app.open(URL(string: "ont://read/bereshit/bereshit-19?v=3")!)
        Thread.sleep(forTimeInterval: 4)
        XCTAssertTrue(app.buttons["Partager"].waitForExistence(timeout: 5),
                      "aucun verset n'a été désigné")
        // Descendre d'un écran : le verset désigné reste **plein**, et rester
        // posé dessus diluerait la mesure de ce qu'on cherche. Ce qu'on veut
        // savoir, c'est l'état de ses voisins.
        let page = app.windows.firstMatch
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            .press(forDuration: 0.05,
                   thenDragTo: page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22)),
                   withVelocity: .default, thenHoldForDuration: 0.02)
        Thread.sleep(forTimeInterval: 1.5)

        let designee = partDEncreFranche()
        print("ONT-ESTOMPE part franche : sans selection \(pleine), voisins avec \(designee)")

        XCTAssertGreaterThan(designee, -0.5, "la page s'est vidée en désignant un verset")
        XCTAssertLessThan(
            designee, pleine * 0.6,
            "le reste de la page n'est pas baissé — part d'encre franche \(pleine) puis \(designee)"
        )
    }
}
