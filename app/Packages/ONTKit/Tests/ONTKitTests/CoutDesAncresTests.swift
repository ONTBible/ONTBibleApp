import Foundation
import Testing

@testable import ONTKit

/// Ce que coûte le calcul des ancres de position, à chaque évaluation du corps.
///
/// **Mesuré, pas supposé.** La session Android a trouvé chez elle un pointillé
/// de sélection qui réenregistrait les glyphes d'un texte haut de plusieurs
/// écrans à chaque image — 23 ms sur 16 de budget. La structure n'est pas la
/// même ici : un `overlay` SwiftUI est une couche à part, pas un ajout au nœud
/// de dessin du texte. Mais `parts` rappelle `plainText()` sur tout le bloc à
/// chaque lecture, et ma propre correction du repli des espaces lui a ajouté
/// une passe. Il fallait donc chiffrer.
struct CoutDesAncresTests {
    /// Un bloc de prose réaliste — trente versets d'une centaine de signes,
    /// avec des intraduisibles et de l'hébreu, comme le corpus en porte.
    private func bloc(_ combien: Int) -> [[Inline]] {
        (0..<combien).map { _ in
            [
                .text("Quand Elohim commença à orchestrer les "),
                .term("Cieux", lemma: "shamayim"),
                .text(" et la "),
                .hebrew("אֶרֶץ"),
                .text(" — la Terre était informe et vide, et l'obscurité "),
                .emphasis([.text("couvrait")]),
                .text(" la face de l'abîme."),
            ]
        }
    }

    @Test("le calcul des ancres reste loin du budget d'une image")
    func leCout() {
        let versets = bloc(30)
        // Ce que fait `parts` : un `plainText()` par verset, puis un prorata.
        func parts() -> [CGFloat] {
            let signes = versets.map { max(1, $0.plainText(gloss: true).count) }
            let total = CGFloat(signes.reduce(0, +))
            return signes.map { CGFloat($0) / total }
        }

        _ = parts()
        let debut = Date()
        let tours = 2_000
        for _ in 0..<tours { _ = parts() }
        let parTour = Date().timeIntervalSince(debut) / Double(tours) * 1000

        // 8,3 ms est le budget d'une image à 120 Hz. On se donne un vingtième.
        #expect(
            parTour < 0.4,
            "le calcul des ancres coûte \(String(format: "%.3f", parTour)) ms par évaluation"
        )
    }
}
