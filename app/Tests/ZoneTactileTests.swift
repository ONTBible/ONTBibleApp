import ONTDesignSystem
import ONTKit
import SwiftUI
import Testing

/// Ce que porte réellement chaque caractère d'un verset composé.
///
/// ## Pourquoi ces épreuves existent
///
/// Un lecteur a signalé qu'en prose continue il devait **viser** pour ouvrir la
/// fiche d'un intraduisible — souvent seule la première lettre répondait. Rien
/// dans le code ne le montrait : la composition pose bien `termURL(lemma)` sur
/// le mot entier, et `poserLeLien` relève ses plages avant d'écrire, donc la
/// faute classique de l'invalidation par fusion n'était pas là non plus.
///
/// Un défaut de zone tactile ne se voit ni à la compilation, ni au rendu, ni en
/// relisant la composition. Il ne se voit qu'en **regardant le résultat**, un
/// caractère à la fois. C'est ce que fait ce fichier : il ne vérifie pas que le
/// code a l'air juste, il relève ce que la chaîne composée porte vraiment.
///
/// La règle qu'ils défendent tient en une phrase : **un intraduisible répond au
/// doigt sur toute sa longueur, ou il ne répond pas du tout.** Un mot qui ne
/// s'ouvre que sur sa première lettre est pire qu'un mot inerte, parce qu'il
/// apprend au lecteur que le geste est un coup de chance.
struct ZoneTactileTests {

    // MARK: - Outillage

    /// Le lien porté par chaque caractère, dans l'ordre.
    ///
    /// On parcourt les **caractères** et non les runs : un run est un détail de
    /// représentation, et c'est précisément ce que le doigt ne connaît pas. La
    /// question posée par le lecteur est « ce caractère-ci répond-il », pas
    /// « combien de runs ».
    private func liens(_ chaine: AttributedString) -> [(caractere: Character, cible: URL?)] {
        var sortie: [(Character, URL?)] = []
        var i = chaine.startIndex
        while i < chaine.endIndex {
            let suivant = chaine.index(afterCharacter: i)
            sortie.append((chaine.characters[i], chaine[i..<suivant].link))
            i = suivant
        }
        return sortie
    }

    /// Le relevé lisible, pour que l'échec dise *où* et pas seulement *que*.
    private func releve(_ chaine: AttributedString) -> String {
        liens(chaine)
            .map { paire in
                let cible = paire.cible.map(\.absoluteString) ?? "—"
                return "  \(paire.caractere == " " ? "␣" : paire.caractere)   \(cible)"
            }
            .joined(separator: "\n")
    }

    /// Les caractères d'un mot et ce qu'ils portent, retrouvés dans le relevé.
    private func porteDuMot(
        _ mot: String,
        dans chaine: AttributedString
    ) -> [(caractere: Character, cible: URL?)] {
        let releve = liens(chaine)
        let lettres = Array(mot)
        for depart in releve.indices where depart + lettres.count <= releve.count {
            let tranche = Array(releve[depart..<(depart + lettres.count)])
            if tranche.map(\.caractere) == lettres { return tranche }
        }
        return []
    }

    private func verseAvecIntraduisible() -> Verse {
        // La forme la plus courante du corpus : de la prose, un intraduisible
        // au milieu, de la prose. C'est le cas que le lecteur a signalé.
        Verse(n: 3, nodes: [
            .text("Et "),
            .term("Elohim", lemma: "elohim"),
            .text(" formula"),
        ])
    }

    // MARK: - Le mot entier répond

    @Test("en prose, un intraduisible répond sur toute sa longueur")
    func termeEntierEnProse() throws {
        let corps = ONTTextRenderer.corpsEnProse(verseAvecIntraduisible(), theme: ONTTheme())
        let attendu = try #require(ONTTextRenderer.termURL("elohim"))

        let mot = porteDuMot("Elohim", dans: corps)
        #expect(mot.count == 6, "« Elohim » introuvable dans le relevé")

        // Chaque lettre, pas seulement la première : c'est tout l'objet.
        let muettes = mot.filter { $0.cible != attendu }
        #expect(
            muettes.isEmpty,
            """
            \(muettes.count) lettre(s) sur 6 n'ouvrent pas la fiche : \
            \(String(muettes.map(\.caractere)))
            Relevé complet :
            \(releve(corps))
            """
        )
    }

    @Test("le lien du verset ne déborde pas sur le mot")
    func leVersetNeMangePasLeMot() throws {
        let corps = ONTTextRenderer.corpsEnProse(verseAvecIntraduisible(), theme: ONTTheme())
        let duVerset = try #require(ONTTextRenderer.verseURL(3))

        // Le lien du verset est posé *après*, partout où il n'y en a pas.
        // S'il déborde d'un seul caractère sur le mot, le doigt tombe sur le
        // verset au lieu de la fiche — et le lecteur croit avoir mal visé.
        let deborde = porteDuMot("Elohim", dans: corps).filter { $0.cible == duVerset }
        #expect(
            deborde.isEmpty,
            """
            Le lien du verset a mangé \(deborde.count) lettre(s) du mot : \
            \(String(deborde.map(\.caractere)))
            Relevé complet :
            \(releve(corps))
            """
        )
    }

    @Test("en prose, aucun caractère ne reste muet")
    func aucuneZoneMorte() throws {
        let corps = ONTTextRenderer.corpsEnProse(verseAvecIntraduisible(), theme: ONTTheme())
        let duVerset = try #require(ONTTextRenderer.verseURL(3))
        let duTerme = try #require(ONTTextRenderer.termURL("elohim"))

        // En prose continue, tout doit répondre — soit la fiche, soit le
        // verset. Un trou est une zone morte, et le doigt n'a aucun moyen de
        // savoir qu'il vient d'en trouver une.
        let muets = liens(corps).filter { $0.cible == nil }
        #expect(
            muets.isEmpty,
            """
            \(muets.count) caractère(s) ne répondent à rien.
            Relevé complet :
            \(releve(corps))
            """
        )

        #expect(Set(liens(corps).compactMap(\.cible)) == Set([duVerset, duTerme]))
    }

    // MARK: - Le mode blocs, pour comparaison

    @Test("en blocs, le mot répond aussi sur toute sa longueur")
    func termeEntierEnBlocs() throws {
        // Le mode blocs ne pose pas de lien de verset : seul l'intraduisible
        // est touchable. Si le défaut n'apparaît qu'en prose, c'est la pose du
        // lien de verset qui le produit — et cette épreuve le dira en restant
        // verte pendant que les autres tombent.
        let corps = ONTTextRenderer.compose(verseAvecIntraduisible().nodes, theme: ONTTheme())
        let attendu = try #require(ONTTextRenderer.termURL("elohim"))

        let manquantes = porteDuMot("Elohim", dans: corps).filter { $0.cible != attendu }
        #expect(
            manquantes.isEmpty,
            """
            En blocs, \(manquantes.count) lettre(s) n'ouvrent pas la fiche.
            Relevé complet :
            \(releve(corps))
            """
        )
    }

    // MARK: - Le cas qui produit beaucoup de runs

    @Test("un verset dense garde ses mots entiers")
    func versetDense() throws {
        // Plusieurs intraduisibles, une glose, un niveau 3 : le balisage qui
        // produit le plus de runs, donc le plus de fusions. Si la pose du lien
        // décale quoi que ce soit, c'est ici que ça se verra.
        let verse = Verse(n: 7, nodes: [
            .term("YHWH", lemma: "yhwh"),
            .text(" "),
            .term("Elohim", lemma: "elohim"),
            .text(" façonna l'"),
            .term("adam", lemma: "adam"),
            .translit("adam", hebrew: "אָדָם"),
            .gloss([.text("de la "), .term("adamah", lemma: "adamah")]),
            .text(" et souffla"),
        ])
        let corps = ONTTextRenderer.corpsEnProse(verse, theme: ONTTheme())

        for (mot, lemme) in [("YHWH", "yhwh"), ("Elohim", "elohim"), ("adamah", "adamah")] {
            let cible = try #require(ONTTextRenderer.termURL(lemme))
            let manquantes = porteDuMot(mot, dans: corps).filter { $0.cible != cible }
            #expect(
                manquantes.isEmpty,
                """
                « \(mot) » : \(manquantes.count) lettre(s) n'ouvrent pas sa fiche.
                Relevé complet :
                \(releve(corps))
                """
            )
        }
    }
}
