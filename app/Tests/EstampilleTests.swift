import Foundation
import Testing

@testable import ONTData

/// L'ordre entre deux corpus — le seul qui manquait, et par lequel une couche
/// entière serait partie invisible.
///
/// **Sans réseau, délibérément**, à rebours de `CorpusUpdaterTests` qui
/// interroge le vrai serveur. Ce qu'on éprouve ici n'est pas un accord entre
/// deux machines, c'est une décision : que fait l'app quand ce qu'on lui
/// propose est *plus vieux* que ce qu'elle porte ? On ne peut pas demander au
/// site de publier un corpus périmé sur commande, et attendre qu'il le fasse
/// par accident, c'est ne rien garder du tout.
@Suite("L'estampille du corpus")
struct EstampilleTests {

    // MARK: - Ce qu'est une estampille

    @Test("une date ISO en UTC, à la seconde, est acceptée")
    func formeCanonique() {
        #expect(CorpusUpdater.Estampille("2026-08-30T00:14:00Z") != nil)
    }

    /// **Le cas que la session du site a vu venir avant qu'il n'arrive.**
    ///
    /// La comparaison se fait sur des chaînes. Deux écritures du *même instant*
    /// s'ordonnent donc à l'envers dès que le fuseau diffère :
    ///
    ///     "2026-08-30T00:14:00Z" < "2026-08-30T02:14:00+02:00"
    ///
    /// L'app aurait gardé le plus vieux des deux corpus **en croyant garder le
    /// plus neuf** — le défaut du 30 août, sous une date bien formée, donc bien
    /// plus difficile à voir qu'un champ vide.
    ///
    /// La garde ne compare donc pas des dates : elle refuse tout ce qui ne
    /// s'écrit pas de la seule façon où comparer des chaînes dit la vérité.
    @Test(
        "tout ce qui n'est pas cette forme-là est refusé",
        arguments: [
            "",                          // le cas d'aujourd'hui
            "2026-08-30T02:14:00+02:00", // le même instant, ordonné à l'envers
            "2026-08-30T00:14:00.000Z",  // les millisecondes d'un `to_rfc3339`
            "2026-08-30T00:14Z",         // sans les secondes
            "2026-08-30 00:14:00Z",      // l'espace de SQL
            "2026-08-30T00:14:00",       // sans fuseau du tout
            "30/08/2026",                // une date de facture
            "AAAA-AA-AATAA:AA:AAZ",      // la bonne forme, sans un chiffre
        ]
    )
    func formesRefusees(_ brut: String) {
        #expect(CorpusUpdater.Estampille(brut) == nil, "« \(brut) » a été acceptée")
    }

    @Test("l'ordre des chaînes est l'ordre du temps")
    func ordre() throws {
        let vieux = try #require(CorpusUpdater.Estampille("2026-08-27T09:00:00Z"))
        let neuf = try #require(CorpusUpdater.Estampille("2026-08-30T00:14:00Z"))
        #expect(vieux < neuf)
        #expect(!(neuf < vieux))
    }

    // MARK: - Ce que la garde en fait

    private func updater(
        embarquee: String?,
        publie manifeste: String,
        fichier: Data? = nil
    ) -> CorpusUpdater {
        FauxReseau.reponses = ["manifeste.json": Data(manifeste.utf8)]
        FauxReseau.parDefaut = fichier
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FauxReseau.self]
        return CorpusUpdater(
            origine: URL(string: "https://exemple.invalide/corpus/")!,
            dossier: FileManager.default.temporaryDirectory
                .appendingPathComponent("estampille-\(UUID().uuidString)", isDirectory: true),
            session: URLSession(configuration: config),
            estampilleEmbarquee: embarquee.flatMap(CorpusUpdater.Estampille.init)
        )
    }

    /// Le cas mesuré sur simulateur le 30 août 2026 : le bundle portait 1913
    /// occurrences de `shem`, le disque 217, et l'app recréait le disque au
    /// lancement en retéléchargeant l'ancien.
    @Test("un corpus publié plus vieux que l'embarqué est refusé")
    func lePublieVieuxNeGagnePas() async throws {
        let m = self.updater(
            embarquee: "2026-08-30T00:14:00Z",
            publie: #"{"schema":2,"genere":"2026-08-27T09:00:00Z","fichiers":{"glossaire":{"chemin":"g.abc.json","empreinte":"abc","octets":2}},"livres":{}}"#,
            fichier: Data("{}".utf8))
        #expect(try await m.synchroniser() == 0)
    }

    /// Le `genere: ""` d'aujourd'hui. **Refuser**, parce qu'on ne peut pas
    /// prouver l'ordre — et que se tromper dans l'autre sens est exactement ce
    /// qui a produit le défaut. Un corpus figé se voit et se répare ; un corpus
    /// silencieusement remplacé par du plus vieux ne se voit pas.
    @Test("un manifeste sans date est refusé, pas accepté par défaut")
    func lIndatableEstRefuse() async throws {
        let m = self.updater(
            embarquee: "2026-08-30T00:14:00Z",
            publie: #"{"schema":2,"genere":"","fichiers":{"glossaire":{"chemin":"g.abc.json","empreinte":"abc","octets":2}},"livres":{}}"#,
            fichier: Data("{}".utf8))
        #expect(try await m.synchroniser() == 0)
    }

    /// Symétrique, et il faut y tenir : sans lui, un `return 0` inconditionnel
    /// passerait les deux tests ci-dessus en fanfare. Une garde qui refuse tout
    /// n'est pas une garde, c'est une panne.
    @Test("un corpus publié plus récent est bien accepté")
    func leNeufPasse() async throws {
        let m = self.updater(
            embarquee: "2026-08-27T09:00:00Z",
            publie: #"""
                {"schema":2,"genere":"2026-08-30T00:14:00Z",
                 "fichiers":{"glossaire":{"chemin":"g.abc.json","empreinte":"abc","octets":2}},
                 "livres":{}}
                """#,
            fichier: Data("{}".utf8))
        #expect(try await m.synchroniser() == 1)
    }

    // MARK: - La purge du corpus périmé

    /// Un dossier de corpus, avec ou sans estampille.
    private func dossierAvec(_ estampille: String?) -> URL {
        let d = FileManager.default.temporaryDirectory
            .appendingPathComponent("purge-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try? Data("{}".utf8).write(to: d.appendingPathComponent("corpus.json"))
        if let estampille {
            try? estampille.write(
                to: d.appendingPathComponent("estampille.txt"),
                atomically: true, encoding: .utf8)
        }
        return d
    }

    /// Un bundle de test qui déclare l'estampille qu'on lui donne.
    private func bundleEstampille(_ valeur: String) -> Foundation.Bundle {
        let d = FileManager.default.temporaryDirectory
            .appendingPathComponent("bundle-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try? Data(#"{"generatedAt":"\#(valeur)"}"#.utf8)
            .write(to: d.appendingPathComponent("manifest.json"))
        return Foundation.Bundle(url: d) ?? .main
    }

    /// **Le cas de l'appareil de l'auteur, le 30 août 2026.**
    ///
    /// La 1.0.5 embarquait la couche des Shemot et n'en affichait aucun : le
    /// disque portait le corpus de l'avant-veille, sans un seul nœud `shem`, et
    /// il répondait à la place du bundle.
    ///
    /// Refuser un corpus publié plus vieux empêche d'en *poser* un mauvais ; ça
    /// ne fait rien à celui qui est déjà là. La cause était arrêtée, l'effet
    /// restait.
    ///
    /// Une estampille **absente** vaut « plus vieux » : c'est le cas de toutes
    /// les installations existantes, et le traiter ainsi est exact — leur
    /// corpus date forcément d'avant la version qui écrit l'estampille.
    @Test("un disque sans estampille est écarté par un bundle daté")
    func leDisqueSansEstampilleEstEcarte() throws {
        let dossier = dossierAvec(nil)
        CorpusUpdater.purgerSiLeBundleEstPlusNeuf(
            dossier: dossier, bundle: bundleEstampille("2026-08-30T00:14:00Z"))
        #expect(!FileManager.default.fileExists(atPath: dossier.path))
    }

    @Test("un disque plus vieux que le bundle est écarté")
    func leDisqueVieuxEstEcarte() throws {
        let dossier = dossierAvec("2026-08-27T09:00:00Z")
        CorpusUpdater.purgerSiLeBundleEstPlusNeuf(
            dossier: dossier, bundle: bundleEstampille("2026-08-30T00:14:00Z"))
        #expect(!FileManager.default.fileExists(atPath: dossier.path))
    }

    /// **Et surtout : une purge qui purge toujours n'est pas une purge.**
    ///
    /// Sans ce cas, un `removeItem` inconditionnel passerait les deux épreuves
    /// ci-dessus en fanfare — et jetterait à chaque lancement un corpus
    /// téléchargé, donc vingt méga par ouverture d'app.
    @Test("un disque plus récent que le bundle est gardé")
    func leDisqueNeufEstGarde() throws {
        let dossier = dossierAvec("2026-08-30T00:14:00Z")
        CorpusUpdater.purgerSiLeBundleEstPlusNeuf(
            dossier: dossier, bundle: bundleEstampille("2026-08-27T09:00:00Z"))
        #expect(FileManager.default.fileExists(atPath: dossier.path))
    }

    /// Et un bundle sans estampille ne juge personne : il ne sait pas ce qu'il
    /// porte, donc il n'a rien à dire de ce que le disque porte.
    @Test("un bundle sans estampille ne purge rien")
    func leBundleMuetNePurgePas() throws {
        let dossier = dossierAvec("2026-08-27T09:00:00Z")
        CorpusUpdater.purgerSiLeBundleEstPlusNeuf(
            dossier: dossier, bundle: bundleEstampille(""))
        #expect(FileManager.default.fileExists(atPath: dossier.path))
    }

    /// Et l'app qui ne sait pas ce qu'elle porte ne prend rien non plus : une
    /// estampille embarquée illisible est le même aveu d'ignorance qu'une
    /// estampille publiée illisible.
    @Test("un bundle sans estampille refuse aussi")
    func lEmbarqueeIllisibleRefuse() async throws {
        let m = self.updater(
            embarquee: nil,
            publie: #"{"schema":2,"genere":"2026-08-30T00:14:00Z","fichiers":{"glossaire":{"chemin":"g.abc.json","empreinte":"abc","octets":2}},"livres":{}}"#,
            fichier: Data("{}".utf8))
        #expect(try await m.synchroniser() == 0)
    }
}

/// Un réseau de papier : il rend ce qu'on lui a posé, et rien d'autre.
final class FauxReseau: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var reponses: [String: Data] = [:]
    nonisolated(unsafe) static var parDefaut: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let nom = request.url?.lastPathComponent ?? ""
        let corps = Self.reponses[nom] ?? Self.parDefaut
        let code = corps == nil ? 404 : 200
        let reponse = HTTPURLResponse(
            url: request.url!, statusCode: code, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: reponse, cacheStoragePolicy: .notAllowed)
        if let corps { client?.urlProtocol(self, didLoad: corps) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
