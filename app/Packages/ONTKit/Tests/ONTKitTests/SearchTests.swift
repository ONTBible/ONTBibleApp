import Testing

import ONTKit

/// Le moteur de recherche, sur des entrées bâties à la main.
///
/// On teste la logique, pas les données : l'index réel est vérifié côté
/// pipeline. Ce qui doit être garanti ici, c'est que le pliage et le
/// dénudage de l'hébreu se comportent comme leurs homologues TypeScript —
/// s'ils divergent, l'index et la requête ne se rencontrent jamais.
struct SearchTests {
    private func record(
        chapter: String = "bereshit-18",
        verse: Int = 1,
        body: String,
        gloss: String = "",
        hebrew: String = "",
        lemmas: [String] = []
    ) -> SearchRecord {
        SearchRecord(
            b: "bereshit",
            c: chapter,
            v: verse,
            k: .verse,
            t: SearchEngine.fold(body),
            g: SearchEngine.fold(gloss),
            h: SearchEngine.stripHebrew(hebrew),
            l: lemmas,
            x: body
        )
    }

    @Test("les diacritiques et la casse ne bloquent pas la recherche")
    func folding() {
        let records = [record(body: "Et il fut frappé de dysfonctionnement à cause de la rupture")]

        #expect(!SearchEngine.search("frappe", in: records, scope: .body).isEmpty)
        #expect(!SearchEngine.search("FRAPPÉ", in: records, scope: .body).isEmpty)
        #expect(!SearchEngine.search("dysfonctionnement", in: records, scope: .body).isEmpty)
    }

    @Test("l'hébreu se cherche sans les voyelles")
    func hebrewWithoutVowels() {
        // Le texte porte le niqqud ; le lecteur tape des consonnes nues.
        let records = [record(body: "ton chesed", hebrew: "חַסְדְּךָ")]

        let hits = SearchEngine.search("חסדך", in: records, scope: .all)
        #expect(hits.count == 1, "une saisie sans voyelles doit trouver le texte vocalisé")
    }

    @Test("l'hébreu vocalisé se cherche aussi tel quel")
    func hebrewWithVowels() {
        let records = [record(body: "ton chesed", hebrew: "חַסְדְּךָ")]
        #expect(!SearchEngine.search("חַסְדְּךָ", in: records, scope: .all).isEmpty)
    }

    @Test("la portée sépare le corps des gloses")
    func scopes() {
        let records = [
            record(body: "il porta le pardon", gloss: "nasa — porter, lever, soulever"),
        ]

        #expect(SearchEngine.search("soulever", in: records, scope: .body).isEmpty)
        #expect(!SearchEngine.search("soulever", in: records, scope: .gloss).isEmpty)
        #expect(!SearchEngine.search("soulever", in: records, scope: .all).isEmpty)

        #expect(!SearchEngine.search("pardon", in: records, scope: .body).isEmpty)
        #expect(SearchEngine.search("pardon", in: records, scope: .gloss).isEmpty)
    }

    @Test("un intraduisible retrouve les passages où il ne paraît qu'en hébreu")
    func lemmaFallback() {
        let records = [record(body: "un passage sans le mot", hebrew: "חֶסֶד", lemmas: ["chesed"])]

        let hits = SearchEngine.search(
            "chesed",
            in: records,
            scope: .all,
            lemmas: ["chesed"]
        )
        #expect(hits.count == 1)
    }

    @Test("un mot entier passe devant un fragment")
    func ranking() {
        let records = [
            record(chapter: "a", body: "la transalliance et autres composés"),
            record(chapter: "b", body: "une alliance est une structure d'engagement"),
        ]

        let hits = SearchEngine.search("alliance", in: records, scope: .body)
        #expect(hits.first?.record.c == "b", "le mot entier doit primer sur le fragment")
    }

    @Test("une requête trop courte ne rend rien")
    func tooShort() {
        let records = [record(body: "quoi que ce soit")]
        #expect(SearchEngine.search("a", in: records, scope: .all).isEmpty)
    }
}

/// L'identité d'un résultat de recherche.
///
/// Deux résultats distincts ne doivent jamais partager un identifiant : la
/// liste s'en sert comme clé, et une clé doublée fait réutiliser la mauvaise
/// vue. Sur Android elle fait carrément lever.
@Suite("L'identité d'un résultat")
struct IdentiteDUnResultatTests {

    private func intertitre(_ texte: String) -> SearchRecord {
        SearchRecord(
            b: "bereshit", c: "bereshit-15", v: 0, k: .heading,
            t: texte, g: "", h: "", l: [], x: texte
        )
    }

    /// **Le cas réel.** `bereshit-15` porte quatre intertitres, tous au verset
    /// zéro, dont deux contiennent « alliance ».
    @Test("deux intertitres du même verset ont des identifiants distincts")
    func intertitresDuMemeVerset() {
        let hits = SearchEngine.search(
            "alliance",
            in: [
                intertitre("l'alliance entre les morceaux"),
                intertitre("la prophetie de l'exil et le rite de l'alliance"),
            ],
            scope: .body
        )

        #expect(hits.count == 2)
        #expect(Set(hits.map(\.id)).count == 2, "identifiants doublés : \(hits.map(\.id))")
    }

    /// Et l'identifiant ne doit pas bouger entre deux recherches identiques —
    /// sinon il défait les animations qu'il sert à tenir.
    @Test("le même résultat garde le même identifiant")
    func identifiantStable() {
        let records = [intertitre("l'alliance entre les morceaux")]
        let premier = SearchEngine.search("alliance", in: records, scope: .body).map(\.id)
        let second = SearchEngine.search("alliance", in: records, scope: .body).map(\.id)
        #expect(premier == second)
    }
}
