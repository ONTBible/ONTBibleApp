import Foundation
import Testing

@testable import ONTKit

/// Le routeur — les liens `ont://` et la navigation partagée.
@MainActor
struct RouterTests {
    @Test("un lien de lecture ouvre le livre et l'unité")
    func readLink() {
        let router = Router()
        #expect(router.open(URL(string: "ont://read/bereshit/bereshit-18")!))

        #expect(router.tab == .bible)
        #expect(
            router.biblePath == [
                .book("bereshit"),
                .chapter(book: "bereshit", chapter: "bereshit-18"),
            ]
        )
    }

    @Test("un lien de livre seul s'arrête à sa table")
    func bookLink() {
        let router = Router()
        #expect(router.open(URL(string: "ont://read/bereshit")!))
        #expect(router.biblePath == [.book("bereshit")])
    }

    @Test("un lien de terme soulève une fiche sans changer d'onglet")
    func termLink() {
        let router = Router()
        router.tab = .qahal
        #expect(router.open(URL(string: "ont://term/chesed")!))

        #expect(router.openedLemma?.id == "chesed")
        #expect(router.tab == .qahal, "la fiche se soulève, elle ne navigue pas")
    }

    @Test("un lien étranger est laissé au système")
    func foreignLink() {
        let router = Router()
        #expect(!router.open(URL(string: "https://example.com")!))
        #expect(!router.open(URL(string: "ont://inconnu/x")!))
    }

    @Test("ouvrir un résultat de recherche vise le verset")
    func openAtVerse() {
        let router = Router()
        router.open(book: "bereshit", chapter: "bereshit-18", verse: 19)

        #expect(router.tab == .bible)
        #expect(router.pendingVerse?.n == 19)
    }
}
