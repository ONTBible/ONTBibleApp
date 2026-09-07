import Foundation
import SwiftUI
import Testing

@testable import ONTDesignSystem

/// **Ce que ces épreuves couvrent, et ce qu'elles ne couvrent pas.**
///
/// Sur le Mac, une modale n'est plus une `.sheet` : le voile, la croix et ⎋
/// appellent tous les trois le même geste, celui que la présentation a déposé
/// avec son contenu. Si ce geste n'est pas gardé, ou s'il ne retire pas la
/// carte, la modale devient **impossible à fermer** — et rien à la lecture ne
/// le dit, puisque les trois chemins ont l'air corrects chacun de leur côté.
///
/// Ce qui n'est pas couvert, et qui doit être dit : **le clic dans le voile
/// lui-même**. Les événements synthétiques ne sont pas délivrés sur cette
/// machine — l'accessibilité est refusée, comme à `osascript` —, donc le
/// `onTapGesture` n'a pas été exercé. Ce qui est éprouvé ici est ce qu'il
/// appelle.
@MainActor
@Suite("Les modales du Mac")
struct FeuillesDuMacTests {
    @Test("le geste déposé est bien celui qu'on rend")
    func leGesteEstGarde() {
        let pile = ONTFeuilles()
        var ferme = false

        _ = pile.poser(titre: "Lecture", contenu: { AnyViewDeTest() }, fermer: { ferme = true })

        #expect(pile.posees.count == 1)
        pile.aDessiner?.fermer()
        #expect(ferme, "le geste de fermeture n'a pas été gardé — la carte serait infermable")
    }

    @Test("retirer enlève la bonne, et elle seule")
    func retirerNEnleveQueLaSienne() {
        let pile = ONTFeuilles()
        let premiere = pile.poser(titre: "a", contenu: { AnyViewDeTest() }, fermer: {})
        let seconde = pile.poser(titre: "b", contenu: { AnyViewDeTest() }, fermer: {})

        pile.retirer(premiere)
        #expect(pile.posees.map(\.id) == [seconde])
        pile.retirer(seconde)
        #expect(pile.posees.isEmpty)
    }

    /// La racine ne dessine que `aDessiner`. Si ce choix s'inversait, ouvrir une
    /// fiche par-dessus des réglages montrerait les réglages — et l'app aurait
    /// l'air de ne pas répondre.
    @Test("la dernière posée est celle qui se montre")
    func laDernierePassePremiere() {
        let pile = ONTFeuilles()
        _ = pile.poser(titre: "réglages", contenu: { AnyViewDeTest() }, fermer: {})
        _ = pile.poser(titre: "fiche", contenu: { AnyViewDeTest() }, fermer: {})

        #expect(pile.aDessiner?.titre == "fiche")
    }
}

private func AnyViewDeTest() -> AnyView { AnyView(EmptyView()) }
