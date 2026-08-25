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

    /// Le renvoi que le pipeline écrit dans le corpus, ouvert par le routeur.
    ///
    /// **C'est le maillon qui reliait deux chantiers sans que rien ne le
    /// vérifie.** Le pipeline résout « Bereshit 9:27 » vers l'unité neuf,
    /// verset interne dix — la numérotation ONT repart de 1 à chaque unité —
    /// et l'écrit en adresse absolue vers le site, pour qu'une liseuse qui ne
    /// sait pas intercepter ouvre quand même quelque chose d'utile.
    ///
    /// Ici, l'app doit la rattraper : `RootView` renvoie tout `openURL` au
    /// routeur, qui reconnaît son propre domaine et ouvre l'unité **sans
    /// jamais sortir vers Safari**.
    @Test("un renvoi du corpus ouvre l'unité au verset, sans passer par Safari")
    func renvoiDuCorpus() {
        let router = Router()
        let url = URL(string: "https://ontbible.com/fr/lire/bereshit/bereshit-9?v=10#v10")!
        #expect(router.open(url), "le routeur doit reconnaître le domaine du site")

        #expect(router.tab == .bible)
        #expect(
            router.biblePath == [
                .book("bereshit"),
                .chapter(book: "bereshit", chapter: "bereshit-9"),
            ]
        )
        #expect(router.pendingVerse == 10, "le verset désigné doit être repris")
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
        #expect(router.pendingVerse == 19)
    }
}
