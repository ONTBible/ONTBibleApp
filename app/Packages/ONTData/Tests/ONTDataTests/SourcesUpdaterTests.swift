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
        #expect(try await updater.synchroniser() == 1)

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
        #expect(try await updater.synchroniser() == 1)
        // La même publication, resservie : l'actif la porte déjà.
        #expect(try await updater.synchroniser() == 0)
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
        #expect(try await updater.synchroniser() == 0)
        #expect(!FileManager.default.fileExists(atPath: dossier.appendingPathComponent("actif").path))
    }

    @Test("un fichier manquant ne bascule rien — la génération est entière ou n'est pas")
    func unFichierManquantNeBasculeRien() async throws {
        let (updater, dossier) = Self.updater(plancher: "2026-09-10T00:00:00Z")
        ReseauFige.reponses = [
            "/sources/manifeste.json": (200, Self.manifeste(genere: "2026-09-11T17:23:15Z"))
            // bereshit.json : 404
        ]
        #expect(try await updater.synchroniser() == 0)
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
        #expect(try await updater.synchroniser() == 0)
        #expect(!FileManager.default.fileExists(atPath: dossier.appendingPathComponent("actif").path))
    }

    @Test("une publication sous le plancher du bundle est refusée")
    func unePublicationSousLePlancher() async throws {
        let (updater, dossier) = Self.updater(plancher: "2026-09-12T00:00:00Z")
        ReseauFige.reponses = [
            "/sources/manifeste.json": (200, Self.manifeste(genere: "2026-09-11T17:23:15Z")),
            "/sources/he-wlc/bereshit.json": (200, Self.fixture("he-wlc/bereshit.json")),
        ]
        #expect(try await updater.synchroniser() == 0)
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
        #expect(try await updater.synchroniser() == 1)

        ReseauFige.reponses["/sources/manifeste.json"] =
            (200, Self.manifeste(genere: "2026-09-05T00:00:00Z"))
        #expect(try await updater.synchroniser() == 0)
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
