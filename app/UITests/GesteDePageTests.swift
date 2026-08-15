import UIKit
import XCTest

/// Ce que seul un doigt peut dire.
///
/// Deux défauts ne se voyaient qu'à l'usage — un chapitre qui arrive vide après
/// un feuilletage, et la lecture qu'on quitte sans l'avoir demandé — et aucun
/// ne se reproduit en ouvrant les chapitres par lien profond : ce chemin
/// remplace la pile de navigation au lieu de faire tourner la page.
///
/// D'où ces tests. Ils ne vérifient pas une règle de calcul : ils **font le
/// geste**, ce qu'aucune autre mesure de ce dépôt ne sait faire.
///
/// ## Pourquoi ils comptent des pixels
///
/// Le premier jet comptait des `staticTexts`, et n'en trouvait aucun : le corps
/// du texte n'est pas exposé à l'accessibilité — un bloc de prose est un seul
/// `Text` que rien ne nomme. La page était pleine et la mesure aveugle.
///
/// On mesure donc l'encre à l'écran. C'est plus grossier, et c'est surtout le
/// bon critère : la question posée est « voit-on le texte », pas « l'arbre
/// d'accessibilité le mentionne-t-il ».
@MainActor
final class GesteDePageTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    // MARK: - Les gestes

    private func ouvrir(_ chapitre: String) {
        app.open(URL(string: "ont://read/bereshit/\(chapitre)")!)
        Thread.sleep(forTimeInterval: 3)
    }

    /// Un glissement horizontal net, au milieu de la page.
    ///
    /// En plusieurs points plutôt qu'en un seul trait : un glissement d'un bloc
    /// ne produit qu'un `onChanged`, et le geste de la liseuse se règle sur la
    /// course du doigt. C'est aussi ce que fait une main.
    private func feuilleter(
        versLaSuivante: Bool,
        depuisLeBord: Bool = false,
        hauteur: CGFloat = 0.55,
        repos: TimeInterval = 1.5
    ) {
        let page = app.windows.firstMatch
        // Le bord **exact**, et c'est tout l'enjeu du retour système : il ne
        // s'arme que dans les tout premiers points de l'écran. Un départ à
        // douze pour cent de la largeur ne le réveille jamais — le premier jet
        // de ces tests passait pour cette seule raison.
        let x0 = versLaSuivante ? 0.88 : (depuisLeBord ? 0.01 : 0.12)
        let x1 = versLaSuivante ? 0.08 : 0.92
        let depart = page.coordinate(withNormalizedOffset: CGVector(dx: x0, dy: hauteur))
        let arrivee = page.coordinate(withNormalizedOffset: CGVector(dx: x1, dy: hauteur))
        depart.press(forDuration: 0.08, thenDragTo: arrivee, withVelocity: .default,
                     thenHoldForDuration: 0.05)
        Thread.sleep(forTimeInterval: repos)
    }

    // MARK: - La mesure

    /// Le nombre de pixels d'encre dans la zone de lecture.
    ///
    /// La bande retenue exclut la barre du haut et celle des onglets : elles
    /// portent de l'encre même quand la page est vide, et c'est ce cas-là qu'on
    /// cherche.
    private func encreDeLecture() -> Int {
        guard let image = XCUIScreen.main.screenshot().image.cgImage else { return -1 }
        let largeur = image.width, hauteur = image.height
        var octets = [UInt8](repeating: 0, count: largeur * hauteur)
        guard let contexte = CGContext(
            data: &octets, width: largeur, height: hauteur,
            bitsPerComponent: 8, bytesPerRow: largeur,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0
        ) else { return -1 }
        contexte.draw(image, in: CGRect(x: 0, y: 0, width: largeur, height: hauteur))

        let haut = Int(Double(hauteur) * 0.38), bas = Int(Double(hauteur) * 0.88)
        let gauche = Int(Double(largeur) * 0.05), droite = Int(Double(largeur) * 0.95)
        var echantillon: [UInt8] = []
        for y in stride(from: haut, to: bas, by: 5) {
            for x in stride(from: gauche, to: droite, by: 5) {
                echantillon.append(octets[y * largeur + x])
            }
        }
        guard !echantillon.isEmpty else { return -1 }
        let fond = echantillon.sorted()[echantillon.count / 2]
        return echantillon.filter { Int($0) < Int(fond) - 40 }.count
    }

    private func exigerDuTexte(_ quand: String) {
        let encre = encreDeLecture()
        XCTAssertGreaterThan(encre, 40, "page sans texte — \(quand) (encre = \(encre))")
    }

    // MARK: - Les tests

    /// La page qui arrive après un tour de feuillet porte son texte.
    func testLaPageArriveePorteSonTexte() {
        ouvrir("bereshit-9")
        exigerDuTexte("au départ, avant tout geste")

        for tour in 1...5 {
            feuilleter(versLaSuivante: true)
            exigerDuTexte("après \(tour) tour(s) vers la suivante")
        }
    }

    /// Le retour à la précédente, pris **au bord exact de l'écran**.
    ///
    /// C'est là que vit le geste de retour du système, et nulle part ailleurs.
    /// On le coupe à l'entrée de la liseuse ; ce test vérifie que la coupure
    /// tient, tour après tour.
    func testLeRetourAuBordNeQuittePasLaLecture() {
        ouvrir("bereshit-9")
        exigerDuTexte("au départ, avant tout geste")

        for tour in 1...4 {
            feuilleter(versLaSuivante: false, depuisLeBord: true)
            exigerDuTexte("après \(tour) retour(s) pris au bord de l'écran")
        }
    }

    /// Deux gestes coup sur coup, sans laisser la page se poser.
    ///
    /// Pendant les deux cents millisecondes de l'arrivée, le geste de la
    /// liseuse est **désarmé** — le temps que l'unité neuve prenne sa place. Un
    /// doigt qui repart aussitôt tombe donc dans une fenêtre où plus personne
    /// ne le réclame, et le système peut s'en saisir.
    func testDeuxGestesCoupSurCoup() {
        ouvrir("bereshit-9")
        exigerDuTexte("au départ, avant tout geste")

        for volee in 1...3 {
            feuilleter(versLaSuivante: true, repos: 0.10)
            feuilleter(versLaSuivante: true, repos: 1.2)
            exigerDuTexte("après la \(volee)ᵉ volée de deux gestes enchaînés")
        }
    }

    /// Le geste pris **bas** dans la page, près de la barre du bas.
    ///
    /// L'indicateur d'accueil y règne, et un glissement qui le frôle peut
    /// quitter l'app plutôt que tourner la page.
    func testLeGesteBasDansLaPage() {
        ouvrir("bereshit-9")
        exigerDuTexte("au départ, avant tout geste")

        for tour in 1...3 {
            feuilleter(versLaSuivante: true, hauteur: 0.86)
            exigerDuTexte("après \(tour) geste(s) pris bas dans la page")
        }
    }

    /// La reprise de lecture, puis le geste — le chemin réellement emprunté.
    ///
    /// C'est la seule route que les liens profonds n'exercent pas : « Reprendre »
    /// ouvre l'unité **et** la fait défiler jusqu'au verset retenu, ce qu'aucun
    /// autre chemin ne fait. Une pile paresseuse y est exposée deux fois — au
    /// moment de viser un rang pas encore posé, et au moment de feuilleter
    /// depuis une page qu'on vient de faire glisser.
    func testReprendrePuisFeuilleter() {
        // Se donner une position à reprendre : ouvrir, puis tourner une page —
        // c'est ce tour qui l'écrit.
        ouvrir("bereshit-11")
        feuilleter(versLaSuivante: true)
        app.terminate()
        app.launch()
        Thread.sleep(forTimeInterval: 2)

        let reprendre = app.staticTexts["Reprendre"].firstMatch
        XCTAssertTrue(reprendre.waitForExistence(timeout: 10), "la carte « Reprendre » est absente")
        reprendre.tap()
        Thread.sleep(forTimeInterval: 3)
        exigerDuTexte("juste après « Reprendre »")

        for tour in 1...3 {
            feuilleter(versLaSuivante: true)
            exigerDuTexte("après « Reprendre » puis \(tour) tour(s)")
        }
        for tour in 1...3 {
            feuilleter(versLaSuivante: false, depuisLeBord: true)
            exigerDuTexte("après « Reprendre » puis \(tour) retour(s) au bord")
        }
    }

    /// Le vide **passager** : la page est-elle nue à l'instant où elle arrive ?
    ///
    /// Les autres tests laissent une seconde et demie à la mise en page avant
    /// de regarder, et ne verraient donc jamais un trou qui se comble. Or c'est
    /// exactement ce qu'un œil attrape : on tourne la page, on voit du blanc,
    /// le texte paraît un instant plus tard.
    ///
    /// Ce test relève l'encre tout de suite, puis à intervalles, et rapporte la
    /// courbe. Il n'échoue que si le vide **dure**.
    func testLeVideEstIlPassager() {
        ouvrir("bereshit-9")
        exigerDuTexte("au départ, avant tout geste")

        var pire = Int.max
        for tour in 1...4 {
            feuilleter(versLaSuivante: true, repos: 0)
            var courbe: [Int] = []
            for _ in 0..<8 {
                courbe.append(encreDeLecture())
                Thread.sleep(forTimeInterval: 0.20)
            }
            print("ONT-COURBE tour \(tour) : \(courbe)")
            pire = min(pire, courbe.first ?? 0)
            XCTAssertGreaterThan(
                courbe.last ?? 0, 40,
                "la page est restée vide une seconde et demie après le tour \(tour)"
            )
        }
        print("ONT-PIRE encre a l'instant de l'arrivee : \(pire)")
    }

    /// Descendre dans la page — là où les trous vivaient.
    ///
    /// C'est le reproche fait à la pile paresseuse quand on y avait renoncé :
    /// un bloc n'apparaissait qu'après sa mise en page, et la page laissait du
    /// blanc en défilant. Aucun autre test ici ne descend d'une ligne.
    func testDescendreDansLaPageSansTrou() {
        ouvrir("bereshit-11")
        exigerDuTexte("au départ, avant de descendre")

        let page = app.windows.firstMatch
        var creux: [Int] = []
        for pas in 1...12 {
            let haut = page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.80))
            let bas = page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.20))
            haut.press(forDuration: 0.05, thenDragTo: bas, withVelocity: .default,
                       thenHoldForDuration: 0.02)
            // Tout de suite : c'est l'instant du trou, pas celui d'après.
            let tout_de_suite = encreDeLecture()
            Thread.sleep(forTimeInterval: 0.6)
            let apres = encreDeLecture()
            creux.append(tout_de_suite)
            print("ONT-DESCENTE pas \(pas) : immediat=\(tout_de_suite) apres=\(apres)")
            XCTAssertGreaterThan(
                apres, 40,
                "trou durable au pas \(pas) de la descente"
            )
        }
        print("ONT-DESCENTE minimum immediat : \(creux.min() ?? -1)")
    }

    /// Feuilleter ne fait pas sortir de la lecture.
    ///
    /// Le glissement vers l'unité **précédente** part du bord gauche et pousse
    /// vers la droite : c'est exactement le geste de retour du système, et les
    /// deux se disputent le doigt. Si le système gagne, on se retrouve sur la
    /// table des matières — page sans corps de texte.
    func testFeuilleterNeQuittePasLaLecture() {
        ouvrir("bereshit-9")
        exigerDuTexte("au départ, avant tout geste")

        for tour in 1...4 {
            feuilleter(versLaSuivante: false)
            exigerDuTexte("après \(tour) retour(s) vers la précédente")
        }
    }
}
