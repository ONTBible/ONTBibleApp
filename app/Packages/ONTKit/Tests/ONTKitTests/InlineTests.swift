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

/// Les espaces que `plainText` laisse derrière ce qu'il omet.
///
/// Le défaut se voyait sur la page des surlignages : « Quand Elohim   commença
/// à orchestrer   les Cieux ». Trois espaces, parce qu'un nœud hébreu entouré
/// d'espaces avait disparu entre deux fragments de texte. En lecture il ne se
/// voyait pas — le nœud y est rendu.
struct EspacesDuTexteNu {
    @Test("un nœud omis ne laisse pas ses deux espaces")
    func leNoeudOmis() {
        let noeuds: [Inline] = [
            .text("Quand Elohim "), .hebrew("אֱלֹהִים"), .text(" commença"),
        ]
        #expect(noeuds.plainText() == "Quand Elohim commença")
    }

    @Test("une glose éteinte non plus")
    func laGloseEteinte() {
        let noeuds: [Inline] = [
            .text("la Lumière "), .gloss([.text("ce qui éclaire")]), .text(" advint"),
        ]
        #expect(noeuds.plainText() == "la Lumière advint")
    }

    /// **Le retour à la ligne survit.** C'est une décision de mise en page du
    /// traducteur — la seconde ligne d'un parallélisme —, pas un espace.
    @Test("le retour à la ligne reste, et ne traîne pas d'espace")
    func leRetourALaLigne() {
        let noeuds: [Inline] = [
            .text("Qu'advienne la Lumière "), .lineBreak, .text(" Et la Lumière advint"),
        ]
        #expect(noeuds.plainText() == "Qu'advienne la Lumière\nEt la Lumière advint")
    }

    @Test("un espace légitime entre deux fragments reste un espace")
    func lEspaceLegitime() {
        let noeuds: [Inline] = [.text("les "), .emphasis([.text("Cieux")]), .text(" et la Terre")]
        #expect(noeuds.plainText() == "les Cieux et la Terre")
    }

    @Test("rien ne dépasse aux deux bouts")
    func lesBouts() {
        #expect([Inline].init([.hebrew("א"), .text(" Bereshit ")]).plainText() == "Bereshit")
    }
}

/// La ponctuation, quand une omission laisse un espace devant elle.
struct PonctuationDuTexteNu {
    @Test("un point ne prend pas d'espace devant")
    func lePoint() {
        let noeuds: [Inline] = [.text("la Lumière "), .hebrew("אוֹר"), .text(" . »")]
        #expect(noeuds.plainText() == "la Lumière. »")
    }

    @Test("une virgule non plus")
    func laVirgule() {
        let noeuds: [Inline] = [.text("les Cieux "), .hebrew("שָׁמַיִם"), .text(" , et la Terre")]
        #expect(noeuds.plainText() == "les Cieux, et la Terre")
    }

    /// **Mais le deux-points et le chevron fermant en prennent un** : c'est la
    /// règle française, et le corpus l'applique déjà.
    @Test("le deux-points et le chevron gardent le leur")
    func laHauteePonctuation() {
        let noeuds: [Inline] = [.text("Elohim formula "), .hebrew("א"), .text(" : « oui »")]
        #expect(noeuds.plainText() == "Elohim formula : « oui »")
    }
}
