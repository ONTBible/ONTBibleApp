import Foundation

/// **À quel compte appartiennent les données posées sur cet appareil.**
///
/// ## Le défaut que ça ferme
///
/// `signOut()` ne touche pas au travail du lecteur — surlignages, notes,
/// position — et c'est délibéré : se déconnecter n'est pas effacer. Mais
/// `signIn()` ne regardait pas non plus à qui ce travail appartenait. Deux
/// comptes sur un même appareil, et **les annotations du premier partaient
/// sous le compte du second** à la première synchronisation.
///
/// Sur des surlignages de Bible, qui révèlent des convictions religieuses —
/// catégorie particulière au sens de l'article 9 du RGPD.
///
/// Relevé par un audit externe le 8 septembre 2026.
///
/// ## Pourquoi le `sub` du jeton, et pas le nom d'usage
///
/// Le nom d'usage **désigne** mais il change : un lecteur qui le renomme
/// deviendrait un autre propriétaire, et ses propres données lui seraient
/// refusées. Le `sub` d'un JWT est l'identifiant que le serveur donne au
/// compte, et il ne bouge pas.
///
/// ## Ce que ce code n'est pas
///
/// **Ce n'est pas une vérification de jeton.** On ne contrôle ni la signature,
/// ni l'expiration, ni l'émetteur — c'est le travail du serveur, et le refaire
/// ici donnerait l'illusion d'une garantie qu'on ne peut pas tenir.
///
/// C'est une **clé de rangement locale** : elle répond à « est-ce le même
/// compte qu'avant ? », jamais à « ce jeton est-il valable ? ». Un jeton forgé
/// tromperait cette lecture — et n'obtiendrait rien du serveur pour autant.
public enum SujetDeSession {
    /// Le `sub` porté par un jeton d'accès, ou `nil` s'il n'en porte pas.
    ///
    /// Les trois segments d'un JWT sont séparés par des points, et la charge
    /// utile est le second, en base64url **sans remplissage** — d'où le
    /// rembourrage manuel : `Data(base64Encoded:)` refuse une longueur qui
    /// n'est pas multiple de quatre, et rendrait `nil` sur un jeton parfaitement
    /// valide.
    public static func sujet(de jeton: String) -> String? {
        let parts = jeton.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }

        var brut = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        brut += String(repeating: "=", count: (4 - brut.count % 4) % 4)

        guard let octets = Data(base64Encoded: brut),
            let objet = try? JSONSerialization.jsonObject(with: octets) as? [String: Any],
            let sujet = objet["sub"] as? String,
            !sujet.isEmpty
        else { return nil }
        return sujet
    }
}
