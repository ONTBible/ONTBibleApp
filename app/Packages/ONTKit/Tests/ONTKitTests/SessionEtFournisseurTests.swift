import Foundation
import Testing

@testable import ONTKit

/// Ce que la session garde du fournisseur.
struct SessionEtFournisseurTests {
    /// **Une session écrite avant ces champs doit se relire.**
    ///
    /// Elle vit dans le trousseau, et un décodage strict déconnecterait tout le
    /// monde à la mise à jour — sans autre message qu'un retour à l'écran de
    /// connexion, que personne ne relierait à un champ ajouté.
    @Test("une session d'avant se relit, sans logo")
    func laSessionDAvant() throws {
        let ancienne = """
            {"accessToken":"a","refreshToken":"r","expiresAt":768000000}
            """
        let lue = try JSONDecoder().decode(Session.self, from: Data(ancienne.utf8))

        #expect(lue.accessToken == "a")
        #expect(lue.provider == nil)
        #expect(lue.email == nil)
    }

    @Test("et une session complète garde les deux")
    func laSessionComplete() throws {
        let posee = Session(
            accessToken: "a", refreshToken: "r", expiresAt: Date(timeIntervalSince1970: 100),
            provider: .apple, email: "lecteur@example.com")
        let revenue = try JSONDecoder().decode(
            Session.self, from: try JSONEncoder().encode(posee))

        #expect(revenue.provider == .apple)
        #expect(revenue.email == "lecteur@example.com")
    }

    /// Les trois fournisseurs se nomment, et le nom sert de repli tant que le
    /// serveur ne renvoie pas l'adresse.
    @Test("chaque fournisseur porte un nom lisible")
    func lesNoms() {
        #expect(AuthProvider.apple.label == "Apple")
        #expect(AuthProvider.google.label == "Google")
        #expect(AuthProvider.github.label == "GitHub")
    }
}
