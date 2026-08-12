import Foundation
import ONTKit

/// Le client HTTP du backend.
///
/// Deux responsabilités, et deux seulement : parler au réseau, et **renouveler
/// le jeton d'accès quand il a expiré**, de façon transparente pour l'appelant.
/// Aucune vue, aucun modèle ne doit avoir à penser à l'expiration.
///
/// Les formats diffèrent des deux côtés — le backend est en Rust, il parle
/// `snake_case` et compte le temps en millisecondes depuis l'epoch. La
/// conversion vit ici, dans des DTO, et jamais dans le domaine.
public actor APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let store: any SessionStore
    private let auth: any AuthService

    /// Empêche deux requêtes simultanées de consommer le même jeton de
    /// rafraîchissement — il ne sert qu'une fois, et la seconde échouerait.
    private var refreshTask: Task<Session, Error>?

    public init(
        baseURL: URL,
        store: any SessionStore,
        auth: any AuthService,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.store = store
        self.auth = auth
        self.session = session
    }

    // MARK: - Requêtes authentifiées

    func send<Response: Decodable>(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (some Encodable)? = Optional<Never>.none,
        as type: Response.Type
    ) async throws -> Response {
        let data = try await sendRaw(method, path, query: query, body: body)
        return try Self.decoder.decode(Response.self, from: data)
    }

    func send(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (some Encodable)? = Optional<Never>.none
    ) async throws {
        _ = try await sendRaw(method, path, query: query, body: body)
    }

    private func sendRaw(
        _ method: String,
        _ path: String,
        query: [URLQueryItem],
        body: (some Encodable)?
    ) async throws -> Data {
        let token = try await validAccessToken()

        do {
            return try await perform(method, path, query: query, body: body, token: token)
        } catch AccountError.unauthorized {
            // Le serveur a refusé un jeton que nous croyions valable : on
            // renouvelle une fois, puis on réessaie. Si ça échoue encore,
            // c'est une vraie déconnexion.
            let renewed = try await renew()
            return try await perform(
                method, path, query: query, body: body, token: renewed.accessToken
            )
        }
    }

    private func perform(
        _ method: String,
        _ path: String,
        query: [URLQueryItem],
        body: (some Encodable)?,
        token: String?
    ) async throws -> Data {
        var components = URLComponents(
            url: baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw AccountError.server(0) }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AccountError.offline
        }

        guard let http = response as? HTTPURLResponse else { throw AccountError.server(0) }
        switch http.statusCode {
        case 200..<300: return data
        case 401: throw AccountError.unauthorized
        default: throw AccountError.server(http.statusCode)
        }
    }

    // MARK: - Jetons

    /// Le jeton d'accès courant, renouvelé s'il a expiré.
    private func validAccessToken() async throws -> String? {
        guard let current = store.session else { return nil }
        guard current.isExpired() else { return current.accessToken }
        return try await renew().accessToken
    }

    /// Renouvelle la session, une seule fois même si plusieurs requêtes le
    /// demandent en même temps.
    private func renew() async throws -> Session {
        if let refreshTask { return try await refreshTask.value }

        guard let current = store.session else { throw AccountError.unauthorized }

        let task = Task { [auth, store] () throws -> Session in
            do {
                let renewed = try await auth.refresh(current.refreshToken)
                store.session = renewed
                return renewed
            } catch {
                // Un rafraîchissement refusé signifie que la session est
                // morte : on la jette plutôt que de boucler.
                store.session = nil
                throw AccountError.unauthorized
            }
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    // MARK: - Codage

    /// Le backend parle `snake_case` — la conversion est déclarée une fois.
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

// `Never: Encodable` était déclaré ici pour permettre `Optional<Never>`
// comme corps de requête absent. La bibliothèque standard le fournit depuis
// Swift 6 — la conformité rétroactive faisait doublon, et un doublon de
// conformité est le genre de chose qui devient une erreur, pas un
// avertissement, à la version suivante.
