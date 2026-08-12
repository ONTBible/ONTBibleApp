import Foundation
import Testing

@testable import ONTKit

/// L'arbre inline — décodage et projections.
///
/// Ces tests portent sur le **contrat avec le pipeline** : si la forme du JSON
/// change sans qu'on s'en aperçoive, c'est ici que ça casse.
struct InlineTests {
    private func decode(_ json: String) throws -> [Inline] {
        try JSONDecoder().decode([Inline].self, from: Data(json.utf8))
    }

    @Test("les trois niveaux se décodent en nœuds distincts")
    func decodesLevels() throws {
        let nodes = try decode(
            """
            [
              {"t":"term","v":"YHWH","lemma":"yhwh"},
              {"t":"text","v":" se laissa voir "},
              {"t":"translit","translit":"vayera","hebrew":"וַיֵּרָא"},
              {"t":"gloss","children":[{"t":"text","v":"niphal de ra'ah"}]}
            ]
            """
        )

        #expect(nodes.count == 4)
        if case .term(let value, let lemma) = nodes[0] {
            #expect(value == "YHWH")
            #expect(lemma == "yhwh")
        } else {
            Issue.record("le premier nœud devrait être un intraduisible")
        }
    }

    @Test("le texte nu ne rend que le corps par défaut")
    func plainTextDefaults() throws {
        let nodes = try decode(
            """
            [
              {"t":"text","v":"il était assis "},
              {"t":"translit","translit":"petach","hebrew":"פֶּתַח"},
              {"t":"gloss","children":[{"t":"text","v":"le seuil"}]}
            ]
            """
        )

        let body = nodes.plainText()
        #expect(!body.contains("petach"), "le niveau 3 est hors du corps")
        #expect(!body.contains("seuil"), "la glose est hors du corps")

        #expect(nodes.plainText(gloss: true).contains("seuil"))
        #expect(nodes.plainText(level3: true).contains("פֶּתַח"))
    }

    @Test("les lemmes remontent des gloses aussi")
    func lemmasIncludeGlosses() throws {
        let nodes = try decode(
            """
            [
              {"t":"term","v":"chesed","lemma":"chesed"},
              {"t":"gloss","children":[{"t":"term","v":"berith","lemma":"berith"}]}
            ]
            """
        )

        #expect(nodes.lemmas == ["chesed", "berith"])
    }

    @Test("un type de nœud inconnu est signalé, pas ignoré")
    func rejectsUnknown() {
        #expect(throws: DecodingError.self) {
            _ = try decode(#"[{"t":"quelque-chose-de-neuf","v":"x"}]"#)
        }
    }
}
