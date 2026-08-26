import UIKit
import XCTest

/// La **surface** qu'un intraduisible offre au doigt.
///
/// ## Ce que les épreuves de composition ne peuvent pas voir
///
/// `ZoneTactileTests` relève ce que porte chaque caractère et dit que tout est
/// en ordre : les six lettres d'« Elohim » portent le lien de leur fiche. Elles
/// répondent donc à *« quelle est la plage ? »*.
///
/// Le lecteur, lui, ne touche pas une plage : il touche une **surface**,
/// calculée par le moteur de texte après la mise en page. Rien n'oblige les
/// deux à coïncider — un caractère ne connaît ni sa position sur la page ni sa
/// hauteur en points.
///
/// ## Pourquoi on vise par les pixels, et non par l'accessibilité
///
/// Première tentative : passer par les éléments d'accessibilité, en pariant sur
/// la note du renderer qui dit que SwiftUI en expose **un par fragment de
/// lien**. Le relevé a réfuté le pari — un verset entier est exposé comme
/// **un seul élément**, « Verset 1. Quand Elohim (elohim / … » de 358 × 1258
/// points. C'est voulu : la phrase a été unifiée pour que VoiceOver cesse de
/// hacher le texte en quatre-vingt-quinze morceaux. Mais la conséquence est
/// qu'aucun élément ne désigne le mot doré, et qu'on ne peut pas le viser par
/// là.
///
/// L'or, lui, se voit. On le cherche donc **dans l'image** : les pixels de la
/// couleur du terme donnent la position exacte du mot à l'écran, sans rien
/// supposer de la mise en page et sans rien ajouter au code de production.
@MainActor
final class ZoneDUnIntraduisibleTests: XCTestCase {
    private var app: XCUIApplication!

    /// Le minimum recommandé par la HIG d'Apple pour une cible tactile.
    private static let cibleMinimale: CGFloat = 44

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    private func retenir(_ nom: String) {
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = nom
        capture.lifetime = .keepAlways
        add(capture)
    }

    private func joindre(_ texte: String, _ nom: String) {
        let piece = XCTAttachment(string: texte)
        piece.name = nom
        piece.lifetime = .keepAlways
        add(piece)
        print(texte)
    }

    // MARK: - Trouver l'or dans l'image

    /// Un mot doré repéré à l'écran, en **points**.
    private struct MotDore {
        var cadre: CGRect
        var pixels: Int
    }

    /// Les deux ors du thème : `goldDeep` en clair, `gold` en sombre.
    private static let orsAttendus: [(r: Double, g: Double, b: Double)] = [
        (0.65, 0.53, 0.31),
        (0.804, 0.745, 0.514),
    ]

    /// Repère les amas de pixels dorés et rend leurs cadres, en points d'écran.
    ///
    /// On regroupe par **bandes de ligne** puis par proximité horizontale : deux
    /// colonnes séparées de plus d'une chasse appartiennent à deux mots. La
    /// tolérance est large parce que le lissage des glyphes délave les bords —
    /// on cherche le centre d'un mot, pas son contour exact.
    private func motsDores(dans image: UIImage) -> [MotDore] {
        guard let cg = image.cgImage else { return [] }
        let l = cg.width, h = cg.height
        var octets = [UInt8](repeating: 0, count: l * h * 4)
        guard let ctx = CGContext(
            data: &octets, width: l, height: h,
            bitsPerComponent: 8, bytesPerRow: l * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: l, height: h))

        // Les pixels dorés, rangés par ligne de balayage.
        var parLigne: [Int: [Int]] = [:]
        for y in stride(from: 0, to: h, by: 1) {
            for x in stride(from: 0, to: l, by: 1) {
                let i = (y * l + x) * 4
                let r = Double(octets[i]) / 255
                let v = Double(octets[i + 1]) / 255
                let b = Double(octets[i + 2]) / 255
                let dore = Self.orsAttendus.contains { or in
                    abs(r - or.r) < 0.10 && abs(v - or.g) < 0.10 && abs(b - or.b) < 0.10
                }
                if dore { parLigne[y, default: []].append(x) }
            }
        }
        guard !parLigne.isEmpty else { return [] }

        // Regrouper les lignes contiguës en bandes — une bande, une ligne de
        // texte.
        let lignes = parLigne.keys.sorted()
        var bandes: [[Int]] = []
        var courante: [Int] = [lignes[0]]
        for y in lignes.dropFirst() {
            if y - courante.last! <= 2 { courante.append(y) }
            else { bandes.append(courante); courante = [y] }
        }
        bandes.append(courante)

        // Dans chaque bande, séparer les amas horizontaux.
        let echelle = image.scale
        var mots: [MotDore] = []
        for bande in bandes {
            let xs = bande.flatMap { parLigne[$0] ?? [] }.sorted()
            guard let premier = xs.first else { continue }
            var debut = premier, precedent = premier, compte = 0
            func fermer() {
                let cadre = CGRect(
                    x: CGFloat(debut) / echelle,
                    y: CGFloat(bande.first!) / echelle,
                    width: CGFloat(precedent - debut + 1) / echelle,
                    height: CGFloat(bande.count) / echelle
                )
                if cadre.width > 8 { mots.append(MotDore(cadre: cadre, pixels: compte)) }
            }
            for x in xs {
                // Plus de 14 pixels de blanc : c'est un autre mot.
                if x - precedent > 14 { fermer(); debut = x; compte = 0 }
                precedent = x
                compte += 1
            }
            fermer()
        }
        return mots.sorted { $0.pixels > $1.pixels }
    }

    // MARK: - Le relevé

    func testReleverLaSurfaceDesMotsDores() {
        app.open(URL(string: "ont://read/bereshit/bereshit-1")!)
        _ = app.wait(for: .runningForeground, timeout: 5)
        sleep(3)
        retenir("00-chapitre-ouvert")

        let ecran = XCUIScreen.main.screenshot().image
        let mots = motsDores(dans: ecran)

        var releve = """

        ══════ LES MOTS DORÉS, MESURÉS DANS L'IMAGE ══════
        écran \(ecran.size.width) × \(ecran.size.height) pt (échelle \(ecran.scale))
        \(mots.count) amas dorés trouvés. Cible HIG : \(Self.cibleMinimale) pt.

        """
        for (i, m) in mots.prefix(25).enumerated() {
            let sous = m.cadre.height < Self.cibleMinimale ? "  ← hauteur sous la cible" : ""
            releve += String(
                format: "  %2d.  %6.1f × %5.1f  à (%6.1f, %6.1f)  %5d px%@\n",
                i, m.cadre.width, m.cadre.height, m.cadre.minX, m.cadre.minY,
                m.pixels, sous as NSString
            )
        }
        joindre(releve, "mots-dores")

        XCTAssertFalse(mots.isEmpty, "Aucun mot doré à l'écran — rien à mesurer.")
    }

    // MARK: - Le geste du lecteur, refait sur le mot lui-même

    /// Trois appuis sur **le même mot doré** : sa première lettre, son milieu,
    /// sa dernière lettre.
    ///
    /// C'est le geste que la session Android a refait de son côté, où les trois
    /// répondent. Si l'un des trois manque ici, le défaut signalé est reproduit
    /// — et localisé.
    func testToucherUnMotDoreEnTroisPoints() {
        app.open(URL(string: "ont://read/bereshit/bereshit-1")!)
        _ = app.wait(for: .runningForeground, timeout: 5)
        sleep(3)

        let mots = motsDores(dans: XCUIScreen.main.screenshot().image)
        guard let mot = mots.first else {
            retenir("aucun-mot-dore")
            XCTFail("Aucun mot doré trouvé à l'écran.")
            return
        }

        var releve = """

        ══════ LE MOT VISÉ ══════
        cadre \(mot.cadre.width) × \(mot.cadre.height) pt à (\(mot.cadre.minX), \(mot.cadre.minY))

        """

        let fenetre = app.windows.firstMatch
        let taille = fenetre.frame.size
        let y = mot.cadre.midY

        for (nom, x) in [
            ("premiere-lettre", mot.cadre.minX + 3),
            ("milieu", mot.cadre.midX),
            ("derniere-lettre", mot.cadre.maxX - 3),
        ] {
            fenetre.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: x, dy: y))
                .tap()
            sleep(2)

            let ouverte = app.staticTexts["אֱלֹהִים"].exists
                || app.staticTexts.allElementsBoundByIndex.contains {
                    $0.label.contains("Occurrences") || $0.label.contains("occurrence")
                }
            releve += "  \(nom)  à x=\(Int(x)), y=\(Int(y))  →  fiche ouverte : \(ouverte)\n"
            retenir("appui-\(nom)")

            if ouverte {
                app.swipeDown(velocity: .fast)
                sleep(2)
            }
        }

        releve += "\n  (fenêtre \(taille.width) × \(taille.height) pt)\n"
        joindre(releve, "trois-appuis")
    }

    // MARK: - La hauteur de la bande, par balayage

    /// Jusqu'où au-dessus et au-dessous du mot le doigt ouvre-t-il encore sa
    /// fiche ?
    ///
    /// La largeur est acquise — les trois appuis passent. Reste la hauteur, qui
    /// est celle de la **ligne** et non celle du glyphe, et qui suit donc le
    /// corps du texte. La session Android l'a mesurée chez elle par le même
    /// balayage : 35 à 42 dp à corps 19. On rend le chiffre iOS pour que les
    /// deux plateformes soient sur la même grandeur.
    ///
    /// En prose continue, l'enjeu n'est pas le vide : c'est que le verset entier
    /// porte lui aussi un lien. Un appui qui manque la bande du mot **n'échoue
    /// pas** — il désigne le verset. Le lecteur ne voit donc pas « rien ne s'est
    /// passé », il voit « autre chose s'est passé », et il croit avoir mal visé.
    func testBalayerLaHauteurDeLaBande() {
        let fenetre = app.windows.firstMatch
        var ouvertes: [CGFloat] = []
        var encre = CGRect.zero
        var releve = "\n══════ BALAYAGE VERTICAL ══════\n"

        // **Un état neuf à chaque appui.** La première version enchaînait les
        // appuis sur la même page, en refermant la fiche par un balayage vers le
        // bas — qui fait aussi défiler le texte. Chaque appui suivant visait donc
        // une position périmée, et deux exécutions de la même configuration ont
        // rendu 27 pt puis 36 pt. On rouvre le chapitre et on relocalise le mot
        // avant chaque appui : c'est plus lent, et c'est reproductible.
        for dy in stride(from: -30.0, through: 30.0, by: 3.0) {
            app.open(URL(string: "ont://read/bereshit/bereshit-1")!)
            _ = app.wait(for: .runningForeground, timeout: 5)
            sleep(2)

            guard let mot = motsDores(dans: XCUIScreen.main.screenshot().image).first else {
                releve += String(format: "  dy %+6.1f  →  mot introuvable\n", dy)
                continue
            }
            encre = mot.cadre
            let y = mot.cadre.midY + dy
            fenetre.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: mot.cadre.midX, dy: y))
                .tap()
            sleep(1)

            let ouverte = app.staticTexts["אֱלֹהִים"].exists
            if ouverte { ouvertes.append(dy) }
            releve += String(format: "  dy %+6.1f  (y = %6.1f)  →  %@\n",
                             dy, y, (ouverte ? "FICHE" : "—") as NSString)
        }

        releve += "\n  encre : \(encre.width) × \(encre.height) pt\n"
        if let bas = ouvertes.first, let haut = ouvertes.last {
            releve += "  bande active : \(haut - bas + 3) pt  (dy de \(bas) à \(haut))\n"
            print("RESULTAT_BANDE \(bas) \(haut) \(encre.height)")
        } else {
            releve += "  aucune ouverture\n"
            print("RESULTAT_BANDE 0 0 \(encre.height)")
        }
        joindre(releve, "balayage-vertical")
    }

    // MARK: - Ce que fait un appui manqué

    /// Rater la bande du mot : est-ce que **rien** ne se passe, ou est-ce que
    /// **le verset est désigné** ?
    ///
    /// La distinction décide du correctif. Si rater ne fait rien, le lecteur
    /// retouche et le défaut n'est qu'une gêne de précision. Si rater **désigne
    /// le verset**, alors il ne voit pas « raté » mais « autre chose s'est
    /// passé » — un état visible qu'il faut refermer —, et il en conclut qu'il a
    /// mal visé. C'est alors le presque-raté qu'il faut rattraper, pas la bande
    /// qu'il faut agrandir.
    ///
    /// Le marqueur d'une sélection est le bouton « Désélectionner » de la carte.
    func testCeQueFaitUnAppuiManque() {
        let fenetre = app.windows.firstMatch
        var releve = "\n══════ CE QUE FAIT CHAQUE APPUI ══════\n"

        for dy in stride(from: -33.0, through: 33.0, by: 3.0) {
            app.open(URL(string: "ont://read/bereshit/bereshit-1")!)
            _ = app.wait(for: .runningForeground, timeout: 5)
            sleep(2)

            guard let mot = motsDores(dans: XCUIScreen.main.screenshot().image).first else {
                releve += String(format: "  dy %+6.1f  →  mot introuvable\n", dy)
                continue
            }
            fenetre.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: mot.cadre.midX, dy: mot.cadre.midY + dy))
                .tap()
            sleep(1)

            let fiche = app.staticTexts["אֱלֹהִים"].exists
            let verset = app.buttons["Désélectionner"].exists
            let quoi = fiche ? "FICHE" : (verset ? "VERSET DÉSIGNÉ" : "rien")
            releve += String(format: "  dy %+6.1f  →  %@\n", dy, quoi as NSString)
        }

        joindre(releve, "appuis-manques")
    }
}
