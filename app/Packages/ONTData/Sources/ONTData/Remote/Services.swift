import Foundation
import ONTKit

// MARK: - DTO

/// Ce que le backend rend à la connexion.
private struct SessionDTO: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let created: Bool
}

/// Un surlignage tel qu'il voyage.
///
/// Distinct du `Highlight` du domaine, et c'est délibéré : le backend compte
/// le temps en millisecondes depuis l'epoch et porte une pierre tombale
/// `deleted` que le stockage local n'a pas. Mélanger les deux ferait remonter
/// des contraintes de transport jusque dans le domaine.
private struct HighlightDTO: Codable {
    let id: String
    let bookId: String
    let chapterId: String
    let verse: Int
    let color: String
    let note: String?
    let updatedAt: Int64
    let deleted: Bool

    init(_ highlight: Highlight) {
        id = highlight.id.uuidString
        bookId = highlight.bookId
        chapterId = highlight.chapterId
        verse = highlight.verse
        color = highlight.color.rawValue
        note = highlight.note
        updatedAt = Int64(highlight.updatedAt.timeIntervalSince1970 * 1000)
        // L'état réel, et non `false` en dur — c'est ce qui faisait qu'aucune
        // suppression ne quittait jamais l'appareil.
        deleted = highlight.deleted
    }

    /// Rend `nil` si l'objet est inutilisable — une couleur inconnue vient
    /// d'une version plus récente de l'app, et on préfère ignorer la ligne
    /// plutôt que de faire échouer toute la synchronisation.
    ///
    /// Une pierre tombale est en revanche **rendue**, pas écartée.
    ///
    /// Elle l'était : `guard !deleted` renvoyait `nil`, donc une suppression
    /// faite sur un autre appareil n'arrivait jamais jusqu'à la fusion. Le
    /// surlignage restait, et le prochain envoi le renvoyait au serveur — qui
    /// le ressuscitait pour tout le monde.
    ///
    /// La couleur d'une pierre tombale n'a plus d'importance ; si elle est
    /// inconnue, on retombe sur une valeur quelconque plutôt que de perdre la
    /// suppression.
    var domain: Highlight? {
        guard let color = HighlightColor(rawValue: color) ?? (deleted ? HighlightColor.allCases.first : nil)
        else { return nil }
        return Highlight(
            id: UUID(uuidString: id) ?? UUID(),
            bookId: bookId,
            chapterId: chapterId,
            verse: verse,
            color: color,
            note: note,
            updatedAt: Date(timeIntervalSince1970: Double(updatedAt) / 1000),
            deleted: deleted
        )
    }
}

private struct PositionDTO: Codable {
    let bookId: String
    let chapterId: String
    let chapterTitle: String
    let verse: Int
    let updatedAt: Int64

    init(_ position: ReadingPosition) {
        bookId = position.bookId
        chapterId = position.chapterId
        chapterTitle = position.chapterTitle
        verse = position.verse
        updatedAt = Int64(position.date.timeIntervalSince1970 * 1000)
    }

    var domain: ReadingPosition {
        ReadingPosition(
            bookId: bookId,
            chapterId: chapterId,
            chapterTitle: chapterTitle,
            verse: verse,
            date: Date(timeIntervalSince1970: Double(updatedAt) / 1000)
        )
    }
}

/// Le profil sur le fil.
///
/// **`portrait` est une `Data` et non une chaîne** : `JSONEncoder` l'écrit en
/// base64 et `JSONDecoder` la relit, ce qui est exactement ce que le serveur
/// range. L'écrire à la main serait une occasion de se tromper d'encodage.
private struct ProfilDTO: Codable {
    let nomDusage: String
    let prenom: String
    let nom: String
    let bio: String
    let portrait: Data?
    let updatedAt: Int64

    init(_ profil: ProfilEnVol) {
        nomDusage = profil.nomDUsage
        prenom = profil.prenom
        nom = profil.nom
        bio = profil.bio
        portrait = profil.portrait
        updatedAt = Int64(profil.updatedAt.timeIntervalSince1970 * 1000)
    }

    var domain: ProfilEnVol {
        ProfilEnVol(
            nomDUsage: nomDusage, prenom: prenom, nom: nom, bio: bio, portrait: portrait,
            updatedAt: Date(timeIntervalSince1970: Double(updatedAt) / 1000))
    }
}

private struct PullDTO: Decodable {
    let highlights: [HighlightDTO]
    let position: PositionDTO?
    let serverTime: Int64
    /// Absent d'un serveur qui ne connaît pas encore le profil — l'app arrive
    /// toujours avant lui, `deployer-backend.yml` ne partant que de `main`.
    let profil: ProfilDTO?
}

private struct PushDTO: Encodable {
    let highlights: [HighlightDTO]
    let position: PositionDTO?
    let profil: ProfilDTO?
}

// MARK: - Authentification

/// L'échange OAuth, côté app.
///
/// L'app n'envoie que le **code d'autorisation** que le fournisseur vient de
/// lui remettre. Le secret client, lui, ne quitte jamais la Lambda : c'est
/// toute la raison d'être du proxy — un `.ipa` se désassemble en dix minutes.
public struct HTTPAuthService: AuthService {
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func signIn(
        provider: AuthProvider,
        code: String,
        redirectURI: String,
        verifier: String?
    ) async throws -> Session {
        struct Body: Encodable {
            let code: String
            let redirectUri: String
            let codeVerifier: String?
        }
        do {
            return try await post(
                "auth/\(provider.rawValue)",
                Body(code: code, redirectUri: redirectURI, codeVerifier: verifier)
            )
        } catch AccountError.server(503) {
            // Le serveur dit qu'il n'a pas les identifiants de ce fournisseur.
            // Sans cette traduction, le lecteur lisait « Le serveur a répondu
            // 503 » — vrai, et inutilisable : rien ne lui disait qu'un autre
            // bouton marcherait.
            throw AccountError.providerNotConfigured(provider)
        }
    }

    public func refresh(_ refreshToken: String) async throws -> Session {
        struct Body: Encodable { let refreshToken: String }
        return try await post("auth/refresh", Body(refreshToken: refreshToken))
    }

    private func post(_ path: String, _ body: some Encodable) async throws -> Session {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try APIClient.encoder.encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AccountError.offline
        }

        guard let http = response as? HTTPURLResponse else { throw AccountError.server(0) }
        switch http.statusCode {
        case 200..<300:
            let dto = try APIClient.decoder.decode(SessionDTO.self, from: data)
            return Session(
                accessToken: dto.accessToken,
                refreshToken: dto.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(dto.expiresIn))
            )
        case 401:
            throw AccountError.providerRefused
        default:
            throw AccountError.server(http.statusCode)
        }
    }
}

// MARK: - Synchronisation

public struct HTTPSyncService: SyncService {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func pull(since: Date?) async throws -> SyncPayload {
        let query = since.map {
            [URLQueryItem(name: "since", value: String(Int64($0.timeIntervalSince1970 * 1000)))]
        } ?? []

        let dto = try await client.send("GET", "sync", query: query, as: PullDTO.self)
        return SyncPayload(
            highlights: dto.highlights.compactMap(\.domain),
            position: dto.position?.domain,
            serverTime: Date(timeIntervalSince1970: Double(dto.serverTime) / 1000),
            profil: dto.profil?.domain
        )
    }

    public func push(_ payload: SyncPayload) async throws {
        try await client.send(
            "PUT",
            "sync",
            body: PushDTO(
                highlights: payload.highlights.map(HighlightDTO.init),
                position: payload.position.map(PositionDTO.init),
                profil: payload.profil.map(ProfilDTO.init)
            )
        )
    }

    public func erase() async throws {
        try await client.send("DELETE", "me")
    }
}
