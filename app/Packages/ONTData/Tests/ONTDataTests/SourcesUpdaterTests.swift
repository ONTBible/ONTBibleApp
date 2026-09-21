import Foundation
import Testing

@testable import ONTData

/// **La mise à jour des sources, éprouvée génération par génération.**
///
/// Deux familles d'épreuves, et les deux doivent pouvoir rougir :
///
/// - le **décodage du vrai manifeste** — la fixture est le fichier émis par le
///   pipeline, copié tel quel (leçon A07 : « tester à partir d'un véritable
///   fichier ») ; les DTO étant écrits à la main, une dérive de forme ne
///   casserait aucune compilation, seule cette épreuve la verrait ;
/// - les **gardes de l'updater** — chacune des façons de refuser est éprouvée
///   positivement, parce qu'une garde qui ne trouve rien à comparer et passe
///   en silence est la famille de défauts que l'audit du 8 septembre a
///   nommée trois fois.
///
/// Le réseau est figé par `URLProtocol` : chaque scénario dit exactement ce
/// que « le site » répond, panne comprise. `.serialized` parce que la table
/// des réponses est partagée.
@Suite("SourcesUpdater", .serialized)
struct SourcesUpdaterTests {

    // MARK: - Le décodage du vrai fichier

    @Test("le manifeste émis par le pipeline se décode, absences comprises")
    func leManifesteReelSeDecode() throws {
        let manifeste = try JSONDecoder().decode(
            ONTSources.Manifeste.self, from: Self.fixture("manifeste.json"))
        #expect(manifeste.schema == 1)
        // La #286 pose l'estampille dans le manifeste du pipeline lui-même —
        // la date du dernier commit du vault, en forme stricte. Un fichier
        // émis sans elle est un pipeline d'avant, et cette ligne le dirait.
        #expect(
            manifeste.genere.flatMap(CorpusUpdater.Estampille.init) != nil,
            "le manifeste émis porte une estampille bien formée")
        #expect(manifeste.temoins.count == 5)
        let bereshit = try #require(manifeste.livres["bereshit"])
        let heWlc = try #require(bereshit.temoins["he-wlc"])
        #expect(heWlc.chemin == "sources/he-wlc/bereshit.json")
        #expect(heWlc.sha256.count == 64, "l'empreinte des sources est pleine, jamais tronquée")
        // Une absence déclarée est un état du contrat, pas un trou : le livre
        // existe, ses témoins sont vides, et `transmission` parle.
        let chazon = try #require(manifeste.livres["chazon-avraham"])
        #expect(chazon.temoins.isEmpty)
        #expect(chazon.transmission?.isEmpty == false)
    }

    // MARK: - La génération qui passe

    @Test("une génération complète bascule, l'estampille en dernier")
    func uneGenerationCompleteBascule() async throws {
        let (updater, dossier) = Self.updater(plancher: "2026-09-10T00:00:00Z")
        let manifeste = Self.manifeste(genere: "2026-09-11T17:23:15Z")
        ReseauFige.reponses = [
            "/sources/manifeste.json": (200, manifeste),
            "/sources/he-wlc/bereshit.json": (200, Self.fixture("he-wlc/bereshit.json")),
        ]

        // La fixture porte aussi six livres à `temoins` vides : leur absence
        // est déclarée, la complétude ne les attend pas.
        #expect(try await updater.synchroniser() == .installee(fichiers: 1))

        let actif = dossier.appendingPathComponent("actif")
        #expect(
            try Data(contentsOf: actif.appendingPathComponent("sources/he-wlc/bereshit.json"))
                == Self.fixture("he-wlc/bereshit.json"))
        // Le manifeste est posé dans ses octets reçus — pas re-sérialisé.
        #expect(
            try Data(contentsOf: actif.appendingPathComponent("sources/manifeste.json"))
                == manifeste)
        #expect(
            try String(
                contentsOf: actif.appendingPathComponent("estampille.txt"), encoding: .utf8)
                == "2026-09-11T17:23:15Z")
        // Aucun candidat orphelin : la bascule consomme le dossier.
        let restes = try FileManager.default.contentsOfDirectory(atPath: dossier.path)
            .filter { $0.hasPrefix("candidat") }
        #expect(restes.isEmpty)
    }

    @Test("rien de neuf ne coûte qu'une requête et ne touche à rien")
    func rienDeNeuf() async throws {
        let (updater, dossier) = Self.updater(plancher: "2026-09-10T00:00:00Z")
        ReseauFige.reponses = [
            "/sources/manifeste.json": (200, Self.manifeste(genere: "2026-09-11T17:23:15Z")),
            "/sources/he-wlc/bereshit.json": (200, Self.fixture("he-wlc/bereshit.json")),
        ]
        #expect(try await updater.synchroniser() == .installee(fichiers: 1))
        // La même publication, resservie : l'actif la porte déjà.
        #expect(try await updater.synchroniser() == .rienDeNeuf)
        _ = dossier
    }

    // MARK: - Les gardes, chacune prouvée capable de refuser

    @Test("un contenu faux de même taille jette le candidat entier")
    func unContenuFauxDeMemeTaille() async throws {
        var abime = Self.fixture("he-wlc/bereshit.json")
        abime[abime.count / 2] ^= 0xFF  // même longueur, autre empreinte
        let (updater, dossier) = Self.updater(plancher: "2026-09-10T00:00:00Z")
        ReseauFige.reponses = [
            "/sources/manifeste.json": (200, Self.manifeste(genere: "2026-09-11T17:23:15Z")),
            "/sources/he-wlc/bereshit.json": (200, abime),
        ]
        // Le candidat est jeté, et la cause est nommée — pas un « 0 ».
        let issue = try await updater.synchroniser()
        #expect(issue.fichiers == 0)
        guard case .generationIncomplete(let motif) = issue else {
            Issue.record("attendu generationIncomplete, obtenu \(issue)")
            return
        }
        // **Et le motif nomme le fichier et sa taille**, parce que c'est ce
        // qu'un lecteur du journal a besoin de savoir. Le premier jet rendait
        // « dataLengthExceedsMaximum » : exact, et muet sur ce qu'il faut
        // chercher.
        #expect(motif.contains("he-wlc/bereshit.json"))
        #expect(motif.contains("empreinte fausse"))
        #expect(motif.contains("\(abime.count)"), "la taille reçue doit être dite")
        #expect(!FileManager.default.fileExists(atPath: dossier.appendingPathComponent("actif").path))
    }

    @Test("une taille inattendue porte les deux nombres — l'écart dit la cause")
    func uneTailleInattenduePorteLesDeuxNombres() async throws {
        // Deux sens, deux causes distinctes — mesurées avec la session du
        // vault le 18 septembre 2026 :
        //
        //     annoncés ≫ reçus   troncature, mauvais fichier, transfert coupé
        //     annoncés ≪ reçus   génération construite avec `ONT_PRETTY` armé
        //
        // Sans les deux nombres au journal, les deux cas se lisent pareil —
        // et l'un se répare en retentant, l'autre en republiant.
        let entier = Self.fixture("he-wlc/bereshit.json")
        let tronque = entier.prefix(1204)
        let (updater, dossier) = Self.updater(plancher: "2026-09-10T00:00:00Z")
        ReseauFige.reponses = [
            "/sources/manifeste.json": (200, Self.manifeste(genere: "2026-09-11T17:23:15Z")),
            "/sources/he-wlc/bereshit.json": (200, Data(tronque)),
        ]
        let issue = try await updater.synchroniser()
        guard case .generationIncomplete(let motif) = issue else {
            Issue.record("attendu generationIncomplete, obtenu \(issue)")
            return
        }
        #expect(motif.contains("1204 octets reçus"))
        #expect(motif.contains("\(entier.count) annoncés"))
        #expect(!FileManager.default.fileExists(atPath: dossier.appendingPathComponent("actif").path))
    }

    @Test("un fichier manquant ne bascule rien — la génération est entière ou n'est pas")
    func unFichierManquantNeBasculeRien() async throws {
        let (updater, dossier) = Self.updater(plancher: "2026-09-10T00:00:00Z")
        ReseauFige.reponses = [
            "/sources/manifeste.json": (200, Self.manifeste(genere: "2026-09-11T17:23:15Z"))
            // bereshit.json : 404
        ]
        let issue = try await updater.synchroniser()
        #expect(issue.fichiers == 0)
        if case .generationIncomplete = issue {} else {
            Issue.record("attendu generationIncomplete, obtenu \(issue)")
        }
        #expect(!FileManager.default.fileExists(atPath: dossier.appendingPathComponent("actif").path))
    }

    @Test("un manifeste sans date est indécidable, donc refusé")
    func unManifesteSansDate() async throws {
        // Le champ est retiré, pas simplement absent : depuis la #286 le
        // pipeline l'émet toujours, et ce scénario est celui d'un publieur
        // fautif — ou d'un pipeline d'avant, ce qui revient au même.
        var objet = try JSONSerialization.jsonObject(with: Self.fixture("manifeste.json"))
            as! [String: Any]
        objet.removeValue(forKey: "genere")
        let (updater, dossier) = Self.updater(plancher: "2026-09-10T00:00:00Z")
        ReseauFige.reponses = [
            "/sources/manifeste.json": (200, try JSONSerialization.data(withJSONObject: objet)),
            "/sources/he-wlc/bereshit.json": (200, Self.fixture("he-wlc/bereshit.json")),
        ]
        // **Le cas qui était confondu avec le repos.** Un publieur qui
        // omet `genere` ne livrera jamais rien ; avant, il rendait la
        // même valeur que « rien n'a changé ».
        #expect(try await updater.synchroniser() == .dateIndecidable)
        #expect(!FileManager.default.fileExists(atPath: dossier.appendingPathComponent("actif").path))
    }

    @Test("une publication sous le plancher du bundle est refusée")
    func unePublicationSousLePlancher() async throws {
        let (updater, dossier) = Self.updater(plancher: "2026-09-12T00:00:00Z")
        ReseauFige.reponses = [
            "/sources/manifeste.json": (200, Self.manifeste(genere: "2026-09-11T17:23:15Z")),
            "/sources/he-wlc/bereshit.json": (200, Self.fixture("he-wlc/bereshit.json")),
        ]
        #expect(try await updater.synchroniser() == .rienDeNeuf)
        #expect(!FileManager.default.fileExists(atPath: dossier.appendingPathComponent("actif").path))
    }

    @Test("deux annonces sur le même chemin se percutent — refusées avant tout octet")
    func deuxAnnoncesSurLeMemeChemin() async throws {
        // Chaque garde compare un fichier à SON entrée ; celle-ci compare les
        // entrées ENTRE ELLES. Deux chemins identiques : un seul fichier
        // écrit, dernier gagnant, la preuve du premier annulée en silence.
        // Question posée par le vault le 16 septembre — même famille que les
        // `n` en double de bereshit-7.
        var objet = try JSONSerialization.jsonObject(with: Self.fixture("manifeste.json"))
            as! [String: Any]
        objet["genere"] = "2026-09-16T00:00:00Z"
        var livres = objet["livres"] as! [String: Any]
        // Un second livre annonce LE chemin de bereshit, sous une autre empreinte.
        livres["doublon"] = [
            "temoins": [
                "he-wlc": [
                    "chemin": "sources/he-wlc/bereshit.json",
                    "octets": 3, "sha256": String(repeating: "a", count: 64),
                ]
            ]
        ]
        objet["livres"] = livres
        let (updater, dossier) = Self.updater(plancher: "2026-09-10T00:00:00Z")
        ReseauFige.reponses = [
            "/sources/manifeste.json": (200, try JSONSerialization.data(withJSONObject: objet)),
            "/sources/he-wlc/bereshit.json": (200, Self.fixture("he-wlc/bereshit.json")),
        ]
        let resultat = try await updater.synchroniser()
        guard case .generationIncomplete(let motif) = resultat else {
            Issue.record("attendu generationIncomplete, reçu \(resultat)")
            return
        }
        #expect(motif.contains("deux fois"))
        #expect(!FileManager.default.fileExists(atPath: dossier.appendingPathComponent("actif").path))
    }

    @Test("un chemin réservé ou évadé est une percussion, pas un fichier")
    func unCheminReserveOuEvade() {
        func annonce(_ chemin: String) -> [ONTSources.Fichier] {
            let json = """
                {"chemin": "\(chemin)", "octets": 1, "sha256": "\(String(repeating: "a", count: 64))"}
                """
            return [try! JSONDecoder().decode(ONTSources.Fichier.self, from: Data(json.utf8))]
        }
        // Réservés : l'updater écrit lui-même ces deux noms — une annonce qui
        // les vise écraserait ou serait écrasée, selon l'ordre.
        #expect(SourcesUpdater.percussionDesChemins(annonce("sources/manifeste.json")) != nil)
        #expect(SourcesUpdater.percussionDesChemins(annonce("estampille.txt")) != nil)
        // Évadés : la bascule n'emporte que le candidat.
        #expect(SourcesUpdater.percussionDesChemins(annonce("sources/../../evade.json")) != nil)
        #expect(SourcesUpdater.percussionDesChemins(annonce("/tmp/absolu.json")) != nil)
        // Et le chemin légitime passe — la garde discrimine, elle ne bloque pas.
        #expect(SourcesUpdater.percussionDesChemins(annonce("sources/he-wlc/bereshit.json")) == nil)
    }

    @Test("un plancher illisible se nomme — il n'est pas le repos")
    func unPlancherIllisible() async throws {
        // Un bundle sans estampille lisible : `Estampille("pas-une-date")`
        // rend nil, exactement comme un `manifest.json` absent ou vide. La
        // #296 rangeait ce cas dans `rienDeNeuf` — le gel de TOUTES les
        // synchronisations à venir, rendu comme le repos. Cette épreuve tient
        // la distinction : défaut du build, pas absence de nouveauté.
        let (updater, dossier) = Self.updater(plancher: "pas-une-date")
        ReseauFige.reponses = [
            "/sources/manifeste.json": (200, Self.manifeste(genere: "2026-09-11T17:23:15Z")),
            "/sources/he-wlc/bereshit.json": (200, Self.fixture("he-wlc/bereshit.json")),
        ]
        let resultat = try await updater.synchroniser()
        #expect(resultat == .plancherIllisible)
        #expect(resultat.estUnRefus, "un gel programmé doit se lire comme un refus")
        #expect(!FileManager.default.fileExists(atPath: dossier.appendingPathComponent("actif").path))
    }

    @Test("une publication plus vieille que l'actif est refusée — le scénario A08")
    func unePublicationPlusVieilleQueLActif() async throws {
        // V1 = plancher, V3 = téléchargée et active, V2 = publiée ensuite.
        // Ne comparer qu'au bundle laisserait V2 recouvrir V3.
        let (updater, dossier) = Self.updater(plancher: "2026-09-01T00:00:00Z")
        ReseauFige.reponses = [
            "/sources/manifeste.json": (200, Self.manifeste(genere: "2026-09-11T17:23:15Z")),
            "/sources/he-wlc/bereshit.json": (200, Self.fixture("he-wlc/bereshit.json")),
        ]
        #expect(try await updater.synchroniser() == .installee(fichiers: 1))

        ReseauFige.reponses["/sources/manifeste.json"] =
            (200, Self.manifeste(genere: "2026-09-05T00:00:00Z"))
        #expect(try await updater.synchroniser() == .rienDeNeuf)
        #expect(
            try String(
                contentsOf: dossier.appendingPathComponent("actif/estampille.txt"),
                encoding: .utf8)
                == "2026-09-11T17:23:15Z", "l'actif garde sa génération")
    }

    @Test("un schéma inconnu remonte au lieu de se taire")
    func unSchemaInconnu() async throws {
        var objet = try JSONSerialization.jsonObject(with: Self.fixture("manifeste.json"))
            as! [String: Any]
        objet["schema"] = 2
        let (updater, _) = Self.updater(plancher: "2026-09-10T00:00:00Z")
        ReseauFige.reponses = [
            "/sources/manifeste.json": (200, try JSONSerialization.data(withJSONObject: objet))
        ]
        await #expect(throws: SourcesUpdater.Failure.self) {
            try await updater.synchroniser()
        }
    }

    // MARK: - La purge au lancement

    @Test("la purge écarte une génération sous le plancher, et elle seule")
    func laPurgeEcarteSousLePlancher() throws {
        let dossier = Self.dossierNeuf()
        let actif = dossier.appendingPathComponent("actif", isDirectory: true)

        // Sous le plancher : purgée.
        try Self.poserGeneration(actif, estampille: "2026-09-01T00:00:00Z")
        SourcesUpdater.purgerSiLeBundleEstPlusNeuf(
            dossier: dossier, plancher: CorpusUpdater.Estampille("2026-09-10T00:00:00Z"))
        #expect(!FileManager.default.fileExists(atPath: actif.path))

        // Sans estampille : une génération que personne n'a datée date
        // d'avant ce code — purgée aussi.
        try Self.poserGeneration(actif, estampille: nil)
        SourcesUpdater.purgerSiLeBundleEstPlusNeuf(
            dossier: dossier, plancher: CorpusUpdater.Estampille("2026-09-10T00:00:00Z"))
        #expect(!FileManager.default.fileExists(atPath: actif.path))

        // Au niveau ou au-dessus : gardée.
        try Self.poserGeneration(actif, estampille: "2026-09-10T00:00:00Z")
        SourcesUpdater.purgerSiLeBundleEstPlusNeuf(
            dossier: dossier, plancher: CorpusUpdater.Estampille("2026-09-10T00:00:00Z"))
        #expect(FileManager.default.fileExists(atPath: actif.path))

        // Sans plancher lisible, on ne purge pas : détruire sur une absence
        // d'information serait décider sur du silence.
        SourcesUpdater.purgerSiLeBundleEstPlusNeuf(dossier: dossier, plancher: nil)
        #expect(FileManager.default.fileExists(atPath: actif.path))
    }

    // MARK: - L'outillage

    private static func updater(plancher: String) -> (SourcesUpdater, URL) {
        let dossier = dossierNeuf()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReseauFige.self]
        let updater = SourcesUpdater(
            origine: URL(string: "https://fige.test/")!,
            dossier: dossier,
            session: URLSession(configuration: configuration),
            plancher: CorpusUpdater.Estampille(plancher)
        )
        return (updater, dossier)
    }

    private static func dossierNeuf() -> URL {
        let dossier = FileManager.default.temporaryDirectory
            .appendingPathComponent("sources-updater-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        return dossier
    }

    private static func poserGeneration(_ actif: URL, estampille: String?) throws {
        try FileManager.default.createDirectory(at: actif, withIntermediateDirectories: true)
        if let estampille {
            try estampille.write(
                to: actif.appendingPathComponent("estampille.txt"),
                atomically: true, encoding: .utf8)
        }
    }

    /// La fixture est le fichier **émis par le pipeline**, copié tel quel.
    private static func fixture(_ chemin: String) -> Data {
        let racine = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/sources")
        return try! Data(contentsOf: racine.appendingPathComponent(chemin))
    }

    /// Le manifeste publié d'un scénario : la fixture réelle, plus la date.
    ///
    /// Re-sérialisé, et c'est acceptable **ici seulement** : le manifeste
    /// n'est prouvé par aucune empreinte — ce sont les livres qui le sont, et
    /// leurs octets ne passent jamais par cette main.
    private static func manifeste(genere: String) -> Data {
        var objet = try! JSONSerialization.jsonObject(with: fixture("manifeste.json"))
            as! [String: Any]
        objet["genere"] = genere
        return try! JSONSerialization.data(withJSONObject: objet)
    }
}

/// Le site, figé : chaque chemin répond ce que le scénario a posé, 404 sinon.
final class ReseauFige: URLProtocol {
    nonisolated(unsafe) static var reponses: [String: (Int, Data)] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let chemin = request.url?.path ?? ""
        let (statut, octets) = Self.reponses[chemin] ?? (404, Data())
        client?.urlProtocol(
            self,
            didReceive: HTTPURLResponse(
                url: request.url!, statusCode: statut, httpVersion: nil, headerFields: nil)!,
            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: octets)
        client?.urlProtocolDidFinishLoading(self)
    }
}
