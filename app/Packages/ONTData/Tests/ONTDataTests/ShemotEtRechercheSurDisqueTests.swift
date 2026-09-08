import Foundation
import ONTKit
import Testing

@testable import ONTData

/// Les fiches des noms propres et l'index de recherche, lus du corpus actif.
///
/// ## Le défaut que ces épreuves gardent
///
/// `shemot.json` et `search.json` n'étaient pas distribués. Les fiches
/// restaient donc celles de l'installation pendant que le texte se corrigeait
/// en minutes — et un Shem apparu depuis n'avait **aucune** fiche. Le cas était
/// réel : `gavriel`, `moshe`, `sinai` et `eliyahu` sont nommés dans le corpus.
///
/// Relevé par un audit externe le 8 septembre 2026 — A10.
struct ShemotEtRechercheSurDisqueTests {
    private func dossierAvec(_ fichier: String, _ contenu: String) -> URL {
        let d = FileManager.default.temporaryDirectory
            .appendingPathComponent("a10-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try? Data(contenu.utf8).write(to: d.appendingPathComponent(fichier))
        return d
    }

    /// Un socle qui répond toujours la même chose — ce que porterait le bundle.
    private struct SocleShemot: ShemotRepository {
        func entries() throws -> [ShemEntry] { [] }
    }

    private struct SocleRecherche: SearchIndex {
        func records() -> [SearchRecord] { [] }
    }

    @Test("les fiches du disque l'emportent sur celles du bundle")
    func shemotDuDisque() throws {
        let d = dossierAvec(
            "shemot.json",
            #"{"schema":1,"entries":[{"lemma":"gavriel","title":"Gavriel","definition":[]}]}"#)
        let depot = DiskShemotRepository(dossier: d, socle: SocleShemot())
        let fiches = try depot.entries()
        #expect(fiches.count == 1)
        #expect(fiches.first?.lemma == "gavriel")
    }

    /// **Le piège des deux noms.**
    ///
    /// Le nœud du manifeste s'appelle `recherche`, écrit en français comme le
    /// reste du corpus ; le fichier posé sur le disque s'appelle `search.json`,
    /// nom que le pipeline lui donne depuis le début.
    ///
    /// Chercher `recherche.json` sur le disque ne trouverait rien, et **le
    /// bundle répondrait à sa place** — l'index resterait figé, exactement le
    /// défaut qu'on corrige, sans qu'aucune erreur ne le dise.
    @Test("l'index se lit dans search.json, pas dans recherche.json")
    func rechercheDuDisque() {
        let d = dossierAvec(
            "search.json",
            #"{"schema":1,"records":[{"b":"bereshit","c":"bereshit-1","v":1,"k":"verse","t":"au commencement","g":"","h":"","l":[],"x":"Au commencement"}]}"#)
        #expect(DiskSearchIndex(dossier: d, socle: SocleRecherche()).records().count == 1)

        // Le même contenu sous le nom du nœud : rien ne doit être trouvé.
        let faux = dossierAvec(
            "recherche.json",
            #"{"schema":1,"records":[{"b":"bereshit","c":"bereshit-1","v":1,"k":"verse","t":"au commencement","g":"","h":"","l":[],"x":"Au commencement"}]}"#)
        #expect(DiskSearchIndex(dossier: faux, socle: SocleRecherche()).records().isEmpty)
    }

    /// Sans fichier sur le disque, le bundle répond — c'est l'état d'une
    /// installation neuve, et de toute installation tant que le site n'a pas
    /// publié.
    @Test("sans fichier, le socle répond")
    func repliSurLeSocle() throws {
        let vide = FileManager.default.temporaryDirectory
            .appendingPathComponent("a10-vide-\(UUID().uuidString)", isDirectory: true)
        #expect(try DiskShemotRepository(dossier: vide, socle: SocleShemot()).entries().isEmpty)
        #expect(DiskSearchIndex(dossier: vide, socle: SocleRecherche()).records().isEmpty)
    }
}
