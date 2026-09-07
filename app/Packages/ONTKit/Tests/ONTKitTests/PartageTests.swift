import Foundation
import Testing

@testable import ONTKit

/// La composition d'un passage partagé.
///
/// On ne partage pas un verset à sa mère et à un groupe d'étude de la même
/// manière. Ces tests tiennent les cinq bascules et ce qu'elles font.
struct PartageTests {
    private let morceaux = [
        Partage.Morceau(numero: 1, texte: "Quand Elohim commença à orchestrer."),
        Partage.Morceau(numero: 2, texte: "La Terre était informe et vide."),
    ]

    private func rendu(_ modifier: (inout ReglagesDePartage) -> Void = { _ in }) -> String {
        var reglages = ReglagesDePartage.default
        modifier(&reglages)
        return Partage.composer(morceaux, reference: "Bereshit 1:1-2", reglages: reglages)
    }

    @Test("les défauts donnent la forme attendue")
    func lesDefauts() {
        // Numéros allumés, à la suite, chevrons, sans le nom de l'app.
        #expect(
            rendu() == "«\u{00A0}1 Quand Elohim commença à orchestrer. "
                + "2 La Terre était informe et vide.\u{00A0}»\n\n— Bereshit 1:1-2")
    }

    @Test("sans les numéros, le corps est nu")
    func sansNumeros() {
        let sortie = rendu { $0.numerosDeVersets = false }
        #expect(!sortie.contains("1 Quand"))
        #expect(sortie.contains("Quand Elohim"))
    }

    /// Un par ligne sert à l'étude, où l'on veut voir la structure.
    @Test("un verset par ligne quand on le demande")
    func unParLigne() {
        let sortie = rendu { $0.versetsALaSuite = false }
        #expect(sortie.contains("orchestrer.\n2 La Terre"))
    }

    /// **L'espace avant le chevron fermant est insécable.** Sans elle, un
    /// retour à la ligne peut séparer le chevron du mot qu'il ferme.
    @Test("les chevrons portent leurs espaces insécables")
    func lesChevrons() {
        #expect(rendu().contains("«\u{00A0}"))
        #expect(rendu().contains("\u{00A0}»"))
        #expect(!rendu { $0.guillemets = false }.contains("«"))
    }

    /// Éteint par défaut : celui qui partage cite un texte, il ne fait pas de
    /// la réclame.
    @Test("le nom de l'app ne vient que si on le demande")
    func leNomDeLApp() {
        #expect(!rendu().contains(Partage.nom))
        #expect(rendu { $0.nomDeLApp = true }.hasSuffix("— Bereshit 1:1-2, \(Partage.nom)"))
    }

    /// **La signature reste sur sa propre ligne.** C'est ce qui permet à qui
    /// reçoit de citer le texte sans la traîner.
    @Test("la signature est détachée du corps")
    func laSignature() {
        #expect(rendu().contains("\n\n— "))
    }

    /// Une sélection vide ne laisse pas un corps fantôme au-dessus de la
    /// signature — deux retours à la ligne sur rien.
    @Test("sans verset, il ne reste que la signature")
    func laSelectionVide() {
        let sortie = Partage.composer(
            [], reference: "Bereshit 1", reglages: .default)
        #expect(sortie == "— Bereshit 1")
    }

    /// Un fichier écrit avant qu'une bascule existe se relit, et prend le
    /// défaut de celle qui manque.
    @Test("des réglages d'une version antérieure se relisent")
    func leDecodageTolerant() throws {
        let ancien = try JSONDecoder().decode(
            ReglagesDePartage.self, from: Data(#"{"guillemets":false}"#.utf8))

        #expect(!ancien.guillemets)
        #expect(ancien.numerosDeVersets)
        #expect(ancien.lien)
    }
}

/// Ce que « Copier » met dans le presse-papier.
///
/// Un presse-papier n'a **qu'un** contenu, là où une feuille de partage porte
/// deux objets — le texte d'un côté, l'URL de l'autre, pour que la messagerie
/// en tire un aperçu. Le copier n'emportait donc rien du lien, et rien ne le
/// disait : celui qui allume la bascule la croit vraie partout.
struct CopierAvecLienTests {
    private let texte = "«\u{00A0}1 Au commencement.\u{00A0}»\n\n— Bereshit 1:1"

    @Test("le lien suit, sur sa propre ligne")
    func leLienSuit() {
        let rendu = Partage.avecLien(
            texte, URL(string: "https://ontbible.com/fr/lire/bereshit/bereshit-1?v=1"))

        #expect(rendu.hasSuffix("\n\nhttps://ontbible.com/fr/lire/bereshit/bereshit-1?v=1"))
        #expect(rendu.contains("— Bereshit 1:1"))
    }

    /// Sans lien — bascule éteinte, ou domaine non configuré — le texte reste
    /// tel quel, sans ligne blanche en trop.
    @Test("sans lien, rien ne dépasse")
    func sansLien() {
        #expect(Partage.avecLien(texte, nil) == texte)
    }
}
