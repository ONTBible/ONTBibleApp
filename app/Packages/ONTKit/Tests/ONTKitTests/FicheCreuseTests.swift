import Testing

@testable import ONTKit

/// Une fiche qui n'a rien à dire du terme.
///
/// Cinq intraduisibles ont vécu ainsi : déclarés, balisés dans tout le corpus,
/// affichés en or et touchables — et sans aucune entrée au glossaire. Les
/// compteurs du pipeline restaient au vert, parce qu'ils vérifient qu'un terme
/// a une **fiche**, jamais qu'il a une **définition**.
///
/// C'est la quatrième garde d'une même série à ne pas poser la question. La
/// session du site l'a formulée le mieux : *on vérifie l'existence du lien,
/// jamais la substance de la cible*.
struct FicheCreuseTests {
    private func entree(_ definition: [Block]?) -> GlossaryEntry {
        GlossaryEntry(
            lemma: "neshamah", title: "neshamah", tagged: true, forms: ["neshamah"],
            hebrew: "נְשָׁמָה", rendering: nil, definition: definition, taggingNote: nil,
            firstUse: nil, sourceSection: nil, count: 3, bodyCount: 3, glossCount: 0)
    }

    /// **Deux formes de vide, une seule conséquence.** Un terme absent du
    /// glossaire rend `nil` ; un terme dont la section existe sans prose rend
    /// une liste vide. La fiche est creuse dans les deux cas, et c'est la seule
    /// chose qui compte pour qui la lit.
    @Test("un champ absent et un champ vide sont tous deux creux")
    func lesDeuxVides() {
        #expect(entree(nil).sansDefinition)
        #expect(entree([]).sansDefinition)
    }

    @Test("une fiche qui dit quelque chose n'est pas creuse")
    func laFichePleine() {
        #expect(!entree([.paragraph([.text("Le souffle qui fait vivre.")])]).sansDefinition)
    }
}
