import Testing

@testable import ONTKit

/// La négociation de capacités, et surtout **ce qu'elle fait de son ignorance**.
@Suite("Ce que le serveur offre")
struct OffreTests {

    /// La règle qui décide de tout : ce qu'on ignore ne se refuse pas.
    ///
    /// Un lecteur hors ligne, ou branché sur un serveur d'avant cette route,
    /// doit garder ses trois boutons. Se fermer sur une ignorance remplacerait
    /// « ça échoue quand on essaie » par « on ne peut plus essayer ».
    @Test("une offre inconnue ne retire rien")
    func inconnueNeRetireRien() {
        let offre = Offre.inconnue
        #expect(offre.fournisseurs == AuthProvider.allCases)
        for capacite in Capacite.allCases {
            #expect(offre.offre(capacite))
        }
        #expect(!offre.estConnue)
    }

    /// **Le cas que tout ceci existe pour attraper** : un serveur dont les
    /// identifiants Apple ne sont pas installés ne doit pas se voir proposer
    /// un bouton Apple.
    @Test("un fournisseur absent de l'offre n'est pas proposé")
    func absentNestPasPropose() {
        let offre = Offre([.authGoogle, .synchronisation])
        #expect(offre.fournisseurs == [.google])
        #expect(!offre.offre(.authApple))
    }

    /// Une offre vide est une réponse, pas une absence de réponse : le serveur
    /// a dit qu'il n'offrait rien, et on le croit.
    @Test("une offre vide retire tout")
    func videRetireTout() {
        let offre = Offre([])
        #expect(offre.fournisseurs.isEmpty)
        #expect(offre.estConnue)
    }

    /// L'ordre compte : la revue App Store exige « Sign in with Apple » en
    /// premier dès qu'un autre fournisseur tiers est proposé.
    @Test("l'ordre des fournisseurs est conservé")
    func ordreConserve() {
        let offre = Offre([.authGithub, .authApple])
        #expect(offre.fournisseurs == [.apple, .github])
    }

    /// Une capacité que le serveur offre et que l'app ignore passe inaperçue —
    /// c'est le sens de la négociation, pas un défaut à signaler.
    @Test("chaque fournisseur exige sa propre capacité")
    func chaqueFournisseurSaCapacite() {
        #expect(AuthProvider.apple.capacite == .authApple)
        #expect(AuthProvider.google.capacite == .authGoogle)
        #expect(AuthProvider.github.capacite == .authGithub)
    }
}
