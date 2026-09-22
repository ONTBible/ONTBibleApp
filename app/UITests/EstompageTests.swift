import UIKit
import XCTest

/// Ce que la sélection doit faire au reste de la page.
///
/// Désigner un verset baisse tous les autres — c'est ce qui le désigne. Le
/// moteur qui l'accomplit demande à SwiftUI de rasteriser la section hors
/// écran, et une section trop haute pour un tampon perdait tout son dessin.
/// La parade — ne poser le moteur que sous un plafond — a d'abord été réglée
/// sur la limite du **simulateur**, 8192 px, moitié moins que celle d'un
/// téléphone. Sur l'appareil, presque aucune section ne passait, et
/// l'estompage ne se produisait plus jamais.
@MainActor
final class EstompageTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    /// La part d'encre **franche** parmi toute l'encre de la page.
    ///
    /// Une proportion, et non un compte : le compte dépend de l'endroit où la
    /// page s'est arrêtée, et comparer deux écrans qui ne montrent pas les
    /// mêmes lignes ne dit rien. La proportion, elle, dit une seule chose —
    /// « ce texte est-il à pleine encre, ou baissé » — et elle la dit où que
    /// l'on soit dans le chapitre.
    ///
    /// C'est la leçon d'une première version qui comparait des comptes bruts :
    /// elle a rapporté un défaut là où il n'y en avait pas, parce que la
    /// sélection fait remonter la page.
    private func partDEncreFranche() -> Double {
        guard let image = XCUIScreen.main.screenshot().image.cgImage else { return -1 }
        let l = image.width, h = image.height
        var octets = [UInt8](repeating: 0, count: l * h)
        guard let ctx = CGContext(data: &octets, width: l, height: h, bitsPerComponent: 8,
                                  bytesPerRow: l, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: 0) else { return -1 }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: l, height: h))

        var e: [Int] = []
        for y in stride(from: Int(Double(h) * 0.20), to: Int(Double(h) * 0.50), by: 2) {
            for x in stride(from: Int(Double(l) * 0.06), to: Int(Double(l) * 0.94), by: 2) {
                e.append(Int(octets[y * l + x]))
            }
        }
        // L'écart au fond compte en valeur absolue : sur un thème sombre,
        // l'encre est plus **claire** que la page, et une mesure signée y
        // verrait une page blanche.
        let fond = e.sorted()[e.count / 2]
        let encre = e.filter { abs($0 - fond) > 25 }
        guard encre.count > 500 else { return -1 }
        let franche = encre.filter { abs($0 - fond) > 90 }
        return Double(franche.count) / Double(encre.count)
    }

    /// **La part de la page qui porte de l'encre**, franche ou baissée.
    ///
    /// L'autre mesure dit « ce texte est-il plein ou baissé ». Celle-ci dit
    /// « y a-t-il du texte ». Sans elle, perdre le dessin du moteur — ce qui
    /// blanchit la page — se lit comme un estompage parfait.
    private func quantiteDEncre() -> Double {
        guard let image = XCUIScreen.main.screenshot().image.cgImage else { return -1 }
        let l = image.width, h = image.height
        var octets = [UInt8](repeating: 0, count: l * h)
        guard let ctx = CGContext(data: &octets, width: l, height: h, bitsPerComponent: 8,
                                  bytesPerRow: l, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: 0) else { return -1 }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: l, height: h))
        var e: [Int] = []
        for y in stride(from: Int(Double(h) * 0.20), to: Int(Double(h) * 0.50), by: 2) {
            for x in stride(from: Int(Double(l) * 0.06), to: Int(Double(l) * 0.94), by: 2) {
                e.append(Int(octets[y * l + x]))
            }
        }
        let fond = e.sorted()[e.count / 2]
        return Double(e.filter { abs($0 - fond) > 25 }.count) / Double(e.count)
    }

    /// **Attendre que la page porte de l'encre, au lieu de compter jusqu'à
    /// quatre.**
    ///
    /// L'épreuve dormait quatre secondes puis mesurait. Après une installation
    /// neuve, l'app analyse le corpus à son premier lancement et la page n'est
    /// pas encore peinte : la mesure rendait alors **0,004** au lieu de 0,9, et
    /// l'épreuve rougissait pour une raison qui n'a rien à voir avec ce qu'elle
    /// garde.
    ///
    /// Elle m'a trompée dans les deux sens le 20 septembre : rouge sur un
    /// correctif juste, verte sur une page blanche. Un délai fixe mesure la
    /// patience de qui l'a écrit, pas l'état de la page.
    /// **Stable, et pas seulement non vide.**
    ///
    /// Un premier jet rendait la main dès qu'un peu d'encre paraissait. La page
    /// n'était alors qu'à moitié peinte — 0,21 au lieu de 0,90 — et l'épreuve
    /// comparait deux états de peinture au lieu de deux états de sélection.
    /// « Il y a de l'encre » n'est pas « la page est prête ».
    @discardableResult
    private func attendreQueLaPagePorteDeLEncre(_ limite: TimeInterval = 30) -> Bool {
        let fin = Date().addingTimeInterval(limite)
        var precedent = -1.0
        while Date() < fin {
            let mesure = quantiteDEncre()
            // Deux relevés identiques à un centième près, et de l'encre : la
            // page ne bouge plus.
            if mesure > 0.05, abs(mesure - precedent) < 0.01 { return true }
            precedent = mesure
            Thread.sleep(forTimeInterval: 0.6)
        }
        return false
    }

    /// Sans sélection, la page est à pleine encre.
    /// Avec, l'essentiel doit être baissé.
    ///
    /// ## Deux indéterminations retirées le 21 septembre
    ///
    /// Cette épreuve a rougi sur une pull request qui ne contenait **que deux
    /// fichiers Markdown**, puis a réussi au rejeu sans qu'une ligne change.
    /// Elle était juste sur son intention et instable sur sa mesure — et une
    /// garde qui rougit au hasard est une garde qu'on apprend à ignorer, donc
    /// pire qu'absente : le jour où elle a raison, personne ne la lit.
    ///
    /// **Premièrement, elle faisait glisser la page** pour s'éloigner du verset
    /// désigné, qui reste plein par définition. Ce qui se trouve ensuite dans
    /// la bande mesurée dépend de l'inertie du geste : tantôt les voisins
    /// baissés, tantôt le verset désigné lui-même. Le glissement est retiré.
    ///
    /// **Deuxièmement, les deux mesures ne regardaient pas la même page.**
    /// L'ancre `?v=3` désigne *et* fait défiler ; l'état « pleine » était donc
    /// relevé avant ce défilement, l'état « désignée » après. Comparer deux
    /// portions différentes ne dit rien sur l'estompage.
    ///
    /// L'ordre est donc inversé : on désigne d'abord, on mesure, **on annule
    /// la sélection sans toucher au défilement**, et on remesure. Même page,
    /// mêmes lignes, seule la désignation change — ce qui est exactement ce
    /// que l'épreuve prétend mesurer.
    func testDesignerUnVersetBaisseLeReste() {
        // Bereshit 19 : ses sections dépassent le plafond du simulateur, et
        // c'est exactement là que la parade se voyait.
        app.open(URL(string: "ont://read/bereshit/bereshit-19?v=3")!)
        XCTAssertTrue(
            attendreQueLaPagePorteDeLEncre(),
            "la page n'a jamais porté d'encre — rien à mesurer"
        )
        XCTAssertTrue(app.buttons["Partager"].waitForExistence(timeout: 8),
                      "aucun verset n'a été désigné")
        // La barre d'actions arrive avec une animation ; la mesurer pendant
        // qu'elle monte relèverait un état transitoire.
        Thread.sleep(forTimeInterval: 1.5)

        let designee = partDEncreFranche()

        // **Une page vide passerait tous les seuils qui suivent.**
        //
        // Le 20 septembre, un correctif a fait perdre son dessin au moteur : la
        // page est devenue blanche, et cette épreuve a rendu 0,019 contre
        // 0,778 — donc « vert », puisqu'elle ne demandait qu'une baisse. On
        // compte donc l'encre elle-même, et pas seulement sa part franche.
        XCTAssertGreaterThan(designee, -0.5, "la page s'est vidée en désignant un verset")
        XCTAssertGreaterThan(
            quantiteDEncre(), 0.02,
            "la page ne porte presque plus d'encre : le texte a disparu, et une "
            + "page blanche satisferait tous les seuils de cette épreuve"
        )

        // Annuler la sélection **sans défiler** : la croix de la barre vide la
        // désignation et laisse la page exactement où elle est.
        let croix = app.buttons["xmark"]
        XCTAssertTrue(croix.waitForExistence(timeout: 5),
                      "la croix qui annule la sélection est introuvable — "
                      + "sans elle, les deux mesures ne portent pas sur la même page")
        croix.tap()
        XCTAssertTrue(
            app.buttons["Partager"].waitForNonExistence(timeout: 5),
            "la sélection n'a pas été annulée : la seconde mesure porterait "
            + "encore un verset désigné"
        )
        Thread.sleep(forTimeInterval: 1.5)

        let pleine = partDEncreFranche()
        print("ONT-ESTOMPE part franche : designee \(designee), pleine \(pleine)")
        XCTAssertGreaterThan(pleine, 0, "page sans sélection illisible")

        // ## Le seuil, et ce qu'il a fallu pour le poser
        //
        // Il valait `0,6` — calibré sur l'ancienne mesure, celle qui faisait
        // glisser la page pour s'éloigner du verset désigné. Sans ce
        // glissement, ==la bande mesurée est occupée par le verset désigné
        // lui-même==, qui reste plein par définition : sur Bereshit 19 un seul
        // verset et sa glose font plus d'un écran. La baisse relevée porte
        // donc sur ce que ce verset **ne** couvre pas, et elle est plus ténue.
        //
        // Le seuil a été posé en mesurant les deux états, pas en le devinant —
        // et l'état « cassé » est le code d'avant le correctif du 21 septembre,
        // `designation: nil` et `.opacity(1)` :
        //
        //     voile en place   0,6995 / 0,8036  =  0,870
        //     voile retiré     0,8036 / 0,8036  =  1,000
        //
        // ==Les trois passages ont rendu des valeurs identiques au chiffre
        // près== dans les deux cas : la mesure ne dépend plus d'aucun geste.
        // 0,93 laisse 6 points de marge sous le cas sain et 7 au-dessus du cas
        // cassé — assez pour que l'épreuve ne rougisse pas au hasard, assez peu
        // pour qu'elle rougisse si le voile disparaît.
        XCTAssertLessThan(
            designee, pleine * 0.93,
            "le reste de la page n'est pas baissé — part d'encre franche "
            + "\(pleine) sans sélection, \(designee) avec"
        )
    }
}
