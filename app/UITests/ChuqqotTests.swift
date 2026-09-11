import XCTest

/// L'onglet Chuqqot dit la vérité sur ce qu'il n'a pas.
///
/// ## Le défaut que cette épreuve garde, et pourquoi il fallait un écran
///
/// L'onglet affichait « Cet onglet portera les chuqqot. Ils ne sont pas encore
/// écrits. » Sept l'étaient, et le pipeline émettait déjà `chuqqot.json`.
///
/// **Aucune épreuve unitaire n'aurait attrapé ça.** La phrase était juste du
/// texte dans une vue : rien à décoder, rien à trier, rien qui puisse échouer.
/// Le seul endroit où le défaut existe, c'est à l'écran — donc le seul endroit
/// où on peut le mesurer.
///
/// C'est aussi pourquoi l'épreuve vérifie **les deux moitiés** : que la phrase
/// fausse a disparu, et que la vraie est là. La première seule passerait sur un
/// écran blanc ; la seconde seule passerait si les deux textes cohabitaient.
@MainActor
final class ChuqqotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        Thread.sleep(forTimeInterval: 7)
    }

    /// Tous les libellés visibles, concaténés.
    ///
    /// On cherche dans l'ensemble plutôt que par identifiant : l'état vide est
    /// un `accessibilityElement(children: .combine)`, donc ses trois textes
    /// arrivent fondus en un seul libellé. Viser un `staticTexts["…"]` exact
    /// dépendrait de la façon dont le système les recolle, ce qui n'est pas ce
    /// qu'on veut mesurer.
    private var texteDeLEcran: String {
        app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ␞ ")
    }

    func testLEtatVideDitCeQuIlAttend() {
        app.buttons["Chuqqot"].tap()
        Thread.sleep(forTimeInterval: 2)

        let vue = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        vue.name = "onglet-chuqqot"
        vue.lifetime = .keepAlways
        add(vue)

        let texte = texteDeLEcran

        // **Si le corpus embarqué porte des chuqqot, l'écran n'a pas d'état
        // vide à montrer** — et c'est très bien : l'épreuve mesure alors que la
        // liste s'affiche. Elle reste juste dans les deux mondes, ce qui est
        // exigé d'elle : `chuqqot.json` s'écrit vide aujourd'hui, et ne le fera
        // plus le jour où l'auteur validera la première.
        guard texte.contains("Rien à lire pour l'instant") else {
            // **La branche pleine, et elle va jusqu'au bout du geste.**
            //
            // Vérifier que la liste existe ne prouverait que la moitié : une
            // liste dont aucune ligne n'ouvre rien ressemble à une liste qui
            // marche. On touche donc la première, et l'on regarde si le texte
            // est arrivé.
            //
            // Elle ne s'exécute pas aujourd'hui — `chuqqot.json` s'écrit vide
            // tant que rien n'est validé —, et c'est exactement pour ça qu'elle
            // est écrite maintenant : le jour où l'auteur validera la première
            // chuqqah, c'est le seul contrôle qui dira si l'écran a suivi.
            // Elle a été éprouvée en montant un `dist/` d'essai à trois
            // chuqqot verrouillées, le 11 septembre 2026.
            // **`app.cells.buttons` et non `app.cells`.**
            //
            // Une première écriture prenait `app.cells.firstMatch` : c'est
            // l'en-tête de section « ce qui est gravé », qui est une cellule
            // lui aussi. Le geste tombait dessus, rien ne s'empilait — et
            // l'assertion d'alors, qui comptait les caractères à l'écran,
            // **passait quand même** : la liste en porte déjà beaucoup.
            //
            // Deux leçons dans le même défaut, et la seconde est la vraie :
            // un mauvais sélecteur se voit, un contrôle qui ne peut pas rougir
            // ne se voit pas. C'est en lui faisant échouer qu'on l'a trouvé.
            //
            // Le rang d'une chuqqah est un `NavigationLink`, donc un bouton,
            // et un en-tête n'en porte aucun : cette requête ne peut pas
            // attraper l'en-tête, quel que soit le nombre de sections.
            let premiere = app.cells.buttons.firstMatch
            XCTAssertTrue(
                premiere.waitForExistence(timeout: 5),
                "ni état vide ni liste : l'onglet Chuqqot ne montre rien du tout — \(texte)")

            let titre = premiere.label
            premiere.tap()
            Thread.sleep(forTimeInterval: 3)

            let page = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            page.name = "chuqqah-ouverte"
            page.lifetime = .keepAlways
            add(page)

            // **Le bouton de retour est la preuve.** Il n'existe que si une
            // page a été empilée, et il porte le nom de l'écran d'où l'on
            // vient. Compter les caractères à l'écran ne prouvait rien : la
            // liste seule en porte déjà beaucoup.
            XCTAssertTrue(
                app.navigationBars.buttons["Chuqqot"].waitForExistence(timeout: 5),
                "toucher « \(titre) » n'a empilé aucune page")
            return
        }

        XCTAssertFalse(
            texte.contains("ne sont pas encore écrits"),
            """
            L'onglet dit encore que les chuqqot ne sont pas écrites. \
            Elles le sont — sept vivent dans `brouillons/chuqqot/` du vault — \
            et ce qui manque est leur validation, pas leur rédaction.
            """)

        XCTAssertTrue(
            texte.contains("attendent leur validation"),
            "l'état vide ne dit pas ce qu'il attend — \(texte)")
    }
}
