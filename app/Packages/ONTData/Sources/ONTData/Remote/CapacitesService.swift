import Foundation
import ONTKit

/// Demander au serveur ce qu'il sait faire.
///
/// Sans session, délibérément : l'app doit pouvoir demander **avant** de savoir
/// si la connexion est possible. Exiger un jeton rendrait la route inutile
/// précisément là où elle sert.
public struct HTTPCapacitesService: CapacitesService {
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Ce que le serveur annonce.
    ///
    /// # Ce qui est une réponse, et ce qui n'en est pas
    ///
    /// Un **404** n'est pas une panne : c'est un serveur d'avant cette route.
    /// C'est même le cas normal pendant la fenêtre où l'app est en avance sur
    /// lui — ce qui arrive à chaque promotion, puisque le backend n'est déployé
    /// que par un push sur `main`.
    ///
    /// Une **coupure réseau** ne l'est pas non plus. Dans les deux cas on ne
    /// sait pas, et l'appelant transforme cette ignorance en `Offre.inconnue`,
    /// qui ne retire rien.
    ///
    /// Ce qu'on rend ici est donc soit une liste, soit une erreur qui dit
    /// « je n'ai pas pu demander » — jamais une liste vide de consolation. Une
    /// liste vide est une **réponse** : le serveur dit qu'il n'offre rien, et
    /// l'app doit la croire.
    public func offertes() async throws -> Set<Capacite> {
        var request = URLRequest(url: baseURL.appending(path: "capacites"))
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AccountError.offline
        }

        guard let http = response as? HTTPURLResponse else {
            throw AccountError.server(0)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AccountError.server(http.statusCode)
        }

        struct Corps: Decodable {
            // Facultatif pour la même raison que le reste : un serveur peut
            // rendre 200 avec un corps qu'on ne reconnaît pas.
            let capacites: [String]?
        }

        let corps = try APIClient.decoder.decode(Corps.self, from: data)
        // Une clé inconnue est ignorée, pas fatale : c'est un serveur **plus
        // récent** que l'app, ce qui arrive après une promotion vers `main`.
        // La négociation existe pour que les deux sens soient supportables.
        return Set((corps.capacites ?? []).compactMap(Capacite.init(rawValue:)))
    }
}
