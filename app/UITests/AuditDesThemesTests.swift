import XCTest

/// Un balayage : chaque écran, dans le thème du moment.
///
/// Un thème ne se relit pas, il se regarde. Une couleur oubliée sur un écran
/// qu'on ouvre rarement ne se voit ni au compilateur, ni au test unitaire, ni
/// à la relecture — seulement à l'usage, et souvent par le lecteur avant nous.
///
/// Le thème n'est pas choisi ici : il est écrit dans les préférences avant le
/// lancement. C'est ce qui permet de rejouer le même parcours pour les quatre
/// sans dépendre de la navigation dans les réglages.
@MainActor
final class AuditDesThemesTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        Thread.sleep(forTimeInterval: 2)
    }

    private func retenir(_ nom: String) {
        let c = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        c.name = nom
        c.lifetime = .keepAlways
        add(c)
    }

    private func ouvrir(_ url: String, _ nom: String, attente: TimeInterval = 3) {
        app.open(URL(string: url)!)
        Thread.sleep(forTimeInterval: attente)
        retenir(nom)
    }

    /// Écrit dans le champ de recherche, où qu'il soit.
    ///
    /// `typeText` sur l'app entière échoue — « Neither element nor any
    /// descendant has keyboard focus ». Il faut d'abord poser le doigt dans le
    /// champ, comme une main le ferait.
    private func saisir(_ texte: String, _ nom: String) {
        let champ = app.searchFields.firstMatch
        guard champ.waitForExistence(timeout: 5) else {
            retenir("\(nom)-CHAMP-ABSENT")
            return
        }
        champ.tap()
        Thread.sleep(forTimeInterval: 0.6)
        // Vider ce qu'une saisie précédente a laissé.
        if let valeur = champ.value as? String, !valeur.isEmpty {
            champ.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: valeur.count))
        }
        champ.typeText(texte)
        Thread.sleep(forTimeInterval: 3)
        retenir(nom)
    }

    private func toucher(_ libelle: String, _ nom: String, attente: TimeInterval = 2) {
        let b = app.buttons[libelle].firstMatch
        guard b.waitForExistence(timeout: 5) else {
            retenir("\(nom)-ABSENT")
            return
        }
        b.tap()
        Thread.sleep(forTimeInterval: attente)
        retenir(nom)
    }

    /// Ce que le premier balayage ne voyait pas.
    ///
    /// Dix écrans, c'était les plus fréquentés. Les autres — celui qu'on ouvre
    /// une fois par mois pour changer l'heure du rappel, celui qui s'excuse
    /// quand un terme n'est pas documenté — sont précisément ceux où une
    /// couleur oubliée survit le plus longtemps.
    func testParcourirLesEcransRares() {
        // Un parcours qui **continue** après une marche ratée.
        //
        // Il ne vérifie rien : il montre. S'arrêter au premier bouton
        // introuvable ne priverait pas d'une assertion, ça priverait des dix
        // captures suivantes — c'est-à-dire de tout l'intérêt.
        continueAfterFailure = true

        // La recherche, depuis la table.
        toucher("Bible", "20-bible")
        toucher("Rechercher", "21-recherche", attente: 3)
        saisir("lumiere", "22-recherche-resultats")
        saisir("zzzzqqqq", "23-recherche-sans-resultat")
        toucher("Annuler", "24-recherche-fermee")

        // Un livre, et sa liste de chapitres.
        toucher("Torah", "25-section-torah")
        let premier = app.buttons.element(boundBy: 3)
        if premier.exists { premier.tap(); Thread.sleep(forTimeInterval: 2) }
        retenir("26-livre")

        // Le renvoi, depuis la lecture.
        ouvrir("ont://read/bereshit/bereshit-3", "27-lecture")
        let renvoi = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Aller à un autre passage'")
        ).firstMatch
        if renvoi.waitForExistence(timeout: 5) {
            renvoi.tap(); Thread.sleep(forTimeInterval: 2); retenir("28-renvoi")
            toucher("Fermer", "29-renvoi-ferme", attente: 1)
        } else {
            retenir("28-renvoi-ABSENT")
        }

        // Les réglages de lecture, et leur dialogue de remise à zéro.
        ouvrir("ont://read/bereshit/bereshit-3", "30-lecture")
        toucher("Lecture", "31-reglages", attente: 3)
        app.swipeUp()
        Thread.sleep(forTimeInterval: 1)
        retenir("32-reglages-bas")
        toucher("Réinitialiser les réglages", "33-remise-a-zero", attente: 2)
        toucher("Annuler", "34-remise-annulee", attente: 1)
        toucher("OK", "35-reglages-fermes", attente: 2)

        // La note, depuis un verset désigné.
        ouvrir("ont://read/bereshit/bereshit-3?v=2", "36-selection", attente: 4)
        toucher("Noter", "37-note", attente: 3)
        toucher("Annuler", "38-note-fermee", attente: 2)

        // Le rappel quotidien.
        toucher("Vous", "39-vous")
        toucher("Verset du jour", "40-rappel", attente: 3)

        // Un terme qui n'a pas d'entrée.
        ouvrir("ont://term/terme-qui-nexiste-pas", "41-terme-inconnu", attente: 4)
    }

    func testParcourirTousLesEcrans() {
        retenir("01-accueil")

        toucher("Qahal", "02-qahal")
        toucher("Vous", "03-vous")
        toucher("Lexique", "04-lexique")
        toucher("Bible", "05-bible-table")

        ouvrir("ont://read/bereshit/bereshit-3", "06-lecture")
        ouvrir("ont://read/bereshit/bereshit-3?v=2", "07-lecture-selection", attente: 4)

        // La fiche d'un intraduisible — l'écran qui a révélé l'oubli.
        ouvrir("ont://term/elohim", "08-fiche-terme", attente: 4)

        // Les réglages de lecture, atteints par la barre.
        ouvrir("ont://read/bereshit/bereshit-3", "09-retour-lecture")
        toucher("Lecture", "10-reglages-lecture", attente: 3)
    }
}
