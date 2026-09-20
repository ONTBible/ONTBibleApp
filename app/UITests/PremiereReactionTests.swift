import UIKit
import XCTest

/// **Le délai avant que quelque chose bouge**, et non celui avant que tout se pose.
///
/// Le premier banc mesurait la stabilité : le temps entre l'appui et un écran
/// qui ne change plus. Il a chiffré une désignation à 513 ms là où l'auteur
/// continuait de dire « c'est lent ».
///
/// Ce n'est pas la même chose qu'il vit. Une page qui répond en 80 ms puis
/// s'anime pendant 400 paraît vive ; une page qui ne bouge pas pendant 400 ms
/// puis se pose d'un coup paraît morte. **La stabilité mesure la fin du
/// mouvement, la première réaction mesure le début.** C'est le début qu'un
/// doigt attend.
@MainActor
final class PremiereReactionTests: XCTestCase {
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
        for y in stride(from: Int(Double(h) * 0.2), to: Int(Double(h) * 0.9), by: 5) {
            for x in stride(from: Int(Double(l) * 0.08), to: Int(Double(l) * 0.92), by: 5) {
                somme = somme &* 31 &+ Int(octets[y * l + x])
            }
        }
        return somme
    }

    func testDelaiAvantQueQuelqueChoseBouge() {
        app.open(URL(string: "ont://read/bereshit/bereshit-17")!)
        Thread.sleep(forTimeInterval: 10)

        let page = app.windows.firstMatch
        var mesures: [Double] = []
        for tour in 0..<6 {
            let avant = empreinte()
            let debut = Date()
            page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
                .press(forDuration: 0.03, thenDragTo:
                        page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)),
                       withVelocity: .default, thenHoldForDuration: 0.01)
            var ms: Double?
            while Date().timeIntervalSince(debut) < 6 {
                if empreinte() != avant { ms = Date().timeIntervalSince(debut) * 1000; break }
            }
            guard let ms else { print("ONT-REACTION tour \(tour) : rien n'a bougé"); continue }
            // Les tours pairs désignent, les impairs relâchent.
            if tour % 2 == 0 { mesures.append(ms) }
            print("ONT-REACTION tour \(tour) \(tour % 2 == 0 ? "designer" : "relacher") : \(String(format: "%.0f", ms)) ms")
            Thread.sleep(forTimeInterval: 2)
        }
        let t = mesures.sorted()
        if !t.isEmpty {
            print(String(format: "ONT-REACTION-RESUME designer, premiere reaction : mediane %.0f ms (n=%d, min %.0f, max %.0f)",
                         t[t.count / 2], t.count, t.first!, t.last!))
        }
    }
}
