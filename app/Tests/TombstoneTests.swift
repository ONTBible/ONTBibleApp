import Foundation
import ONTData
import ONTKit
import Testing

/// Les suppressions voyagent.
///
/// Le défaut qu'elles couvrent était silencieux et coûteux : `remove` détruisait
/// la ligne, le transport posait `deleted = false` en dur, et une pierre tombale
/// reçue était écartée à la lecture. Un surlignage supprimé sur un appareil
/// réapparaissait donc au prochain échange — depuis le serveur, ou depuis un
/// autre appareil qui ne savait pas.
@Suite("Pierres tombales")
struct TombstoneTests {
    private func store() -> (FileReaderStore, URL) {
        let dossier = URL.temporaryDirectory.appending(path: UUID().uuidString)
        return (FileReaderStore(directory: dossier, name: "lecteur.json"), dossier)
    }

    private func surlignage(verse: Int = 19) -> Highlight {
        Highlight(
            bookId: "bereshit",
            chapterId: "bereshit-18",
            verse: verse,
            color: .gold,
            note: "tsedaqah umishpat"
        )
    }

    @Test("supprimer marque, ne détruit pas")
    func removeMarksInsteadOfDeleting() {
        let (magasin, _) = store()
        let h = surlignage()
        magasin.save(h)
        magasin.remove(h)

        #expect(magasin.all().isEmpty, "il ne doit plus s'afficher")
        #expect(magasin.allForSync().count == 1, "mais il doit encore partir au serveur")
        #expect(magasin.allForSync().first?.deleted == true)
    }

    @Test("la pierre tombale ne garde pas la note")
    func tombstoneDropsTheNote() {
        // Une suppression qui conserverait le texte de la note laisserait sur le
        // serveur ce que le lecteur vient d'effacer — article 9 du RGPD.
        let (magasin, _) = store()
        let h = surlignage()
        magasin.save(h)
        magasin.remove(h)

        #expect(magasin.allForSync().first?.note == nil)
    }

    @Test("un verset supprimé n'est plus rendu par la recherche de verset")
    func deletedIsNotFoundByVerse() {
        let (magasin, _) = store()
        let h = surlignage()
        magasin.save(h)
        magasin.remove(h)

        #expect(magasin.highlight(chapterId: "bereshit-18", verse: 19) == nil)
    }

    @Test("la pierre tombale survit au rechargement")
    func tombstoneSurvivesReload() {
        // C'est le point : si elle ne survivait pas, l'app relancée renverrait
        // le surlignage au serveur comme s'il n'avait jamais été supprimé.
        let dossier = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let premier = FileReaderStore(directory: dossier, name: "lecteur.json")
        let h = surlignage()
        premier.save(h)
        premier.remove(h)

        let second = FileReaderStore(directory: dossier, name: "lecteur.json")
        #expect(second.all().isEmpty)
        #expect(second.allForSync().count == 1)
        #expect(second.allForSync().first?.deleted == true)
    }

    @Test("resurligner un verset supprimé le fait revivre")
    func resavingRevives() {
        let (magasin, _) = store()
        let h = surlignage()
        magasin.save(h)
        magasin.remove(h)

        var neuf = surlignage()
        neuf.updatedAt = Date()
        magasin.save(neuf)

        #expect(magasin.all().count == 1)
        #expect(magasin.highlight(chapterId: "bereshit-18", verse: 19) != nil)
    }

    @Test("une pierre tombale trop vieille est purgée au chargement")
    func oldTombstonesArePurged() {
        // Sans purge, le fichier gagnerait une ligne par suppression, pour
        // toujours. Quatre-vingt-dix jours passent largement le temps qu'un
        // appareil peut rester hors ligne.
        let dossier = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let premier = FileReaderStore(directory: dossier, name: "lecteur.json")
        var vieux = surlignage()
        vieux.deleted = true
        vieux.updatedAt = Date().addingTimeInterval(-91 * 24 * 60 * 60)
        premier.save(vieux)

        let second = FileReaderStore(directory: dossier, name: "lecteur.json")
        #expect(second.allForSync().isEmpty)
    }

    @Test("un surlignage écrit avant ce champ se relit comme vivant")
    func decodesLegacyWithoutTheField() throws {
        // Le fichier d'un lecteur qui a la version précédente ne porte pas
        // `deleted`. Sans tolérance au décodage, il perdrait tout.
        let ancien = """
        {"id":"\(UUID().uuidString)","bookId":"bereshit","chapterId":"bereshit-18",
         "verse":19,"color":"gold","updatedAt":0}
        """
        let lu = try JSONDecoder().decode(Highlight.self, from: Data(ancien.utf8))
        #expect(lu.deleted == false)
    }
}
