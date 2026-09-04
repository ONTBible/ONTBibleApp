import SwiftUI
import Testing
import UIKit

@testable import ONTDesignSystem
@testable import ONTKit

/// **Les rôles fonctionnels tiennent-ils leur contraste ?**
///
/// La gamme est générée avec ses contrastes vérifiés — mais le générateur
/// tourne hors du dépôt, et c'est le *choix du cran* par le rôle qui décide de
/// ce que le lecteur voit. Le cèdre 600 rend 4,4:1 sur parchemin : juste sous
/// la barre, et l'écart ne se voit pas à l'œil. C'est précisément le genre de
/// décision qu'une épreuve doit garder : celle-ci a refusé le 600 et imposé le
/// 700 avant même d'être committée.
@Suite("Les contrastes de la gamme")
struct GammeContrastTests {
    private func luminance(_ couleur: Color) -> Double {
        var r: CGFloat = 0
        var v: CGFloat = 0
        var b: CGFloat = 0
        UIColor(couleur).getRed(&r, green: &v, blue: &b, alpha: nil)
        func lin(_ c: CGFloat) -> Double {
            let c = Double(c)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(v) + 0.0722 * lin(b)
    }

    private func contraste(_ a: Color, _ b: Color) -> Double {
        let la = luminance(a)
        let lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    @Test(
        "chaque rôle tient 4,5:1 sur le fond de son mode",
        arguments: ReadingTheme.allCases)
    func lesRolesTiennent(_ mode: ReadingTheme) {
        let fond = ONTColors.background(mode)
        for (nom, role) in [
            ("danger", ONTColors.danger(mode)),
            ("succès", ONTColors.succes(mode)),
            ("avertissement", ONTColors.avertissement(mode)),
        ] {
            let c = contraste(role, fond)
            #expect(
                c >= 4.5,
                "\(nom) rend \(String(format: "%.1f", c)):1 sur le fond de \(mode) — illisible")
        }
    }

    /// Les ancres du relevé **sont** leurs crans — au centième près.
    ///
    /// La gamme est interpolée *autour* du logo et du site ; si une
    /// régénération les déplaçait, la marque dériverait sans que rien ne
    /// rougisse à l'œil.
    @Test("les ancres du relevé sont exactes")
    func lesAncresSontExactes() {
        let paires: [(String, Color, Color)] = [
            ("aubergine800 = bordeaux du logo", ONTGamme.aubergine800, ONTColors.burgundy),
            ("or300 = or du logo", ONTGamme.or300, ONTColors.gold),
        ]
        for (nom, a, b) in paires {
            var (r1, v1, b1): (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
            var (r2, v2, b2): (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
            UIColor(a).getRed(&r1, green: &v1, blue: &b1, alpha: nil)
            UIColor(b).getRed(&r2, green: &v2, blue: &b2, alpha: nil)
            let ecart = max(abs(r1 - r2), abs(v1 - v2), abs(b1 - b2))
            #expect(ecart < 0.005, "\(nom) — écart \(ecart)")
        }
    }
}
