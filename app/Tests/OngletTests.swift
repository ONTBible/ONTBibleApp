import Foundation
import ONTKit
import Testing

/// L'identifiant d'onglet — ce qui survit à la fermeture de l'app.
///
/// Depuis que la barre latérale de l'iPad porte des livres, un onglet n'est
/// plus un cas fixe parmi quatre : il peut désigner n'importe quel livre. Le
/// brut doit donc faire l'aller-retour sans perdre l'identifiant, y compris
/// pour ceux qui portent un tiret — et ils en portent presque tous.
@MainActor
struct OngletTests {
    @Test("les quatre onglets fixes gardent leur brut")
    func lesQuatreFixes() {
        for onglet in [Router.TabID.qahal, .bible, .lexicon, .you] {
            #expect(Router.TabID(rawValue: onglet.rawValue) == onglet)
            #expect(onglet.bookId == nil)
        }
    }

    @Test("un livre fait l'aller-retour, tirets compris")
    func unLivre() {
        let onglet = Router.TabID.book("toledot-adam-ve-chavah")
        #expect(onglet.rawValue == "book:toledot-adam-ve-chavah")
        #expect(Router.TabID(rawValue: onglet.rawValue) == onglet)
        #expect(onglet.bookId == "toledot-adam-ve-chavah")
    }

    @Test("un brut inconnu ne devient pas un livre fantôme")
    func brutInconnu() {
        #expect(Router.TabID(rawValue: "recherche") == nil)
        #expect(Router.TabID(rawValue: "") == nil)
    }

    @Test("un onglet enregistré est relu au lancement")
    func relectureAuLancement() {
        let clé = "tab"
        let avant = UserDefaults.standard.string(forKey: clé)
        defer { UserDefaults.standard.set(avant, forKey: clé) }

        UserDefaults.standard.set("book:bereshit", forKey: clé)
        #expect(Router().tab == .book("bereshit"))

        // Et un brut qu'on ne sait plus lire ramène à la lecture, jamais à un
        // écran vide : c'est ce qui arrive à qui revient d'une version où le
        // format n'était pas le même.
        UserDefaults.standard.set("n'importe quoi", forKey: clé)
        #expect(Router().tab == .bible)
    }
}
