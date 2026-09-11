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

    /// **Un renvoi vers l'unité qu'on lit déjà empile quand même.**
    ///
    /// Ce test exigeait l'inverse. Il encodait une garde dont la prémisse est
    /// fausse : le sommet de la pile n'est pas ce que le lecteur voit, puisque
    /// le glissement de page ne touche pas au chemin. La garde avalait donc des
    /// renvois parfaitement légitimes, et sans verset à désigner il ne restait
    /// rien — un silence que le lecteur lit comme une panne.
    @Test func un_renvoi_vers_l_unite_du_dessus_empile_quand_meme() {
        let router = Router()
        router.open(URL(string: "ont://read/bereshit/bereshit-7")!)
        router.open(URL(string: "ont://renvoi/bereshit/bereshit-7?v=4")!)
        #expect(router.biblePath.count == 3, "n'a pas empilé — \(router.biblePath)")
        #expect(router.pendingSelection == [4])
    }

    /// Le cas qui a motivé le retrait : un renvoi **sans verset** vers l'unité
    /// que la pile porte déjà. Il n'y a rien à désigner — s'il n'empile pas, il
    /// ne fait rien.
    @Test func un_renvoi_sans_verset_navigue_quand_meme() {
        let router = Router()
        router.open(URL(string: "ont://read/bereshit/bereshit-5")!)
        let avant = router.biblePath
        router.open(URL(string: "ont://renvoi/bereshit/bereshit-5")!)
        #expect(router.biblePath != avant, "rien ne s'est passé — \(router.biblePath)")
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
