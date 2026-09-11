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

// MARK: - Le renvoi empile

@MainActor
@Suite("Un renvoi empile au lieu de remplacer")
struct RenvoiQuiEmpile {
    /// Le cas que l'auteur a demandé : suivre un renvoi depuis une lecture en
    /// cours, et que le retour rende le chapitre d'où l'on vient.
    @Test func un_renvoi_empile_sur_la_lecture_en_cours() {
        let router = Router()
        router.open(URL(string: "ont://read/bereshit/bereshit-7")!)
        #expect(router.biblePath.count == 2)

        router.open(URL(string: "ont://renvoi/bereshit/bereshit-1?v=2")!)
        #expect(
            router.biblePath == [
                .book("bereshit"),
                .chapter(book: "bereshit", chapter: "bereshit-7"),
                .chapter(book: "bereshit", chapter: "bereshit-1"),
            ],
            "la pile devrait porter trois échelons — \(router.biblePath)"
        )
        #expect(router.pendingSelection == [2])
    }

    /// `read` continue de remplacer : c'est ce que le widget attend.
    @Test func read_remplace_toujours() {
        let router = Router()
        router.open(URL(string: "ont://read/bereshit/bereshit-7")!)
        router.open(URL(string: "ont://read/bereshit/bereshit-1")!)
        #expect(router.biblePath.count == 2, "read a empilé — \(router.biblePath)")
    }

    /// Un renvoi vers l'unité qu'on lit déjà ne s'empile pas sur lui-même.
    @Test func un_renvoi_vers_soi_meme_n_empile_rien() {
        let router = Router()
        router.open(URL(string: "ont://read/bereshit/bereshit-7")!)
        router.open(URL(string: "ont://renvoi/bereshit/bereshit-7?v=4")!)
        #expect(router.biblePath.count == 2, "empilé sur soi-même — \(router.biblePath)")
        #expect(router.pendingSelection == [4])
    }

    /// Touché hors de la lecture, le renvoi pose le livre sous l'unité.
    @Test func un_renvoi_depuis_une_pile_vide_pose_le_livre() {
        let router = Router()
        router.open(URL(string: "ont://renvoi/bereshit/bereshit-1?v=2")!)
        #expect(
            router.biblePath == [
                .book("bereshit"),
                .chapter(book: "bereshit", chapter: "bereshit-1"),
            ],
            "\(router.biblePath)"
        )
    }
}
