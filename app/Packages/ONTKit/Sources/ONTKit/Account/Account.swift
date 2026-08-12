import Foundation

/// Les fournisseurs d'identité acceptés.
///
/// Apple en premier : la revue App Store l'exige dès qu'un autre fournisseur
/// tiers est proposé. Ce n'est pas une préférence, c'est une règle de
/// publication.
public enum AuthProvider: String, CaseIterable, Sendable, Codable {
    case apple, google, github

    public var label: String {
        switch self {
        case .apple: "Apple"
        case .google: "Google"
        case .github: "GitHub"
        }
    }
}

/// Une session ouverte.
///
/// Le jeton d'accès est court (1 h) parce qu'il est **irrévocable** — une fois
/// signé, il vaut jusqu'à son expiration. Le jeton de rafraîchissement est
/// long mais stocké côté serveur, donc révocable, et il ne sert qu'une fois :
/// chaque usage en produit un nouveau.
public struct Session: Codable, Hashable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// Vrai si le jeton d'accès est expiré, ou sur le point de l'être.
    ///
    /// La marge évite qu'une requête parte avec un jeton qui expirera pendant
    /// son vol.
    public func isExpired(now: Date = Date(), margin: TimeInterval = 60) -> Bool {
        now.addingTimeInterval(margin) >= expiresAt
    }
}

/// Le consentement à la synchronisation.
///
/// Les surlignages et les notes d'un lecteur de Bible **révèlent des
/// convictions religieuses** : catégorie particulière au sens de l'article 9
/// du RGPD. Leur traitement suppose un consentement *explicite* et *séparé* —
/// pas une case noyée dans des conditions générales.
///
/// D'où ce type distinct des réglages ordinaires, et d'où le fait que
/// l'application reste **pleinement utilisable sans compte** : la
/// synchronisation est une option, jamais un préalable.
public struct SyncConsent: Codable, Hashable, Sendable {
    public var granted: Bool
    public var date: Date?

    public init(granted: Bool = false, date: Date? = nil) {
        self.granted = granted
        self.date = date
    }

    public static let none = SyncConsent()

    public static func grantedNow() -> SyncConsent {
        SyncConsent(granted: true, date: Date())
    }
}

/// Ce qui traverse le réseau dans un sens comme dans l'autre.
public struct SyncPayload: Sendable {
    public var highlights: [Highlight]
    public var position: ReadingPosition?
    /// L'horodatage du serveur, à renvoyer au prochain appel incrémental.
    public var serverTime: Date?

    public init(
        highlights: [Highlight] = [],
        position: ReadingPosition? = nil,
        serverTime: Date? = nil
    ) {
        self.highlights = highlights
        self.position = position
        self.serverTime = serverTime
    }
}

public enum AccountError: LocalizedError, Sendable {
    case cancelled
    case providerRefused
    case unauthorized
    case offline
    case server(Int)

    public var errorDescription: String? {
        switch self {
        case .cancelled: "Connexion annulée."
        case .providerRefused: "Le fournisseur a refusé la connexion."
        case .unauthorized: "Session expirée — reconnectez-vous."
        case .offline: "Pas de connexion. Vos annotations restent sur cet appareil."
        case .server(let code): "Le serveur a répondu \(code)."
        }
    }
}

// MARK: - Ports

/// L'échange d'un code d'autorisation contre une session.
public protocol AuthService: Sendable {
    func signIn(
        provider: AuthProvider,
        code: String,
        redirectURI: String,
        verifier: String?
    ) async throws -> Session

    func refresh(_ refreshToken: String) async throws -> Session
}

/// La synchronisation de ce que le lecteur produit.
public protocol SyncService: Sendable {
    func pull(since: Date?) async throws -> SyncPayload
    func push(_ payload: SyncPayload) async throws
    /// Efface le compte et tout ce qui s'y rattache — exigé par le RGPD.
    func erase() async throws
}

/// Le rangement de la session.
///
/// L'implémentation réelle passe par le trousseau : `UserDefaults` est un
/// fichier en clair dans le conteneur de l'app, ce qui convient à une
/// préférence d'affichage mais pas à un jeton de session.
public protocol SessionStore: AnyObject, Sendable {
    var session: Session? { get set }
    var consent: SyncConsent { get set }
}
