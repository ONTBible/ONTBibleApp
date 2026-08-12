import Foundation
import ONTKit
import Security

/// Le rangement de la session, dans le trousseau.
///
/// Pas `UserDefaults` : c'est un fichier `.plist` en clair dans le conteneur
/// de l'app, parfait pour une préférence d'affichage, inacceptable pour un
/// jeton de session. Le trousseau est chiffré par le système et lié à
/// l'appareil.
///
/// `ThisDeviceOnly` est délibéré : un jeton de session n'a pas à voyager dans
/// une sauvegarde iCloud vers un autre appareil. Le lecteur s'y reconnectera.
///
/// Le **consentement**, lui, reste dans `UserDefaults` : ce n'est pas un
/// secret, et il doit survivre à une déconnexion — un lecteur qui se reconnecte
/// ne devrait pas avoir à redonner son accord.
public final class KeychainSessionStore: SessionStore, @unchecked Sendable {
    private let service: String
    private let account = "session"
    private let lock = NSLock()

    public init(service: String = "com.labibleont.ONT") {
        self.service = service
    }

    public var session: Session? {
        get {
            lock.lock()
            defer { lock.unlock() }

            var query = baseQuery
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne

            var result: CFTypeRef?
            guard
                SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
                let data = result as? Data
            else { return nil }

            return try? JSONDecoder().decode(Session.self, from: data)
        }
        set {
            lock.lock()
            defer { lock.unlock() }

            SecItemDelete(baseQuery as CFDictionary)
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else { return }

            var query = baseQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    public var consent: SyncConsent {
        get {
            guard
                let data = UserDefaults.standard.data(forKey: "syncConsent"),
                let value = try? JSONDecoder().decode(SyncConsent.self, from: data)
            else { return .none }
            return value
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: "syncConsent")
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// Une doublure en mémoire, pour les tests et les aperçus.
public final class InMemorySessionStore: SessionStore, @unchecked Sendable {
    public var session: Session?
    public var consent: SyncConsent = .none

    public init(session: Session? = nil, consent: SyncConsent = .none) {
        self.session = session
        self.consent = consent
    }
}
