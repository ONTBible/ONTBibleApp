// **Ce banc tranche une question ; il ne garde pas un invariant.**
//
// Il ne doit donc **pas** entrer dans la CI. Ses valeurs absolues dépendent du
// simulateur et de la machine — il rougirait pour des raisons qui ne sont pas
// du code, et un contrôle qui rougit sans défaut finit par ne plus être lu.
//
// Ce qu'il sait faire, et qui vaut : répondre « de combien » quand quelqu'un
// dit « c'est plus lent ». Il l'a fait le 20 septembre 2026 — 517 ms de trop
// sur la désignation, mesurés là où l'auteur les avait sentis.
//
// **Les coordonnées sont éprouvées sur `ONT` (iPhone 17 Pro, 1206×2622) et
// nulle part ailleurs.** Sur un autre appareil, `dy 0,02` pourrait tomber sur
// un verset, et le contrôle négatif deviendrait en silence un second appui
// ordinaire. C'est pourquoi le banc **lit** la barre « Partager » au lieu de
// la supposer : ce témoin dira tout de suite que les coordonnées ne valent
// plus.
//
// Écrit par la session assistante d'iOS/iPadOS, volet wE:p4.

import UIKit
import XCTest

/// Combien de temps s'écoule entre l'appui sur un verset et la page stabilisée.
///
/// L'auteur a écrit « mtn la selection est super lente » après un premier
/// correctif, et personne n'avait de chiffre — ni avant, ni après. Ce banc
/// existe pour en donner un, sur trois états du code.
///
/// ## Ce qu'on mesure, et ce qu'on ne mesure pas
///
/// On mesure **le temps de mur** entre le `tap` et le moment où deux captures
/// consécutives de l'écran sont identiques. C'est la latence *vécue* : elle
/// inclut la recomposition SwiftUI, la mise en page du texte et le dessin.
///
/// Elle ne vaut qu'à la résolution d'un aller-retour de capture — de l'ordre
/// de 40 à 60 ms sur simulateur. C'est assez pour séparer « fluide » d'une
/// lenteur sentie à l'usage ; ce n'est pas assez pour départager 30 ms de
/// 60 ms. Si la réponse tombait dans cet intervalle, la réponse serait « c'est
/// fluide », et un instrument plus fin ne changerait pas la décision.
///
/// ## Pourquoi pas `scripts/banc-chapitre.swift`
///
/// Il monte son propre TextKit en AppKit et ne connaît ni `ChapterView` ni
/// `Prose`. Il rendrait le même chiffre sur les trois états du code —
/// reproductible, et muet sur la question posée.
@MainActor
final class LatenceDesignationTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    /// Une empreinte grossière de l'écran, assez fine pour voir le voile
    /// tomber et assez grossière pour coûter moins que la capture elle-même.
    private func empreinte() -> Int {
        guard let image = XCUIScreen.main.screenshot().image.cgImage else { return -1 }
        let l = image.width, h = image.height
        var octets = [UInt8](repeating: 0, count: l * h)
        guard let ctx = CGContext(data: &octets, width: l, height: h, bitsPerComponent: 8,
                                  bytesPerRow: l, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: 0) else { return -1 }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: l, height: h))
        // Un échantillon régulier : on cherche « l'image a-t-elle bougé »,
        // pas « de combien ». Une somme pondérée par la position distingue
        // deux images de même encre totale mais de disposition différente.
        var h1 = 5381
        for y in stride(from: 0, to: h, by: 8) {
            for x in stride(from: 0, to: l, by: 8) {
                h1 = (h1 &* 33) &+ Int(octets[y * l + x])
            }
        }
        return h1
    }

    /// Attend que l'écran cesse de bouger, et rend le temps que ça a pris.
    ///
    /// « Stable » = deux empreintes consécutives identiques. On rend le temps
    /// mesuré **à la première des deux**, sans quoi on facturerait à la page
    /// l'aller-retour de capture qui a servi à constater qu'elle avait fini.
    private func attendreStabilite(depuis t0: CFAbsoluteTime, limite: Double = 12) -> Double? {
        var precedente = empreinte()
        var tPrecedente = CFAbsoluteTimeGetCurrent()
        while CFAbsoluteTimeGetCurrent() - t0 < limite {
            let e = empreinte()
            let t = CFAbsoluteTimeGetCurrent()
            if e == precedente { return (tPrecedente - t0) * 1000 }
            precedente = e
            tPrecedente = t
        }
        return nil
    }

    func testLatenceDeLaDesignation() {
        // bereshit-17 : 27 versets, l'unité lourde que la session iOS a
        // mesurée à 13 960 pt de haut — le pire cas, pas la moyenne.
        app.open(URL(string: "ont://read/bereshit/bereshit-17")!)
        Thread.sleep(forTimeInterval: 6)
        XCTAssertNotNil(attendreStabilite(depuis: CFAbsoluteTimeGetCurrent(), limite: 20),
                        "la page de départ n'est jamais devenue stable")

        let page = app.windows.firstMatch
        let cible = page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))

        // ── Deux contrôles, sans quoi le chiffre principal ne veut rien dire ──
        //
        // Un banc qui ne peut pas rendre un petit chiffre ne mesure pas la
        // page : il mesure sa propre boucle. On établit donc d'abord ce que
        // l'instrument coûte quand il n'y a rien à attendre.
        //
        // (1) LE BRUIT — la page ne bouge pas, personne n'a touché à rien.
        //     C'est le plancher de l'instrument : deux captures et l'égalité.
        let bruit = attendreStabilite(depuis: CFAbsoluteTimeGetCurrent(), limite: 5) ?? -1
        print(String(format: "ONT-LATENCE-CONTROLE bruit (aucun appui) : %.0f ms", bruit))

        // (2) L'APPUI MORT — on tape dans la marge, où il n'y a pas de verset.
        //     Si ce chiffre égale celui d'un vrai appui, alors ce que je
        //     mesure n'est pas la désignation mais le fait de toucher l'écran.
        //     Première version : un tap en marge à dx 0.02. Il a rendu 568 ms,
        //     soit 453 de plus que le bruit — donc il ne s'agissait pas d'un
        //     appui mort. On vérifie maintenant ce qu'il fait au lieu de le
        //     supposer inerte : la barre d'actions est le témoin.
        let marge = page.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.42))
        let tMort = CFAbsoluteTimeGetCurrent()
        marge.tap()
        let mort = attendreStabilite(depuis: tMort, limite: 8) ?? -1
        let margeADesigne = app.buttons["Partager"].waitForExistence(timeout: 2)
        print(String(format: "ONT-LATENCE-CONTROLE appui marge : %.0f ms — a designe : %@",
                     mort, margeADesigne ? "OUI (ce n'est pas un controle negatif)" : "non"))
        if margeADesigne { cible.tap(); Thread.sleep(forTimeInterval: 1.2) }
        Thread.sleep(forTimeInterval: 1.2)

        //     Un second candidat au contrôle négatif : l'en-tête de la page,
        //     tout en haut, qui ne porte aucun verset.
        let entete = page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06))
        let tEntete = CFAbsoluteTimeGetCurrent()
        entete.tap()
        let inerte = attendreStabilite(depuis: tEntete, limite: 8) ?? -1
        let enteteADesigne = app.buttons["Partager"].waitForExistence(timeout: 2)
        print(String(format: "ONT-LATENCE-CONTROLE appui en-tete : %.0f ms — a designe : %@",
                     inerte, enteteADesigne ? "OUI" : "non"))
        if enteteADesigne { cible.tap(); Thread.sleep(forTimeInterval: 1.2) }
        Thread.sleep(forTimeInterval: 1.2)

        // (3) LA PREUVE QUE L'APPUI DÉSIGNE — sans elle, un banc qui tape dans
        //     le vide rendrait huit chiffres parfaitement stables et faux.
        cible.tap()
        let barre = app.buttons["Partager"].waitForExistence(timeout: 5)
        print("ONT-LATENCE-CONTROLE barre d'actions apres appui : \(barre)")
        Thread.sleep(forTimeInterval: 1.0)
        cible.tap()  // on relâche, pour repartir d'une page nue
        Thread.sleep(forTimeInterval: 1.2)

        var designer: [Double] = []
        var relacher: [Double] = []
        var echecs = 0

        for tour in 0..<8 {
            let t0 = CFAbsoluteTimeGetCurrent()
            cible.tap()
            guard let ms = attendreStabilite(depuis: t0) else {
                echecs += 1
                print("ONT-LATENCE tour \(tour) : jamais stabilisé")
                Thread.sleep(forTimeInterval: 1)
                continue
            }
            // Un tour sur deux désigne, l'autre relâche. Les deux sont des
            // remises en page, mais pas la même : les confondre dans une
            // moyenne effacerait celle qui coûte.
            if tour % 2 == 0 { designer.append(ms) } else { relacher.append(ms) }
            print("ONT-LATENCE tour \(tour) \(tour % 2 == 0 ? "designer" : "relacher") : \(String(format: "%.0f", ms)) ms")
            Thread.sleep(forTimeInterval: 0.8)
        }

        // Le premier appui paie des caches que les suivants ne paient plus :
        // on le rend à part, comme `banc-chapitre.swift` sépare froid et chaud.
        func resume(_ nom: String, _ v: [Double]) {
            guard !v.isEmpty else { print("ONT-LATENCE \(nom) : aucune mesure"); return }
            let froid = v[0]
            let chaud = v.dropFirst()
            let moy = chaud.isEmpty ? froid : chaud.reduce(0, +) / Double(chaud.count)
            print(String(format: "ONT-LATENCE-RESUME %@ froid %.0f ms | chaud %.0f ms (n=%d, min %.0f, max %.0f)",
                         nom, froid, moy, chaud.count, chaud.min() ?? froid, chaud.max() ?? froid))
        }
        // ── Le marquage seul, barre déjà ouverte ──
        //
        // Proposé par la session iOS, et c'est le bon geste : désigner un
        // SECOND verset pendant que la barre d'actions est déjà là. L'animation
        // d'apparition n'a plus lieu, la page ne remonte plus — il ne reste
        // que le recalcul des marques. L'écart avec un premier appui donne à
        // peu près ce que coûte le marquage, séparé de son décor.
        //
        // On ne le mesure QUE si les contrôles ont validé le banc : un second
        // chiffre bâti sur un instrument non validé vaudrait moins que rien.
        if bruit >= 0 && bruit < 250 {
            cible.tap()  // le premier : ouvre la barre
            Thread.sleep(forTimeInterval: 1.5)
            let autre = page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.66))
            var successifs: [Double] = []
            for _ in 0..<4 {
                let t = CFAbsoluteTimeGetCurrent()
                autre.tap()
                if let ms = attendreStabilite(depuis: t, limite: 8) { successifs.append(ms) }
                Thread.sleep(forTimeInterval: 0.8)
                let t2 = CFAbsoluteTimeGetCurrent()
                cible.tap()
                if let ms = attendreStabilite(depuis: t2, limite: 8) { successifs.append(ms) }
                Thread.sleep(forTimeInterval: 0.8)
            }
            if !successifs.isEmpty {
                let moy = successifs.reduce(0, +) / Double(successifs.count)
                print(String(format: "ONT-LATENCE-RESUME barre-deja-ouverte %.0f ms (n=%d, min %.0f, max %.0f)",
                             moy, successifs.count, successifs.min()!, successifs.max()!))
            }
        } else {
            print("ONT-LATENCE-RESUME barre-deja-ouverte : non mesure, banc non valide")
        }

        resume("designer", designer)
        resume("relacher", relacher)
        print("ONT-LATENCE-RESUME echecs \(echecs)")

        // Le banc ne juge pas : il chiffre. La seule chose qu'il refuse, c'est
        // de rendre un chiffre qui ne repose sur rien.
        XCTAssertFalse(designer.isEmpty, "aucun appui n'a jamais stabilisé la page")
    }
}
