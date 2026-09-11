import UIKit
import XCTest

/// **Suivre un renvoi, puis revenir exactement d'où l'on vient.**
///
/// L'auteur l'a demandé ainsi, le 11 septembre 2026 : « quand j'arrive depuis
/// un ref de verset je veux que le btn de back me ramène à l'endroit où j'étais
/// juste avant, donc le bon chapitre et le bon niveau de scroll ».
///
/// ## Pourquoi ça ne pouvait pas marcher, et pourquoi ça se mesure ici
///
/// Le routeur **remplaçait** la pile de navigation pour tout lien — `read`,
/// le widget, la carte du jour. C'est exact quand on *entre* dans le corpus :
/// le lecteur n'en venait pas, et le retour doit le mener à la table des
/// matières. Un renvoi est l'inverse, une *sortie* depuis une lecture en
/// cours : remplacer la pile lui faisait perdre son chapitre **et** sa hauteur
/// de défilement.
///
/// L'empilement rend les deux d'un coup — `NavigationStack` garde la vue
/// parente vivante, donc sa position de défilement avec elle. **Ce test existe
/// parce que cette phrase est une affirmation sur le système, pas une
/// certitude.** Elle se vérifie par un doigt, ou pas du tout.
///
/// ## Ce qu'il compare
///
/// Pas des `staticTexts` : le corps du texte ONT n'est pas exposé à
/// l'accessibilité — un bloc de prose est un seul `Text` que rien ne nomme.
/// On prend donc une **signature de l'encre** : un échantillon de gris sur la
/// zone de lecture. Deux écrans à la même hauteur de défilement donnent la
/// même signature ; deux hauteurs différentes divergent tout de suite.
@MainActor
final class RetourDepuisUnRenvoiTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    // MARK: - Mesure

    /// Un échantillon de gris de la zone de lecture.
    ///
    /// Les bornes évitent la barre de navigation en haut et la barre d'onglets
    /// en bas : toutes deux sont identiques d'un écran à l'autre et diluraient
    /// l'écart qu'on cherche.
    private func signature() -> [UInt8] {
        guard let image = XCUIScreen.main.screenshot().image.cgImage else { return [] }
        let largeur = image.width, hauteur = image.height
        var octets = [UInt8](repeating: 0, count: largeur * hauteur)
        guard let contexte = CGContext(
            data: &octets, width: largeur, height: hauteur,
            bitsPerComponent: 8, bytesPerRow: largeur,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0
        ) else { return [] }
        contexte.draw(image, in: CGRect(x: 0, y: 0, width: largeur, height: hauteur))

        let haut = Int(Double(hauteur) * 0.20), bas = Int(Double(hauteur) * 0.85)
        let gauche = Int(Double(largeur) * 0.05), droite = Int(Double(largeur) * 0.95)
        var echantillon: [UInt8] = []
        for y in stride(from: haut, to: bas, by: 7) {
            for x in stride(from: gauche, to: droite, by: 7) {
                echantillon.append(octets[y * largeur + x])
            }
        }
        return echantillon
    }

    /// La part de l'échantillon qui coïncide, entre 0 et 1.
    ///
    /// Une tolérance de 12 niveaux de gris et non l'égalité stricte : le rendu
    /// du texte n'est pas déterministe au pixel près d'un passage à l'autre —
    /// l'antialiasing bouge, et une comparaison exacte rougirait sur un écran
    /// visuellement identique.
    private func coincidence(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard !a.isEmpty, a.count == b.count else { return 0 }
        let proches = zip(a, b).filter { abs(Int($0) - Int($1)) <= 12 }.count
        return Double(proches) / Double(a.count)
    }

    private func glisser(_ fois: Int) {
        let fenetre = app.windows.firstMatch
        for _ in 0..<fois {
            fenetre.swipeUp(velocity: .slow)
            Thread.sleep(forTimeInterval: 0.4)
        }
        Thread.sleep(forTimeInterval: 1)
    }

    /// Le titre de l'unité ouverte — et **pas** celui d'une vue restée sous
    /// la pile.
    ///
    /// Le premier jet cherchait le premier libellé contenant « Chapitre ». Il
    /// a rougi sur « Chapitres », l'en-tête de section de l'index du livre :
    /// `NavigationStack` garde la vue parente vivante, donc interrogeable,
    /// même quand elle n'est pas à l'écran — c'est exactement ce qui fait
    /// marcher la restauration du défilement, et ça piège toute mesure qui
    /// lit l'arbre au lieu de l'écran.
    ///
    /// Le point médian discrimine : le titre d'une unité s'écrit
    /// « Bereshit · Chapitre 7 », l'en-tête de l'index s'écrit « Chapitres ».
    /// Et `isHittable` écarte ce qui est sous une autre vue.
    private func titre() -> String {
        app.staticTexts.allElementsBoundByIndex
            .filter { $0.isHittable }
            .map(\.label)
            .first { $0.contains("·") && $0.contains("Chapitre") } ?? ""
    }

    // MARK: - Le geste

    /// **Un renvoi se touche ; il ne s'ouvre pas par URL.**
    ///
    /// Le premier jet passait les deux navigations par `app.open(URL)`. Il a
    /// rougi, et pas pour la raison qu'il annonçait : `app.open` **remet
    /// l'app à zéro** — mesuré, le poids d'une capture passe de 750 ko à
    /// 1,99 Mo en rouvrant la *même* unité, parce que le défilement est
    /// perdu. `biblePath` n'est pas persisté, seul l'onglet l'est ; l'app
    /// redémarrait donc avec une pile vide, et le renvoi retombait dans sa
    /// branche « pile vide ».
    ///
    /// Le test mesurait un chemin que personne n'emprunte : **toucher un lien
    /// dans le texte ne relance jamais l'app**. Il touche donc le lien.
    ///
    /// Le renvoi se reconnaît à son chiffre : les intraduisibles et les Shemot
    /// s'appellent « toledot », « Noach », « Yafet » ; une référence s'écrit
    /// « Bereshit 1 » ou « Genèse 9:27 ».
    private func premierRenvoi() -> XCUIElement? {
        app.links.allElementsBoundByIndex.first {
            $0.isHittable && $0.label.contains(where: \.isNumber)
        }
    }

    func testLeRetourRendLeChapitreEtLaHauteur() throws {
        // L'entrée passe par une URL : c'est un *lancement*, pas un détour, et
        // la remise à zéro qu'elle provoque n'est donc pas gênante ici.
        app.open(URL(string: "ont://read/bereshit/bereshit-10")!)
        Thread.sleep(forTimeInterval: 5)

        // On descend jusqu'à ce qu'un renvoi soit sous le doigt. Sans
        // défilement, le test passerait même si la hauteur n'était pas rendue :
        // deux écrans en tête de chapitre coïncident.
        var renvoi = premierRenvoi()
        for _ in 0..<8 where renvoi == nil {
            app.windows.firstMatch.swipeUp(velocity: .slow)
            Thread.sleep(forTimeInterval: 0.6)
            renvoi = premierRenvoi()
        }
        // Un glissement de plus, pour être sûr d'être loin du haut.
        app.windows.firstMatch.swipeUp(velocity: .slow)
        Thread.sleep(forTimeInterval: 0.8)
        renvoi = premierRenvoi()

        let cible = try XCTUnwrap(renvoi, "aucun renvoi touchable dans bereshit-10")
        let libelle = cible.label

        let titreAvant = titre()
        XCTAssertTrue(titreAvant.contains("10"), "on n'est pas dans Bereshit 10 — « \(titreAvant) »")
        let avant = signature()
        XCTAssertFalse(avant.isEmpty, "impossible de lire l'écran")

        cible.tap()
        Thread.sleep(forTimeInterval: 4)

        let titrePendant = titre()
        XCTAssertFalse(
            titrePendant.isEmpty,
            "toucher « \(libelle) » n'a mené nulle part — le renvoi ne pose pas de lien"
        )
        XCTAssertNotEqual(
            titrePendant, titreAvant,
            "toucher « \(libelle) » n'a pas changé d'unité"
        )

        // **Le bouton de retour du système**, et non un geste : le glissement
        // de retour est coupé dans la lecture, la page tourne à sa place.
        let retour = app.navigationBars.buttons["BackButton"]
        XCTAssertTrue(retour.waitForExistence(timeout: 5), "pas de bouton de retour")
        // **On ne juge pas sur le libellé du bouton.** Il a annoncé
        // « Précédent » : iOS remplace le titre de la vue parente par ce mot
        // générique dès qu'il ne tient pas dans la barre, et « Bereshit ·
        // Chapitre 10 » n'y tient pas. Le libellé ne dit donc rien de la pile
        // — c'est la troisième fois dans cette épreuve qu'une mesure bien
        // formée répond à une autre question. Le verdict est plus bas : ce
        // qu'on voit après avoir touché.
        retour.tap()
        Thread.sleep(forTimeInterval: 3)

        let titreApres = titre()
        XCTAssertEqual(
            titreApres, titreAvant,
            "le retour n'a pas rendu l'unité d'où l'on vient"
        )

        let apres = signature()
        let part = coincidence(avant, apres)
        XCTAssertGreaterThan(
            part, 0.92,
            "l'unité est rendue mais pas la hauteur de défilement — "
                + "coïncidence \(String(format: "%.2f", part))"
        )
    }
}
