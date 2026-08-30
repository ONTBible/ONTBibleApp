import Foundation
import Testing

@testable import ONTKit

/// Ce qu'un lecteur a marqué, rassemblé.
///
/// Le classement est tout l'enjeu : rendre la bonne liste dans le mauvais ordre
/// donne une page qu'on ne peut pas parcourir. C'est éprouvé ici plutôt qu'à
/// l'écran, parce que rien de tout cela ne demande un simulateur.
struct SurlignagesTests {
    private func unite(_ id: String, _ n: Int) -> ChapterStub {
        ChapterStub(
            id: id, n: n, title: id, status: .locked, verseCount: 40, reference: nil)
    }

    private func livre(_ id: String, slot: Int, unites: [ChapterStub]) -> BookOutline {
        BookOutline(
            id: id, slot: slot, title: id, french: id, glose: nil, hebrew: nil,
            groupId: nil, empty: false, intro: nil, chapters: unites)
    }

    private func marque(
        _ livre: String, _ unite: String, _ verset: Int, _ couleur: HighlightColor = .gold
    ) -> Highlight {
        Highlight(
            id: UUID(), bookId: livre, chapterId: unite, verse: verset,
            color: couleur, note: nil, updatedAt: Date(timeIntervalSince1970: 0))
    }

    private var corpus: [BookOutline] {
        [
            livre("bereshit", slot: 1, unites: [unite("b-2", 2), unite("b-11", 11)]),
            livre("shemot", slot: 2, unites: [unite("s-1", 1)]),
        ]
    }

    private func texte(_ h: Highlight) -> (corps: String, renvoi: String)? {
        ("le corps de \(h.chapterId):\(h.verse)", "\(h.chapterId):\(h.verse)")
    }

    /// **L'ordre du corpus, pas celui des dates.**
    @Test("les livres sortent dans l'ordre des slots")
    func lOrdreDesLivres() {
        let rendu = Surlignages.parLivre(
            [marque("shemot", "s-1", 3), marque("bereshit", "b-2", 5)],
            livres: corpus, texte: texte)

        #expect(rendu.map(\.id) == ["bereshit", "shemot"])
    }

    /// **Une unité se trie par son rang, jamais par son nom.**
    ///
    /// « Bereshit 11 » précède « Bereshit 2 » quand on compare les chaînes, et
    /// c'est exactement ce qu'un tri naïf ferait. Le sommaire fait foi.
    @Test("les unités suivent le sommaire, pas l'alphabet")
    func lOrdreDesUnites() {
        let rendu = Surlignages.parLivre(
            [marque("bereshit", "b-11", 1), marque("bereshit", "b-2", 1)],
            livres: corpus, texte: texte)

        #expect(rendu.first?.surlignages.map(\.renvoi) == ["b-2:1", "b-11:1"])
    }

    @Test("dans une même unité, les versets montent")
    func lOrdreDesVersets() {
        let rendu = Surlignages.parLivre(
            [marque("bereshit", "b-2", 12), marque("bereshit", "b-2", 3)],
            livres: corpus, texte: texte)

        #expect(rendu.first?.surlignages.map(\.surlignage.verse) == [3, 12])
    }

    /// Un verset que le corpus ne porte plus — livre remanié entre deux
    /// publications. La ligne disparaît au lieu de s'afficher vide.
    @Test("un verset introuvable est écarté, pas rendu vide")
    func leVersetDisparu() {
        let rendu = Surlignages.parLivre(
            [marque("bereshit", "b-2", 5)], livres: corpus, texte: { _ in nil })

        #expect(rendu.isEmpty)
    }

    /// Et un livre dont **tous** les versets ont disparu ne laisse pas un
    /// en-tête seul au-dessus du vide.
    @Test("un livre sans ligne lisible ne laisse pas son en-tête")
    func leLivreVide() {
        let rendu = Surlignages.parLivre(
            [marque("bereshit", "b-2", 5), marque("shemot", "s-1", 1)],
            livres: corpus,
            texte: { $0.bookId == "shemot" ? self.texte($0) : nil })

        #expect(rendu.map(\.id) == ["shemot"])
    }

    /// Le filtre garde l'ordre déclaré des couleurs, et non celui des marques.
    @Test("le décompte par couleur ne bouge pas d'une fois sur l'autre")
    func leDecompteParCouleur() {
        let rendu = Surlignages.parCouleur([
            marque("bereshit", "b-2", 1, HighlightColor.allCases[2]),
            marque("bereshit", "b-2", 2, HighlightColor.allCases[0]),
            marque("bereshit", "b-2", 3, HighlightColor.allCases[2]),
        ])

        #expect(rendu.map(\.0) == [HighlightColor.allCases[0], HighlightColor.allCases[2]])
        #expect(rendu.map(\.1) == [1, 2])
    }
}
