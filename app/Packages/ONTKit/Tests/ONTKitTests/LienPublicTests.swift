import Foundation
import Testing

@testable import ONTKit

/// Le lien public — **un contrat entre trois dépôts**.
///
/// `ontbible.com/fr/lire/<livre>/<unité>?v=…` est produit par le site et lu par
/// les deux liseuses. Ce n'est plus une adresse de page : c'est une forme sur
/// laquelle trois dépôts se sont accordés, et que chacun peut casser seul.
///
/// Rien ne la gardait ici. Ces épreuves répondent à une question posée par la
/// session du site — *iOS lit-il une sélection disjointe ?* — et laissent la
/// réponse vérifiable au lieu de la laisser dite.
@Suite("Le lien public")
@MainActor
struct LienPublicTests {

    private func routeur() -> Router {
        Router.webBaseImpose = URL(string: "https://ontbible.com")
        return Router()
    }

    private func ouvrir(_ adresse: String) -> Router {
        let r = routeur()
        _ = r.open(URL(string: adresse)!)
        return r
    }

    // MARK: - Les trois formes que le site produit

    @Test("un verset seul")
    func versetSeul() {
        let r = ouvrir("https://ontbible.com/fr/lire/bereshit/bereshit-1?v=6")
        #expect(r.pendingSelection == [6])
        #expect(r.pendingVerse == 6)
    }

    @Test("une plage contiguë")
    func plageContigue() {
        let r = ouvrir("https://ontbible.com/fr/lire/bereshit/bereshit-1?v=1-3")
        #expect(r.pendingSelection == [1, 2, 3])
        #expect(r.pendingVerse == 1)
    }

    /// **Celle dont la session du site doutait.**
    ///
    /// Une app qui ne lirait que `début-fin` afficherait « 1 à 6 » là où on
    /// partageait « 1, 4, 5, 6 » — et ça ne ressemble pas à une panne, ça
    /// ressemble à une sélection un peu large. C'est le genre de défaut qui
    /// vit des mois.
    @Test("une sélection disjointe garde ses trous")
    func selectionDisjointe() {
        let r = ouvrir("https://ontbible.com/fr/lire/bereshit/bereshit-1?v=1,4-6")
        #expect(r.pendingSelection == [1, 4, 5, 6])
        #expect(!r.pendingSelection.contains(2))
        #expect(!r.pendingSelection.contains(3))
        #expect(r.pendingVerse == 1)
    }

    // MARK: - Ce qui doit rester vrai

    /// Le segment de langue n'est **pas** comparé, délibérément : un lien
    /// anglais doit ouvrir le même passage. Android l'ignore de son côté, et
    /// une divergence ici ferait cesser d'ouvrir l'app le jour d'une édition
    /// anglaise — sans que rien ne le signale.
    @Test("un lien d'une autre langue ouvre le même passage")
    func autreLangue() {
        let r = ouvrir("https://ontbible.com/en/lire/bereshit/bereshit-1?v=2")
        #expect(r.biblePath.count == 2)
        #expect(r.pendingSelection == [2])
    }

    @Test("sans versets, l'unité s'ouvre entière")
    func sansVersets() {
        let r = ouvrir("https://ontbible.com/fr/lire/bereshit/bereshit-1")
        #expect(r.pendingSelection.isEmpty)
        #expect(r.pendingVerse == nil)
    }

    /// Le lien d'un autre domaine ne nous concerne pas — on le laisse au
    /// système plutôt que de l'avaler.
    @Test("un lien d'ailleurs est refusé")
    func lienDAilleurs() {
        let r = routeur()
        #expect(!r.open(URL(string: "https://exemple.invalide/fr/lire/x/y")!))
    }

    // MARK: - Ce qu'un lien bricolé ne doit pas pouvoir faire

    /// *Un lien à moitié compris vaut mieux qu'un lien mort.* Un morceau
    /// illisible est ignoré, le reste passe.
    @Test("un morceau illisible n'emporte pas le reste")
    func morceauIllisible() {
        let r = ouvrir("https://ontbible.com/fr/lire/bereshit/bereshit-1?v=2,abc,5")
        #expect(r.pendingSelection == [2, 5])
    }

    /// Une plage absurde est bornée plutôt que de faire allouer des millions
    /// d'entiers. Elle est alors **ignorée**, pas tronquée : tronquer
    /// désignerait un passage que personne n'a partagé.
    @Test("une plage absurde est ignorée, pas tronquée")
    func plageAbsurde() {
        let r = ouvrir("https://ontbible.com/fr/lire/bereshit/bereshit-1?v=1-99999999")
        #expect(r.pendingSelection.isEmpty)
    }

    @Test("les bornes à l'envers se lisent à l'endroit")
    func bornesInversees() {
        let r = ouvrir("https://ontbible.com/fr/lire/bereshit/bereshit-1?v=3-1")
        #expect(r.pendingSelection == [1, 2, 3])
    }
}
