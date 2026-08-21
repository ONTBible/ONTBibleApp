import Foundation
import Testing

@testable import ONTKit

/// L'arbre inline — ses projections.
///
/// Le décodage n'est plus éprouvé ici : il ne se fait plus ici. `ONTKit` est le
/// domaine, il ne connaît pas le JSON du pipeline, et les tests de contrat
/// vivent dans `ONTDataTests/SchemaMappingTests`.
///
/// Ce qui reste est du domaine pur — et se construit donc en Swift, sans passer
/// par une chaîne de caractères. Un test qui décodait du JSON pour fabriquer
/// trois nœuds éprouvait deux choses à la fois, et échouait pour la mauvaise
/// raison quand le format bougeait.
struct InlineTests {
    @Test("le texte nu ne rend que le corps par défaut")
    func plainTextDefaults() {
        let nodes: [Inline] = [
            .text("il était assis "),
            .translit("petach", hebrew: "פֶּתַח"),
            .gloss([.text("le seuil")]),
        ]

        let body = nodes.plainText()
        #expect(!body.contains("petach"), "le niveau 3 est hors du corps")
        #expect(!body.contains("seuil"), "la glose est hors du corps")

        #expect(nodes.plainText(gloss: true).contains("seuil"))
        #expect(nodes.plainText(level3: true).contains("פֶּתַח"))
    }

    @Test("les lemmes remontent des gloses aussi")
    func lemmasIncludeGlosses() {
        let nodes: [Inline] = [
            .term("chesed", lemma: "chesed"),
            .gloss([.term("berith", lemma: "berith")]),
        ]

        #expect(nodes.lemmas == ["chesed", "berith"])
    }

    /// Un lien et une accentuation portent des enfants, donc des lemmes.
    ///
    /// Ils avaient été oubliés de la première version de `lemmas`, qui ne
    /// descendait que dans les gloses : un intraduisible cité à l'intérieur
    /// d'un lien n'apparaissait alors dans aucune fiche.
    @Test("les lemmes remontent aussi des liens et des accentuations")
    func lemmasIncludeLinksAndAccentuation() {
        let nodes: [Inline] = [
            .accentuation([.term("Elohim", lemma: "elohim")]),
            .link([.term("berith", lemma: "berith")], href: "/fr/lexique/berith"),
        ]

        #expect(nodes.lemmas == ["elohim", "berith"])
    }
}
