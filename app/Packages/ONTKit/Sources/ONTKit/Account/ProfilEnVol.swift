import Foundation

/// Le profil tel qu'il voyage.
///
/// **Il porte les octets du portrait, pas son nom de fichier.** Un nom de
/// fichier n'a de sens que sur l'appareil qui l'a écrit : l'envoyer ferait
/// arriver sur l'autre téléphone une adresse qui ne mène nulle part. C'est la
/// raison d'être de ce type — le domaine local et le domaine en vol ne disent
/// pas la même chose du portrait, et les confondre casserait l'un des deux.
///
/// Le reste est identique, et volontairement plat : ce qui traverse le réseau
/// est un contrat, et un contrat gagne à n'avoir aucune structure à deviner.
public struct ProfilEnVol: Codable, Hashable, Sendable {
    public var nomDUsage: String
    public var prenom: String
    public var nom: String
    public var bio: String
    /// Les octets de l'image. `JSONEncoder` les écrit en base64, ce que le
    /// serveur attend.
    public var portrait: Data?
    public var updatedAt: Date

    public init(
        nomDUsage: String = "", prenom: String = "", nom: String = "", bio: String = "",
        portrait: Data? = nil, updatedAt: Date = Date()
    ) {
        self.nomDUsage = nomDUsage
        self.prenom = prenom
        self.nom = nom
        self.bio = bio
        self.portrait = portrait
        self.updatedAt = updatedAt
    }

    /// Ce qu'on envoie, depuis ce qu'on garde.
    public init(_ profil: Profil, portrait: Data?) {
        self.init(
            nomDUsage: profil.nomDUsage, prenom: profil.prenom, nom: profil.nom,
            bio: profil.bio, portrait: portrait, updatedAt: profil.updatedAt)
    }

    /// Ce qu'on garde, depuis ce qu'on reçoit — **sans le portrait**, dont le
    /// nom de fichier ne peut être décidé que par le dépôt qui l'écrit.
    public func versLeProfil(portrait nomDuFichier: String?) -> Profil {
        Profil(
            nomDUsage: nomDUsage, prenom: prenom, nom: nom, bio: bio,
            portrait: nomDuFichier, updatedAt: updatedAt)
    }
}
