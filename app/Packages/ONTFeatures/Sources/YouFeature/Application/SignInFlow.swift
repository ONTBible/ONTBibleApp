import AuthenticationServices

#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif
import CryptoKit
import Foundation
import ONTKit

/// Le résultat d'un flux de connexion : le code, et de quoi le redeemer.
public struct AuthorizationGrant: Sendable {
    public let code: String
    /// Le vérificateur PKCE, quand le fournisseur l'exige.
    public let verifier: String?
    /// L'adresse de retour déclarée, à renvoyer telle quelle au fournisseur.
    public let redirectURI: String
    /// Le nom que le fournisseur a confié **au client**, quand il l'a fait.
    ///
    /// ## Pourquoi il passe par ici et non par le serveur
    ///
    /// Google et GitHub disent le nom au serveur, qui interroge leur API après
    /// l'échange : il amorce le profil lui-même, et le client n'a rien à faire.
    ///
    /// **Apple ne le dit qu'au client, et qu'à la toute première
    /// autorisation.** Il accompagne l'autorisation, pas l'`id_token` ; le
    /// serveur ne le voit jamais, et une seconde connexion ne le redonne à
    /// personne — pas même après une désinstallation.
    ///
    /// Il n'y a donc pas de symétrie à rétablir : l'information n'arrive pas au
    /// même endroit selon le fournisseur, et prétendre le contraire obligerait
    /// à faire transiter par le serveur une donnée qu'il n'a pas.
    ///
    /// `nil` pour Google et GitHub, et pour Apple à toute connexion sauf la
    /// première.
    public let prenom: String?
    public let nom: String?

    public init(
        code: String, verifier: String?, redirectURI: String,
        prenom: String? = nil, nom: String? = nil
    ) {
        self.code = code
        self.verifier = verifier
        self.redirectURI = redirectURI
        self.prenom = prenom
        self.nom = nom
    }
}

/// Les flux de connexion, côté système.
///
/// Les trois fournisseurs ne se ressemblent pas, et la différence n'est pas
/// cosmétique :
///
/// - **Apple** passe par `ASAuthorizationController`, l'interface native
///   (Face ID, pas de navigateur). Il n'y a **aucune redirection** : le code
///   revient directement à l'app. C'est aussi ce qu'exige la revue App Store.
/// - **Google et GitHub** passent par `ASWebAuthenticationSession`, une vue
///   Safari isolée. Isolée est le mot : les identifiants ne transitent jamais
///   par notre code, et Apple refuse les `WKWebView` maison pour
///   l'authentification tierce, précisément pour cette raison.
///
/// **Pourquoi le retour passe par le backend.** Google et GitHub n'acceptent
/// qu'une adresse de retour en HTTPS — un schéma comme `ont://` leur est
/// refusé. Le backend en expose une, qui rebondit aussitôt vers l'app. Il ne
/// fait que faire suivre le code, sans l'échanger.
@MainActor
public struct SignInFlow {
    /// La racine du backend.
    public let baseURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    public func grant(for provider: AuthProvider) async throws -> AuthorizationGrant {
        switch provider {
        case .apple: try await apple()
        case .google, .github: try await web(provider)
        }
    }

    /// L'adresse de retour déclarée chez Google et GitHub.
    public func redirectURI(_ provider: AuthProvider) -> String {
        baseURL.appending(path: "auth/\(provider.rawValue)/callback").absoluteString
    }

    // MARK: - Apple

    private func apple() async throws -> AuthorizationGrant {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        // **On demande le nom, et lui seul.**
        //
        // Apple ne le transmet qu'à la toute première autorisation, et
        // seulement si on l'a demandé. Ne pas le demander, c'est le perdre pour
        // toujours : il n'y a pas de seconde chance, pas même après une
        // désinstallation.
        //
        // Pas l'adresse : le backend n'en garde aucune — il identifie par le
        // `subject` du fournisseur —, et Apple propose un relais qui la rend de
        // toute façon peu parlante. Demander ce dont on n'a pas l'usage est une
        // collecte, pas une fonctionnalité.
        request.requestedScopes = [.fullName]

        let delegate = AppleDelegate()
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = delegate
        controller.presentationContextProvider = delegate

        let accord: AppleDelegate.Accord = try await withCheckedThrowingContinuation {
            continuation in
            delegate.continuation = continuation
            controller.performRequests()
        }

        // Ni redirection ni PKCE : l'autorisation a été accordée à l'app
        // elle-même, et c'est son identifiant que le backend présentera.
        return AuthorizationGrant(
            code: accord.code, verifier: nil, redirectURI: "",
            prenom: accord.prenom, nom: accord.nom)
    }

    // MARK: - Google et GitHub

    private func web(_ provider: AuthProvider) async throws -> AuthorizationGrant {
        let pkce = PKCE()
        let redirect = redirectURI(provider)

        guard let url = authorizationURL(provider, redirect: redirect, challenge: pkce.challenge)
        else { throw AccountError.providerRefused }

        let anchor = PresentationAnchor()
        let code: String = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: Router.scheme
            ) { callback, error in
                if let error {
                    let cancelled = (error as? ASWebAuthenticationSessionError)?.code
                        == .canceledLogin
                    continuation.resume(throwing: cancelled ? AccountError.cancelled : error)
                    return
                }

                let items = callback
                    .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
                    .queryItems

                if let code = items?.first(where: { $0.name == "code" })?.value {
                    continuation.resume(returning: code)
                } else {
                    continuation.resume(throwing: AccountError.providerRefused)
                }
            }
            session.presentationContextProvider = anchor
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        return AuthorizationGrant(code: code, verifier: pkce.verifier, redirectURI: redirect)
    }

    /// L'URL d'autorisation du fournisseur.
    ///
    /// Les identifiants clients publics viennent du `Info.plist` : ce ne sont
    /// pas des secrets — ils voyagent dans cette URL même. Le *client secret*,
    /// lui, reste sur la Lambda.
    private func authorizationURL(
        _ provider: AuthProvider,
        redirect: String,
        challenge: String
    ) -> URL? {
        let key = provider == .google ? "ONTGoogleClientID" : "ONTGitHubClientID"
        guard
            let clientID = Bundle.main.object(forInfoDictionaryKey: key) as? String,
            !clientID.isEmpty
        else { return nil }

        var components = URLComponents(
            string: provider == .google
                ? "https://accounts.google.com/o/oauth2/v2/auth"
                : "https://github.com/login/oauth/authorize"
        )
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(
                name: "scope",
                value: provider == .google ? "openid email" : "read:user user:email"
            ),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return components?.url
    }
}

// MARK: - PKCE

/// Le couple vérificateur / défi de PKCE.
///
/// Sans lui, le code d'autorisation transite par un schéma d'URL
/// personnalisé — et une autre app installée sur l'appareil peut déclarer le
/// même schéma et l'intercepter. Elle pourrait alors le présenter à *notre*
/// backend et obtenir une session.
///
/// PKCE ferme cette porte : l'app tire un secret au hasard (le vérificateur),
/// n'en envoie que l'empreinte (le défi) au fournisseur, et ne révèle le
/// secret qu'au moment de l'échange. Un code volé sans son vérificateur ne
/// vaut rien.
struct PKCE {
    let verifier: String
    let challenge: String

    init() {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        verifier = Data(bytes).base64URLEncoded

        let digest = SHA256.hash(data: Data(verifier.utf8))
        challenge = Data(digest).base64URLEncoded
    }
}

extension Data {
    /// Base64 « URL-safe », sans remplissage — ce que la RFC 7636 impose.
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Passerelles vers UIKit

private final class AppleDelegate: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {
    /// Ce qu'Apple rend : le code, et le nom s'il le donne.
    struct Accord: Sendable {
        let code: String
        let prenom: String?
        let nom: String?
    }

    var continuation: CheckedContinuation<Accord, Error>?

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let data = credential.authorizationCode,
            let code = String(data: data, encoding: .utf8)
        else {
            continuation?.resume(throwing: AccountError.providerRefused)
            return
        }
        // `fullName` est nul à toute connexion sauf la première. Ce n'est pas
        // une erreur à signaler : c'est le contrat d'Apple, et le profil est
        // déjà amorcé depuis longtemps quand ça arrive.
        let composantes = credential.fullName
        continuation?.resume(
            returning: Accord(
                code: code,
                prenom: sansEspaces(composantes?.givenName),
                nom: sansEspaces(composantes?.familyName)))
    }

    /// Une chaîne vide n'est pas un nom.
    ///
    /// Apple rend parfois `""` plutôt que `nil` quand le lecteur a effacé un
    /// champ dans sa fiche. Écrire cette chaîne dans le profil poserait une
    /// date de mise à jour sur un contenu vide, et la fusion — dernier écrit
    /// gagné — ferait alors effacer un nom saisi ailleurs.
    private func sansEspaces(_ valeur: String?) -> String? {
        guard let coupe = valeur?.trimmingCharacters(in: .whitespacesAndNewlines),
            !coupe.isEmpty
        else { return nil }
        return coupe
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        let cancelled = (error as? ASAuthorizationError)?.code == .canceled
        continuation?.resume(throwing: cancelled ? AccountError.cancelled : error)
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        PresentationAnchor.keyWindow()
    }
}

private final class PresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        Self.keyWindow()
    }

    /// La fenêtre sur laquelle la session web vient s'ancrer.
    ///
    /// **Deux mondes, deux façons de trouver une fenêtre.** iOS passe par ses
    /// scènes ; le Mac a une fenêtre clé et rien d'autre à démêler.
    static func keyWindow() -> ASPresentationAnchor {
        #if canImport(UIKit)
            let scenes = UIApplication.shared.connectedScenes.compactMap {
                $0 as? UIWindowScene
            }
            if let key = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
                return key
            }
            // Le repli. `ASPresentationAnchor()` sans scène est déprécié depuis
            // iOS 26 et ne saurait de toute façon pas où se présenter : une
            // fenêtre doit appartenir à une scène. À défaut de fenêtre clé,
            // n'importe quelle fenêtre déjà posée fait l'affaire — elle
            // appartient forcément à une scène.
            if let existante = scenes.flatMap(\.windows).first {
                return existante
            }
            let scene = scenes.first { $0.activationState == .foregroundActive }
                ?? scenes.first
            return scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        #else
            // Sur le Mac, la fenêtre clé suffit. S'il n'y en a pas — l'app
            // vient d'ouvrir, ou toutes ses fenêtres sont fermées —, on en
            // prend une quelconque plutôt que d'en fabriquer une : une fenêtre
            // neuve apparaîtrait vide derrière la feuille d'authentification.
            NSApplication.shared.keyWindow
                ?? NSApplication.shared.windows.first
                ?? NSWindow()
        #endif
    }
}
