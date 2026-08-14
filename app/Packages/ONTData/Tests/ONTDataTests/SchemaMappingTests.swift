import Foundation
import ONTKit
import Testing

@testable import ONTData

/// Le contrat avec le pipeline — décodage et traduction.
///
/// Si la forme du JSON change sans qu'on s'en aperçoive, c'est ici que ça
/// casse. Ces tests vivaient dans `ONTKitTests`, du temps où le domaine
/// décodait lui-même : ils y éprouvaient un contrat qui n'était pas le sien.
///
/// La plupart des divergences ne les atteindront jamais, et c'est voulu — un
/// type de nœud ajouté au pipeline fait maintenant échouer la **compilation**
/// de `SchemaMapping.swift`. Ce qui reste à éprouver ici, c'est ce qu'un
/// compilateur ne peut pas voir : que chaque étiquette JSON tombe sur la bonne
/// variante du domaine, et qu'une étiquette inconnue lève.
struct SchemaMappingTests {
    private func noeuds(_ json: String) throws -> [Inline] {
        try JSONDecoder()
            .decode([ONTSchema.Inline].self, from: Data(json.utf8))
            .map(Inline.init)
    }

    private func blocs(_ json: String) throws -> [Block] {
        try JSONDecoder()
            .decode([ONTSchema.Block].self, from: Data(json.utf8))
            .map(Block.init)
    }

    @Test("les trois niveaux se décodent en nœuds distincts")
    func lesTroisNiveaux() throws {
        let nodes = try noeuds(
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
        guard case .term(let valeur, let lemme) = nodes[0] else {
            Issue.record("le premier nœud devrait être un intraduisible")
            return
        }
        #expect(valeur == "YHWH")
        #expect(lemme == "yhwh")

        guard case .translit(let translit, let hebreu) = nodes[2] else {
            Issue.record("le troisième nœud devrait être un niveau 3")
            return
        }
        #expect(translit == "vayera")
        #expect(hebreu == "וַיֵּרָא")
    }

    /// Les étiquettes du pipeline et les noms du domaine **ne coïncident pas**,
    /// et c'est le seul endroit où l'écart est franchi.
    ///
    /// `para` devient `paragraph`, `em` devient `emphasis`, `heb` devient
    /// `hebrew`, `break` devient `lineBreak`. Le JSON est court parce qu'il est
    /// répété des dizaines de milliers de fois ; le domaine est lisible parce
    /// qu'on le lit. Une inversion ici ne casserait aucune compilation.
    @Test("chaque étiquette tombe sur la bonne variante du domaine")
    func lesEtiquettesTombentJuste() throws {
        let nodes = try noeuds(
            """
            [
              {"t":"heb","v":"אָדוֹן"},
              {"t":"em","children":[{"t":"text","v":"Bereshit"}]},
              {"t":"important","children":[{"t":"text","v":"Jour"}]},
              {"t":"link","children":[{"t":"text","v":"là"}],"href":"/x"},
              {"t":"break"}
            ]
            """
        )

        guard case .hebrew(let h) = nodes[0] else { Issue.record("heb → hebrew"); return }
        #expect(h == "אָדוֹן")
        guard case .emphasis = nodes[1] else { Issue.record("em → emphasis"); return }
        guard case .important = nodes[2] else { Issue.record("important"); return }
        guard case .link(_, let href) = nodes[3] else { Issue.record("link"); return }
        #expect(href == "/x")
        guard case .lineBreak = nodes[4] else { Issue.record("break → lineBreak"); return }
    }

    @Test("un bloc `para` devient un paragraphe")
    func lesBlocsTombentJuste() throws {
        let blocks = try blocs(
            """
            [
              {"t":"para","nodes":[{"t":"text","v":"prose"}]},
              {"t":"verses","verses":[{"n":1,"nodes":[{"t":"text","v":"un"}]}]},
              {"t":"heading","level":2,"nodes":[{"t":"text","v":"titre"}]},
              {"t":"rule"}
            ]
            """
        )

        guard case .paragraph = blocks[0] else { Issue.record("para → paragraph"); return }
        guard case .verses(let versets) = blocks[1] else { Issue.record("verses"); return }
        #expect(versets.first?.n == 1)
        guard case .heading(let niveau, _) = blocks[2] else { Issue.record("heading"); return }
        #expect(niveau == 2)
        guard case .rule = blocks[3] else { Issue.record("rule"); return }
    }

    /// Un type inconnu **lève**, il n'est pas ignoré.
    ///
    /// C'est la seule défense possible côté app : elle télécharge son corpus,
    /// donc une version installée peut rencontrer un fichier plus récent que le
    /// code qui la lit. Mieux vaut un livre qui refuse de s'ouvrir qu'un livre
    /// auquel il manque des mots sans que personne ne le sache.
    @Test("un type de nœud inconnu est signalé, pas ignoré")
    func unTypeInconnuLeve() {
        #expect(throws: DecodingError.self) {
            _ = try noeuds(#"[{"t":"quelque-chose-de-neuf","v":"x"}]"#)
        }
    }

    @Test("un type de bloc inconnu est signalé, pas ignoré")
    func unBlocInconnuLeve() {
        #expect(throws: DecodingError.self) {
            _ = try blocs(#"[{"t":"colonnes","nodes":[]}]"#)
        }
    }

    /// Le piège des `null` : la clé est **présente** et vaut `null`.
    ///
    /// Un `Optional` le couvre ; un `@Decodable` avec valeur par défaut ne le
    /// couvrirait pas, parce qu'il ne s'applique qu'à la clé absente.
    @Test("un sous-titre d'introduction n'a pas de renvoi")
    func leRenvoiPeutEtreNul() throws {
        let dto = try JSONDecoder().decode(
            ONTSchema.Subtitle.self,
            from: Data(#"{"french":"Genèse","hebrew":"בְּרֵאשִׁית","reference":null}"#.utf8)
        )
        let sous_titre = Subtitle(dto)
        #expect(sous_titre.reference == nil)
        #expect(sous_titre.french == "Genèse")
    }

    @Test("les clés camelCase du pipeline arrivent au domaine")
    func lesClesCamelCase() throws {
        let dto = try JSONDecoder().decode(
            ONTSchema.Stub.self,
            from: Data(
                #"{"id":"bereshit-1","n":1,"title":"Bereshit 1","status":"locked","verseCount":31,"reference":"1:1-31"}"#
                    .utf8)
        )
        let stub = ChapterStub(dto)
        #expect(stub.verseCount == 31)
        #expect(stub.status == .locked)
    }
}
