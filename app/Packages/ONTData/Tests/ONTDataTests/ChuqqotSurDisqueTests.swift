import Foundation
import ONTKit
import Testing

@testable import ONTData

/// Les chuqqot, lues du corpus actif.
///
/// ## Le défaut que ces épreuves gardent
///
/// Le pipeline émettait `dist/chuqqot.json` et **personne ne l'ouvrait**.
/// L'onglet affichait en dur « Ils ne sont pas encore écrits » pendant que sept
/// chuqqot vivaient dans le vault. Le contrôle des émissions l'a nommé le
/// 11 septembre 2026 ; ce fichier-ci garde la fermeture.
///
/// ## Ce que chaque épreuve mesure, et comment on l'a vue rougir
///
/// Une épreuve qu'on n'a pas vue échouer ne mesure rien. Chacune ci-dessous a
/// été retournée contre le code d'avant — le détail est en tête de chaque
/// `@Test`, avec la mutation exacte et ce qu'elle a fait dire au rapport.
struct ChuqqotSurDisqueTests {
    private func dossierAvec(_ fichier: String, _ contenu: String) -> URL {
        let d = FileManager.default.temporaryDirectory
            .appendingPathComponent("chuqqot-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try? Data(contenu.utf8).write(to: d.appendingPathComponent(fichier))
        return d
    }

    /// Un bundle qui ne porte **aucun** corpus.
    ///
    /// `Bundle(for: NSString.self)` est celui de Foundation : il existe, il se
    /// charge, et il n'a pas de dossier `data/`. C'est le même artifice que
    /// `Composition` emploie sous `-corpus-absent` — on éprouve le repli sans
    /// fabriquer un faux bundle, donc sans ressource à maintenir.
    private var bundleSansCorpus: Foundation.Bundle { Foundation.Bundle(for: NSString.self) }

    /// **L'épreuve du défaut lui-même.** Le fichier est là, on le lit.
    ///
    /// Vue rougir en rendant `[]` depuis `chuqqot()` — ce que faisait l'app
    /// avant ce chantier, puisqu'elle ne lisait rien : « Expectation failed:
    /// (lues.count → 0) == 1 ».
    @Test("les chuqqot du disque sont lues")
    func lecture() {
        let d = dossierAvec(
            "chuqqot.json",
            #"""
            {"schema":1,"entries":[
              {"id":"yhwh-ha-maqom","title":"YHWH ha-Maqom","rank":4294967295,
               "blocks":[{"t":"para","nodes":[{"t":"text","v":"Le lieu."}]}]}
            ]}
            """#)
        let lues = DiskChuqqotRepository(dossier: d, bundle: bundleSansCorpus).chuqqot()

        #expect(lues.count == 1)
        #expect(lues.first?.id == "yhwh-ha-maqom")
    }

    /// **La traduction renomme, et c'est là qu'elle peut se tromper.**
    ///
    /// Le fichier dit `title`, `rank`, `blocks` ; le domaine dit `titre`,
    /// `rang`, `blocs`. Trois champs à apparier à la main dans
    /// `SchemaMapping`, donc trois occasions d'en croiser deux — un `titre:
    /// dto.id` compile parfaitement, et l'app afficherait un slug.
    ///
    /// Vue rougir en écrivant `titre: dto.id` dans `Chuqqah.init(_:)` :
    /// « (lue?.titre → "yhwh-ha-maqom") == "YHWH ha-Maqom" ».
    @Test("les champs du fichier deviennent ceux du domaine")
    func traduction() {
        let d = dossierAvec(
            "chuqqot.json",
            #"""
            {"schema":1,"entries":[
              {"id":"yhwh-ha-maqom","title":"YHWH ha-Maqom","rank":7,
               "blocks":[
                 {"t":"heading","level":2,"nodes":[{"t":"text","v":"Le lieu"}]},
                 {"t":"para","nodes":[{"t":"text","v":"Il est le lieu."}]}
               ]}
            ]}
            """#)
        let lue = DiskChuqqotRepository(dossier: d, bundle: bundleSansCorpus).chuqqot().first

        #expect(lue?.id == "yhwh-ha-maqom")
        #expect(lue?.titre == "YHWH ha-Maqom")
        #expect(lue?.rang == 7)
        #expect(lue?.blocs.count == 2)
        // Le corps arrive en **blocs de corpus** et non en markdown : c'est ce
        // qui met les intraduisibles en or et les rend touchables sans une
        // ligne de code dans l'onglet.
        if case .heading(let niveau, _) = lue?.blocs.first {
            #expect(niveau == 2)
        } else {
            Issue.record("le premier bloc devrait être un titre de niveau 2")
        }
    }

    /// **L'ordre de lecture est une propriété du domaine.**
    ///
    /// Le pipeline trie déjà ce qu'il émet, et le dépôt pourrait s'en remettre
    /// à l'ordre reçu. Il ne le fait pas : un corpus d'aperçu monté par le mode
    /// développeur du Mac, un fichier écrit à la main, une fusion future — rien
    /// de tout cela ne passe par le tri du pipeline, et tout passe par ici.
    ///
    /// `chuqqot-0-intro` porte le rang 0 et ouvre la série ; les autres n'ont
    /// pas de rang déclaré et portent `u32::MAX`. Le fichier les donne ici dans
    /// l'ordre inverse, exprès.
    ///
    /// Vue rougir en retirant le `.sorted` de `DiskChuqqotRepository` :
    /// « (ordre → ["yhwh-ha-maqom", "chuqqot-0-intro"]) == ["chuqqot-0-intro",
    /// "yhwh-ha-maqom"] ».
    @Test("l'introduction passe devant, quel que soit l'ordre du fichier")
    func ordreDeLecture() {
        let d = dossierAvec(
            "chuqqot.json",
            #"""
            {"schema":1,"entries":[
              {"id":"yhwh-ha-maqom","title":"YHWH ha-Maqom","rank":4294967295,"blocks":[]},
              {"id":"chuqqot-0-intro","title":"L'introduction","rank":0,"blocks":[]}
            ]}
            """#)
        let ordre = DiskChuqqotRepository(dossier: d, bundle: bundleSansCorpus)
            .chuqqot().map(\.id)

        #expect(ordre == ["chuqqot-0-intro", "yhwh-ha-maqom"])
    }

    /// **Le départage par identifiant, sans quoi l'ordre n'en est pas un.**
    ///
    /// Deux chuqqot sans rang déclaré portent toutes deux `u32::MAX`. Trier sur
    /// le seul rang laisserait leur ordre relatif dépendre de la stabilité du
    /// tri, c'est-à-dire de rien de garanti — et deux lancements pourraient
    /// présenter la liste autrement.
    ///
    /// Vue rougir en triant sur `$0.rang < $1.rang` seul : le tri de Swift
    /// n'étant pas stable, l'ordre rendu était celui du fichier.
    @Test("à rang égal, l'identifiant départage")
    func departage() {
        let d = dossierAvec(
            "chuqqot.json",
            #"""
            {"schema":1,"entries":[
              {"id":"zayin","title":"Z","rank":4294967295,"blocks":[]},
              {"id":"alef","title":"A","rank":4294967295,"blocks":[]}
            ]}
            """#)
        let ordre = DiskChuqqotRepository(dossier: d, bundle: bundleSansCorpus)
            .chuqqot().map(\.id)

        #expect(ordre == ["alef", "zayin"])
    }

    /// **Rien nulle part n'est une panne pour personne.**
    ///
    /// Ni sur le disque, ni dans le bundle : le dépôt rend une liste vide, sans
    /// lever. C'est l'état d'aujourd'hui — les sept chuqqot écrites sont en
    /// brouillon et la garde du pipeline les retient —, donc l'état le plus
    /// fréquent de cet écran.
    ///
    /// Vue rougir en faisant lever `chuqqot()` sur l'absence : l'épreuve
    /// échouait à la construction du dépôt, avant même l'assertion.
    @Test("sans fichier, la liste est vide et rien ne lève")
    func absenceTotale() {
        let vide = FileManager.default.temporaryDirectory
            .appendingPathComponent("chuqqot-vide-\(UUID().uuidString)", isDirectory: true)

        #expect(DiskChuqqotRepository(dossier: vide, bundle: bundleSansCorpus).chuqqot().isEmpty)
    }

    /// **Un fichier illisible ne doit pas empêcher de lire.**
    ///
    /// Un téléchargement interrompu laisse des octets tronqués sur le disque.
    /// Le décodage échoue, et le repli répond — comme partout ailleurs dans ce
    /// fichier. Sans ça, une coupure de réseau rendrait l'onglet inutilisable
    /// jusqu'à ce que quelqu'un pense à vider le dossier du corpus.
    ///
    /// Vue rougir en remplaçant `try?` par `try!` dans `lire(_:)` : l'épreuve
    /// tombait sur un plantage, pas sur une assertion — ce qui est exactement
    /// ce que le lecteur aurait vu.
    @Test("un fichier tronqué ne fait pas tomber l'onglet")
    func fichierIllisible() {
        let d = dossierAvec("chuqqot.json", #"{"schema":1,"entri"#)

        #expect(DiskChuqqotRepository(dossier: d, bundle: bundleSansCorpus).chuqqot().isEmpty)
    }

    /// **Le cache s'oublie, sinon la validation attend le prochain lancement.**
    ///
    /// C'est le trou que `DiskPrononciationRepository` porte encore : construit
    /// en ligne dans `Composition`, personne ne tient sa référence, donc
    /// personne ne peut lui dire d'oublier. Une chuqqah validée est précisément
    /// l'événement qu'on veut voir arriver sans relancer l'app.
    ///
    /// Vue rougir en vidant le corps d'`oublier()` : « (apres.count → 0) == 1 ».
    @Test("après un oubli, le dépôt relit le disque")
    func oubli() throws {
        let d = FileManager.default.temporaryDirectory
            .appendingPathComponent("chuqqot-oubli-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)

        let depot = DiskChuqqotRepository(dossier: d, bundle: bundleSansCorpus)
        #expect(depot.chuqqot().isEmpty)

        // Le corpus arrive après coup, comme le fait `CorpusUpdater`.
        try Data(
            #"{"schema":1,"entries":[{"id":"a","title":"A","rank":0,"blocks":[]}]}"#.utf8
        ).write(to: d.appendingPathComponent("chuqqot.json"))

        // Sans l'oubli, le cache tient le vide d'avant — et rien ne lui dit
        // qu'il a vieilli.
        #expect(depot.chuqqot().isEmpty)

        depot.oublier()
        #expect(depot.chuqqot().count == 1)
    }
}
