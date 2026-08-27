import Testing

@testable import ONTKit

/// Ce que le lecteur lit quand la connexion échoue.
///
/// Les messages d'erreur sont du texte d'interface : personne ne les compile,
/// donc rien ne signale qu'ils sont devenus faux. Ces épreuves gardent la seule
/// chose qui compte pour le lecteur — **est-ce que ça vaut la peine de
/// réessayer**.
@Suite("Les messages de connexion")
struct AccountErrorTests {

    /// Un fournisseur sans identifiants ne s'installera pas en réessayant.
    ///
    /// C'est toute la différence avec `providerUnavailable`, qui dit « Réessayez
    /// dans un instant » — vrai pour une panne passagère, et un mur pour un
    /// fournisseur absent du déploiement. Le lecteur doit apprendre qu'un autre
    /// bouton marchera, pas qu'il faut patienter.
    @Test("un fournisseur non configuré n'invite jamais à réessayer")
    func nonConfigureNInvitePasAReessayer() throws {
        for provider in [AuthProvider.apple, .google, .github] {
            let message = try #require(
                AccountError.providerNotConfigured(provider).errorDescription
            )
            #expect(!message.lowercased().contains("réessayez"))
            #expect(message.contains(provider.label))
        }
    }

    /// Et l'inverse, pour que la distinction ne se perde pas dans un sens
    /// comme dans l'autre.
    @Test("une panne passagère, elle, invite à réessayer")
    func passagereInviteAReessayer() throws {
        let message = try #require(
            AccountError.providerUnavailable(.google).errorDescription
        )
        #expect(message.lowercased().contains("réessayez"))
    }

    @Test("les deux ne disent pas la même chose")
    func lesDeuxDiffèrent() {
        #expect(
            AccountError.providerNotConfigured(.github)
                != AccountError.providerUnavailable(.github)
        )
    }
}
