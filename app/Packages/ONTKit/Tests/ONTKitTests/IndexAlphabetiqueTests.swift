import Testing

@testable import ONTKit

/// Le classement du rail de lettres.
struct IndexAlphabetiqueTests {
    @Test("les accents se replient sur leur lettre nue")
    func lesAccents() {
        // Deux entrées voisines à l'œil sous deux lettres différentes
        // rendraient le rail inutilisable.
        #expect(IndexAlphabetique.lettre(de: "Élohim") == "E")
        #expect(IndexAlphabetique.lettre(de: "elohim") == "E")
    }

    /// `'Elohim` se range sous `E`. Une lettre `'` dans le rail ne dit rien à
    /// personne.
    @Test("une apostrophe de tête ne fait pas une lettre")
    func lApostrophe() {
        #expect(IndexAlphabetique.lettre(de: "'Elohim") == "E")
        #expect(IndexAlphabetique.lettre(de: "She'ol") == "S")
    }

    @Test("ce qui n'a aucune lettre va sous le dièse")
    func leReste() {
        #expect(IndexAlphabetique.lettre(de: "70") == "#")
        #expect(IndexAlphabetique.lettre(de: "—") == "#")
        #expect(IndexAlphabetique.lettre(de: "") == "#")
    }

    /// **Le découpage n'ordonne pas.** Le classement appartient à qui fournit
    /// la liste ; le refaire ici ferait deux vérités sur un même écran.
    @Test("les tranches suivent l'ordre reçu, sans le corriger")
    func lOrdreRecu() {
        let recu = ["adam", "adamah", "berith", "avon"]
        let tranches = IndexAlphabetique.trancher(recu) { $0 }

        #expect(tranches.map(\.lettre) == ["A", "B", "A"])
        #expect(tranches.first?.entrees == ["adam", "adamah"])
    }

    @Test("une liste vide ne fait aucune tranche")
    func laListeVide() {
        #expect(IndexAlphabetique.trancher([String]()) { $0 }.isEmpty)
    }
}
