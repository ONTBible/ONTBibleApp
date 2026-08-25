import Foundation
import ONTKit
import Testing

@testable import ONTData

/// Ce que l'app fait d'un serveur qui ne connaît pas encore la route.
///
/// # La distinction qui décide de tout
///
/// Un échec doit **lever**, jamais rendre un ensemble vide. Les deux se
/// ressemblent dans le code appelant et n'ont rien à voir :
///
/// - **lever** → l'offre reste inconnue → tous les boutons restent ;
/// - **ensemble vide** → l'offre est connue et vide → **tous les boutons
///   disparaissent**.
///
/// Le second est le pire résultat possible : le lecteur ne pourrait plus se
/// connecter du tout, parce que son réseau a hoqueté ou parce que le serveur
/// est d'une version d'avant. On aurait remplacé « ça échoue quand on essaie »
/// par « on ne peut plus essayer ».
@Suite("Demander ce que le serveur sait faire")
struct CapacitesServiceTests {

    /// Un service branché sur un serveur feint **qui n'appartient qu'à cette
    /// épreuve**.
    ///
    /// L'hôte est unique par appel, et la doublure choisit sa réponse d'après
    /// lui. La première version employait une variable statique partagée :
    /// Swift Testing exécutant en parallèle, chaque épreuve mesurait la réponse
    /// d'une autre — et rendait un résultat parfaitement vraisemblable sur une
    /// mesure qui n'avait pas eu lieu.
    private func service(_ repondre: @escaping @Sendable () -> (Int, Data)) -> HTTPCapacitesService {
        let hote = "\(UUID().uuidString.lowercased()).invalide"
        Faux.inscrire(hote, repondre)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Faux.self]
        return HTTPCapacitesService(
            baseURL: URL(string: "https://\(hote)")!,
            session: URLSession(configuration: config)
        )
    }

    @Test("une liste se lit")
    func listeSeLit() async throws {
        let sujet = service {
            (200, Data(#"{"capacites":["auth.google","sync"]}"#.utf8))
        }
        let offertes = try await sujet.offertes()
        #expect(offertes == [.authGoogle, .synchronisation])
    }

    /// **Le cas réel du jour** : le serveur en ligne rend 404 sur cette route,
    /// parce que le backend n'est déployé que par un push sur `main`.
    @Test("un serveur d'avant la route lève, et ne rend pas un ensemble vide")
    func serveurAncienLeve() async {
        let sujet = service { (404, Data()) }
        await #expect(throws: (any Error).self) { try await sujet.offertes() }
    }

    /// Une coupure réseau ne doit pas davantage se confondre avec « rien ».
    @Test("une panne réseau lève")
    func panneLeve() async {
        let sujet = service { (500, Data()) }
        await #expect(throws: (any Error).self) { try await sujet.offertes() }
    }

    /// Une **liste vide** est une réponse, elle : le serveur dit qu'il n'offre
    /// rien, et l'app doit la croire. C'est le seul cas où l'offre est connue
    /// et vide.
    @Test("une liste vide est une réponse, pas un échec")
    func listeVideEstUneReponse() async throws {
        let sujet = service { (200, Data(#"{"capacites":[]}"#.utf8)) }
        let offertes = try await sujet.offertes()
        #expect(offertes.isEmpty)
    }

    /// Un serveur **plus récent** que l'app : la clé inconnue est ignorée, le
    /// reste passe. C'est le cas après une promotion vers `main`.
    @Test("une capacité inconnue est ignorée, pas fatale")
    func capaciteInconnueIgnoree() async throws {
        let sujet = service {
            (200, Data(#"{"capacites":["sync","venue.du.futur"]}"#.utf8))
        }
        let offertes = try await sujet.offertes()
        #expect(offertes == [.synchronisation])
    }
}

/// Un `URLProtocol` qui répond ce qu'on lui dit, sans réseau.
///
/// Les réponses sont rangées **par hôte** et non dans une variable unique :
/// c'est ce qui permet à des épreuves parallèles de ne pas se voler leurs
/// mesures.
private final class Faux: URLProtocol, @unchecked Sendable {
    private static let verrou = NSLock()
    nonisolated(unsafe) private static var reponses: [String: @Sendable () -> (Int, Data)] = [:]

    static func inscrire(_ hote: String, _ repondre: @escaping @Sendable () -> (Int, Data)) {
        verrou.lock()
        defer { verrou.unlock() }
        reponses[hote] = repondre
    }

    private static func reponse(pour hote: String) -> (Int, Data) {
        verrou.lock()
        defer { verrou.unlock() }
        guard let repondre = reponses[hote] else {
            fatalError("aucune réponse inscrite pour \(hote) — l'épreuve mesurerait autre chose")
        }
        return repondre()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let (code, corps) = Self.reponse(pour: url.host() ?? "")
        let reponse = HTTPURLResponse(
            url: url,
            statusCode: code,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: reponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: corps)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
