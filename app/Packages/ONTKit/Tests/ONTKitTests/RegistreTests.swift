import Testing

@testable import ONTKit

/// Le choix entre le pont français et la glose.
///
/// La règle tenait en trois lignes et était recopiée dans les vues — c'est
/// précisément pour ça qu'un écran a fini par ne pas l'appliquer. Elle est
/// maintenant à un seul endroit, et éprouvée ici.
struct RegistreTests {
    @Test("le français reçu allumé rend le pont")
    func lePontQuandOnLeDemande() {
        #expect(
            Registre.second(
                french: "Actes des Apôtres", glose: "les gevurot de YHWH par ses neviim",
                francaisRecu: true) == "Actes des Apôtres")
    }

    @Test("le français reçu éteint rend la glose")
    func laGloseQuandOnLEteint() {
        #expect(
            Registre.second(
                french: "Actes des Apôtres", glose: "les gevurot de YHWH par ses neviim",
                francaisRecu: false) == "les gevurot de YHWH par ses neviim")
    }

    /// *Ketouvim* est « Écrits » des deux côtés : le corpus ne lui donne pas
    /// de glose, et la ligne doit retomber sur le pont plutôt que disparaître.
    @Test("sans glose, la ligne retombe sur le français")
    func sansGloseOnGardeLePont() {
        #expect(
            Registre.second(french: "Écrits", glose: nil, francaisRecu: false) == "Écrits")
    }

    @Test("sans rien à dire, la ligne disparaît")
    func rienNAfficheRien() {
        #expect(Registre.second(french: nil, glose: nil, francaisRecu: false) == nil)
        #expect(Registre.second(french: "", glose: nil, francaisRecu: true) == nil)
    }
}
