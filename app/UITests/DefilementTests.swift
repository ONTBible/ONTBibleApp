import UIKit
import XCTest

/// **Ce que coûte lire, et non désigner.**
///
/// La désignation a été mesurée et corrigée ; l'auteur a continué de dire
/// « c'est lent ». Un banc qui ne mesure qu'un geste ne peut pas le contredire
/// — il peut seulement ne pas voir ce qu'il ne regarde pas.
///
/// Celui-ci mesure le défilement, qui est le geste de la lecture : on fait
/// glisser, et on attend que la page se pose.
@MainActor
final class DefilementTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    private func empreinte() -> Int {
        guard let image = XCUIScreen.main.screenshot().image.cgImage else { return -1 }
        let l = image.width, h = image.height
        var octets = [UInt8](repeating: 0, count: l * h)
        guard let ctx = CGContext(data: &octets, width: l, height: h, bitsPerComponent: 8,
                                  bytesPerRow: l, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: 0) else { return -1 }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: l, height: h))
        var somme = 0
        for y in stride(from: Int(Double(h) * 0.2), to: Int(Double(h) * 0.8), by: 7) {
            for x in stride(from: Int(Double(l) * 0.1), to: Int(Double(l) * 0.9), by: 7) {
                somme = somme &* 31 &+ Int(octets[y * l + x])
            }
        }
        return somme
    }

    /// Le temps entre la fin du glissement et une page qui ne bouge plus.
    private func attendreStabilite(_ limite: TimeInterval = 8) -> TimeInterval? {
        let debut = Date()
        var precedent = empreinte()
        while Date().timeIntervalSince(debut) < limite {
            let e = empreinte()
            if e == precedent, e != -1 { return Date().timeIntervalSince(debut) }
            precedent = e
        }
        return nil
    }

    func testDefilerUneUnite() {
        app.open(URL(string: "ont://read/bereshit/bereshit-17")!)
        Thread.sleep(forTimeInterval: 10)

        let page = app.windows.firstMatch
        var mesures: [Double] = []
        for tour in 0..<6 {
            page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.03,
                       thenDragTo: page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)),
                       withVelocity: .default, thenHoldForDuration: 0.01)
            guard let ms = attendreStabilite().map({ $0 * 1000 }) else {
                print("ONT-DEFILE tour \(tour) : jamais stabilisé")
                continue
            }
            mesures.append(ms)
            print("ONT-DEFILE tour \(tour) : \(String(format: "%.0f", ms)) ms")
        }
        let tries = mesures.sorted()
        if !tries.isEmpty {
            print(String(format: "ONT-DEFILE-RESUME mediane %.0f ms (n=%d, min %.0f, max %.0f)",
                         tries[tries.count / 2], tries.count, tries.first!, tries.last!))
        }
    }
}
