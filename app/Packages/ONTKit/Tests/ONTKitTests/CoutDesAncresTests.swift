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

        // **Un étalon mesuré dans la même exécution.**
        //
        // Le seuil était d'abord absolu — 0,4 ms, relevé sur ma machine. Il est
        // tombé sur le runner de l'intégration continue, à 0,46 ms, et il avait
        // raison de tomber : un seuil en millisecondes est une conclusion sur
        // **une machine**, pas une mesure de ce qu'on croit mesurer. Un runner
        // chargé l'aurait fait rougir un jour ou l'autre, sans qu'aucun code
        // n'ait bougé.
        //
        // L'étalon est le même travail sur un seul verset. Le rapport entre les
        // deux ne dépend plus de la machine : il dit combien de fois le bloc
        // coûte son verset, et c'est **ça** qu'une régression ferait exploser.
        let unSeul = [versets[0]]
        func etalon() -> Int { unSeul.map { $0.plainText(gloss: true).count }.reduce(0, +) }

        _ = parts()
        _ = etalon()
        let tours = 2_000

        let debutEtalon = Date()
        for _ in 0..<tours { _ = etalon() }
        let coutEtalon = Date().timeIntervalSince(debutEtalon)

        let debut = Date()
        for _ in 0..<tours { _ = parts() }
        let cout = Date().timeIntervalSince(debut)

        let rapport = cout / max(coutEtalon, .leastNonzeroMagnitude)
        let parTour = cout / Double(tours) * 1000

        // Trente versets pour un : le rapport doit rester du même ordre que le
        // nombre de versets. On tolère le double — la marge couvre le prorata
        // et le bruit de mesure, pas une régression d'algorithme.
        #expect(
            rapport < Double(versets.count) * 2,
            "le bloc coûte \(String(format: "%.1f", rapport)) fois son verset, soit \(String(format: "%.3f", parTour)) ms par évaluation sur cette machine"
        )
    }
}
