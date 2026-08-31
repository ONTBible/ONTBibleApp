/// Ce que le serveur sait faire — et ce que l'app sait en employer.
///
/// # Pourquoi cette négociation existe
///
/// **L'app arrive structurellement avant le serveur.** Sa moitié voyage
/// `dev → staging → main` ; le backend n'est déployé que par un push sur
/// `main`. Entre deux promotions, une app livrée aux testeurs interroge donc
/// un serveur plus ancien qu'elle — et jusqu'ici elle n'avait aucun moyen de
/// le savoir : `/health` rend `ok`, ce qui dit que le serveur *répond*, pas ce
/// qu'il *sait faire*.
///
/// # Deux listes, et ce n'est pas une duplication
///
/// Le serveur déclare **ce qu'il offre**, dérivé de ce qui est réellement
/// installé chez lui. L'app déclare **ce qu'elle sait employer**. Ce sont deux
/// affirmations différentes, et leur intersection est ce qui marche.
///
/// Une capacité offerte que l'app ignore est sans conséquence : elle passe
/// inaperçue. C'est l'inverse qui blesse — l'app qui emploie ce que le serveur
/// n'a pas —, et c'est cela seul qu'on détecte.
///
/// Ce qui doit concorder, c'est **l'orthographe des clés**, et rien d'autre.
/// Un contrôle s'en charge.
public enum Capacite: String, Sendable, CaseIterable, Codable {
    case authApple = "auth.apple"
    case authGoogle = "auth.google"
    case authGithub = "auth.github"
    case synchronisation = "sync"
    case effacementDuCompte = "compte.effacement"
    case diffusion = "diffusion"
}

extension AuthProvider {
    /// La capacité que ce fournisseur exige du serveur.
    public var capacite: Capacite {
        switch self {
        case .apple: .authApple
        case .google: .authGoogle
        case .github: .authGithub
        }
    }
}

/// Ce que le serveur annonce.
///
/// Un port : le domaine dit ce dont il a besoin, et `ONTData` sait comment
/// l'obtenir. C'est ce qui permet d'éprouver la négociation sans réseau.
public protocol CapacitesService: Sendable {
    func offertes() async throws -> Set<Capacite>
}

/// Ce que le serveur offre, **quand on le sait**.
///
/// `nil` n'est pas « rien » : c'est « on n'a pas pu demander ». Hors ligne, ou
/// serveur trop ancien pour connaître la route — il rend alors `404`, et c'est
/// un cas normal, pas une panne.
///
/// # La règle qui décide de tout
///
/// **Ce qu'on ignore ne se refuse pas.** Une liste inconnue laisse tout passer ;
/// seule une liste **obtenue** peut retirer quelque chose.
///
/// L'inverse serait pire que le défaut qu'on corrige : un lecteur hors ligne,
/// ou branché sur un serveur d'avant cette route, verrait disparaître tous les
/// boutons de connexion. On aurait remplacé « ça échoue quand on essaie » par
/// « on ne peut plus essayer », ce qui n'est pas un progrès.
public struct Offre: Sendable, Equatable {
    private let connues: Set<Capacite>?

    /// L'offre qu'on n'a pas pu demander.
    public static let inconnue = Offre(connues: nil)

    public init(_ capacites: Set<Capacite>) {
        self.connues = capacites
    }

    private init(connues: Set<Capacite>?) {
        self.connues = connues
    }

    /// Le serveur sait-il faire ceci ?
    ///
    /// Vrai quand l'offre est inconnue — voir la règle ci-dessus.
    public func offre(_ capacite: Capacite) -> Bool {
        connues?.contains(capacite) ?? true
    }

    /// A-t-on seulement pu demander ?
    ///
    /// Utile pour distinguer, dans l'interface, « ce serveur ne le propose
    /// pas » de « on ne sait pas encore ».
    public var estConnue: Bool { connues != nil }

    /// Les fournisseurs qu'il vaut la peine de proposer au lecteur.
    ///
    /// L'ordre de `AuthProvider.allCases` est conservé : « Sign in with Apple »
    /// y figure en premier parce que la revue App Store l'exige dès qu'un autre
    /// fournisseur tiers est proposé.
    public var fournisseurs: [AuthProvider] {
        AuthProvider.allCases.filter { offre($0.capacite) }
    }
}
