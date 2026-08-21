import Foundation
import ONTKit
import Testing

@testable import ONT

/// La détection d'un livre qui vient de paraître.
///
/// Ce qui est éprouvé ici n'est pas la notification — iOS ne la livre pas dans
/// un test — mais **l'état retenu entre deux passages**, qui est le seul
/// endroit où cette mécanique peut mentir. Une erreur de comparaison ne casse
/// rien : elle annonce trop, ou jamais, et personne ne s'en aperçoit avant
/// qu'un livre paraisse pour de bon.
struct NouveautesTests {
    /// Un corpus de test : des livres avec leurs chapitres, et des slots vides.
    private struct Faux: CorpusRepository {
        /// `["bereshit": 3]` — un livre et le nombre de chapitres qu'il porte.
        let ecrits: [String: Int]
        let vides: [String]

        init(ecrits: [String: Int], vides: [String] = []) {
            self.ecrits = ecrits
            self.vides = vides
        }

        func corpora() throws -> [Corpus] {
            let livres =
                ecrits.sorted { $0.key < $1.key }.map { slot($0.key, chapitres: $0.value) }
                + vides.map { slot($0, chapitres: 0) }
            return [
                Corpus(
                    id: "kenesset", title: "Kenesset", order: 1,
                    modes: [Mode(id: "torah", title: "Torah", order: 1, books: livres)]
                )
            ]
        }

        func book(_ id: String) throws -> Book {
            throw NSError(domain: "faux", code: 0)
        }

        private func slot(_ id: String, chapitres: Int) -> BookOutline {
            BookOutline(
                id: id, slot: 1, title: id, french: id, hebrew: nil, groupId: nil,
                empty: chapitres == 0, intro: nil,
                chapters: (1...max(chapitres, 1)).prefix(chapitres).map {
                    ChapterStub(
                        id: "\(id)-\($0)", n: $0, title: "\(id) \($0)",
                        status: .locked, verseCount: 10, reference: nil)
                }
            )
        }
    }

    private func defaults(_ nom: String) -> UserDefaults {
        let d = UserDefaults(suiteName: nom)!
        d.removePersistentDomain(forName: nom)
        return d
    }

    @Test("le premier passage n'annonce rien")
    func premierPassageSeTait() async {
        let d = defaults("nouveautes-premier")
        await NouveautesNotifications.verifier(
            Faux(ecrits: ["bereshit": 2], vides: ["iyov"]), defaults: d)

        #expect(
            d.stringArray(forKey: "unites-parues") == ["bereshit:bereshit-1", "bereshit:bereshit-2"],
            "l'état doit être pris, sans quoi la première parution passerait pour connue"
        )
    }

    @Test("un chapitre ajouté à un livre ouvert est une parution")
    func chapitreAjoute() async {
        let d = defaults("nouveautes-chapitre")
        await NouveautesNotifications.verifier(Faux(ecrits: ["bereshit": 2]), defaults: d)
        await NouveautesNotifications.verifier(Faux(ecrits: ["bereshit": 3]), defaults: d)

        #expect(d.stringArray(forKey: "unites-parues")?.count == 3)
    }

    /// Deux livres peuvent numéroter leurs unités pareil. Sans le préfixe du
    /// livre, la parution du chapitre 1 du second passerait pour du déjà-vu.
    @Test("deux livres ne se confondent pas sur un même numéro")
    func pasDeCollisionEntreLivres() async {
        let d = defaults("nouveautes-collision")
        await NouveautesNotifications.verifier(Faux(ecrits: ["bereshit": 1]), defaults: d)
        await NouveautesNotifications.verifier(
            Faux(ecrits: ["bereshit": 1, "shemot": 1]), defaults: d)

        #expect(d.stringArray(forKey: "unites-parues") == ["bereshit:bereshit-1", "shemot:shemot-1"])
    }

    @Test("un slot qui cesse d'être vide devient une parution")
    func slotRempliEstUneParution() async {
        let d = defaults("nouveautes-parution")
        await NouveautesNotifications.verifier(Faux(ecrits: ["bereshit": 1], vides: ["iyov"]), defaults: d)
        await NouveautesNotifications.verifier(Faux(ecrits: ["bereshit": 1, "iyov": 1]), defaults: d)

        #expect(d.stringArray(forKey: "unites-parues") == ["bereshit:bereshit-1", "iyov:iyov-1"])
    }

    @Test("deux passages de suite n'annoncent qu'une fois")
    func idempotente() async {
        let d = defaults("nouveautes-idempotente")
        let avant = Faux(ecrits: ["bereshit": 1], vides: ["iyov"])
        let apres = Faux(ecrits: ["bereshit": 1, "iyov": 1])
        await NouveautesNotifications.verifier(avant, defaults: d)
        await NouveautesNotifications.verifier(apres, defaults: d)
        let etat = d.stringArray(forKey: "unites-parues")
        await NouveautesNotifications.verifier(apres, defaults: d)

        #expect(d.stringArray(forKey: "unites-parues") == etat, "l'état ne doit plus bouger")
    }

    /// Le corpus vide arrive vraiment : au tout premier lancement, avant que
    /// le bundle ne soit lu, `writtenBooks()` peut ne rien rendre. Enregistrer
    /// un état vide ferait passer les quatre livres existants pour des
    /// parutions à la synchronisation suivante.
    @Test("un corpus vide ne fixe aucun état")
    func corpusVideNeFixeRien() async {
        let d = defaults("nouveautes-vide")
        await NouveautesNotifications.verifier(Faux(ecrits: [:], vides: ["iyov"]), defaults: d)

        #expect(d.stringArray(forKey: "unites-parues") == nil)
    }
}
