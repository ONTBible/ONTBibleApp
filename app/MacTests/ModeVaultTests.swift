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
