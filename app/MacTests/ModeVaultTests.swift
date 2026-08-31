import Foundation
import Testing

@testable import ONTMac

/// Le relevé du compte-rendu du pipeline.
///
/// **C'est la seule partie du mode vault qui peut mentir en silence.** Le reste
/// échoue bruyamment — un dossier illisible, un binaire absent, un pipeline qui
/// rend un code non nul. Mais un relevé qui prend le mauvais nombre affiche
/// « 3 unités » d'un corpus qui en a 44, et rien ne le contredit.
@Suite("Le compte-rendu du pipeline")
struct ModeVaultTests {

    @Test("la ligne des unités se lit")
    func laLigneSeLit() {
        let rendu = """
            → le corpus — vault du 2026-08-30T02:05:02Z
            Unités     41 chapitres + 3 intros — 864 versets
            Glossaire  108 entrées — 2184 occurrences indexées
            """
        let (unites, versets) = ModeVault.compter(rendu)
        #expect(unites == 44, "les intros comptent comme des unités")
        #expect(versets == 864)
    }

    /// **Les intros s'ajoutent, elles ne remplacent pas.**
    ///
    /// `chazon-avraham` n'a aucun chapitre : tout son contenu est une intro.
    /// Ne compter que le premier nombre effacerait un livre entier — le même
    /// oubli que celui qui laissait `Yaho'el` hors de l'index.
    @Test("un corpus sans chapitre compte quand même")
    func lesIntrosComptent() {
        let (unites, _) = ModeVault.compter("Unités     0 chapitres + 3 intros — 40 versets")
        #expect(unites == 3)
    }

    /// Un compte-rendu qu'on ne sait pas lire rend zéro, jamais un nombre
    /// plausible tiré d'une autre ligne.
    @Test(
        "ce qui ne porte pas la ligne rend zéro",
        arguments: [
            "",
            "Anomalies  0 termes inconnus",
            "Unités",
            "Unités     41 chapitres",
        ]
    )
    func lIllisibleRendZero(_ rendu: String) {
        let (unites, versets) = ModeVault.compter(rendu)
        #expect(unites == 0 && versets == 0, "« \(rendu) » a rendu quelque chose")
    }
}

/// **Le vault se retrouve-t-il d'une session à l'autre ?**
///
/// Sous bac à sable, le droit de lire un dossier est accordé **au processus**
/// par le sélecteur, et meurt avec lui. Un chemin relu des réglages désignerait
/// le bon dossier sans l'ouvrir : l'app dirait « dossier illisible » d'un
/// dossier parfaitement lisible, et l'auteur chercherait du côté du disque.
///
/// D'où le signet, qui garde le droit et non le chemin. Ces épreuves mesurent
/// l'aller-retour — enregistrer, résoudre, oublier — et **non le bac à sable**,
/// qui ne s'applique qu'à une app signée. Ce qu'elles gardent, c'est que la
/// mécanique de reprise est juste ; que le bac l'honore se vérifie à la main,
/// sur une app signée, et c'est écrit dans le README.
@MainActor
@Suite("La reprise du vault")
struct ReprisDuVaultTests {
    /// Des réglages à soi, effacés après coup.
    ///
    /// `UserDefaults.standard` ferait écrire l'épreuve dans les réglages de
    /// l'app installée : elle retirerait à l'auteur le vault qu'il suit, ou
    /// lui en désignerait un qu'il n'a pas choisi.
    private func reglagesJetables() -> UserDefaults {
        let nom = "essai.vault.\(UUID().uuidString)"
        return UserDefaults(suiteName: nom)!
    }

    private func dossierJetable() -> URL {
        let d = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vault-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @Test("un vault suivi se retrouve à la session suivante")
    func laReprise() {
        let reglages = reglagesJetables()
        let dossier = dossierJetable()
        defer { try? FileManager.default.removeItem(at: dossier) }

        let premiere = ModeVault(reglages: reglages)
        premiere.suivre(dossier)
        #expect(premiere.vault != nil)

        // Une instance neuve, comme au lancement suivant : elle ne sait rien
        // que les réglages ne lui disent.
        let seconde = ModeVault(reglages: reglages)
        #expect(seconde.vault == nil, "rien tant qu'on n'a pas repris")
        seconde.reprendre()
        defer { seconde.arreter() }

        // Comparés par chemin résolu : `/var` et `/private/var` désignent le
        // même dossier, et le signet rend la forme canonique. Comparer les URL
        // ferait échouer une épreuve qui a pourtant raison.
        #expect(
            seconde.vault?.resolvingSymlinksInPath().path
                == dossier.resolvingSymlinksInPath().path,
            "le vault n'a pas été repris : \(String(describing: seconde.vault))")
    }

    @Test("« cesser de suivre » cesse pour de bon")
    func lArretOublie() {
        let reglages = reglagesJetables()
        let dossier = dossierJetable()
        defer { try? FileManager.default.removeItem(at: dossier) }

        let premiere = ModeVault(reglages: reglages)
        premiere.suivre(dossier)
        premiere.arreter()

        let seconde = ModeVault(reglages: reglages)
        seconde.reprendre()
        #expect(seconde.vault == nil, "le vault est revenu après qu'on a cessé de le suivre")
    }

    /// **Un signet caduc s'oublie, il ne se retente pas.**
    ///
    /// Un dossier déplacé, effacé, ou sur un volume démonté rend le signet
    /// irrésoluble. Le garder ferait échouer *chaque* lancement pour un dossier
    /// dont l'auteur ne se sert peut-être plus — un défaut qui se réveille tout
    /// seul, longtemps après le geste qui l'a causé.
    @Test("un signet illisible est oublié plutôt que retenté")
    func leSignetCaduc() {
        let reglages = reglagesJetables()
        reglages.set(Data([0x00, 0x01, 0x02, 0x03]), forKey: "vault.signet")

        let mode = ModeVault(reglages: reglages)
        mode.reprendre()

        #expect(mode.vault == nil)
        #expect(
            reglages.data(forKey: "vault.signet") == nil,
            "le signet caduc est resté : il échouera encore au prochain lancement")
    }
}
