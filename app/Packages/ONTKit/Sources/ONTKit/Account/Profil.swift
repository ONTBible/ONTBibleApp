import Foundation

/// Ce que le lecteur dit de lui.
///
/// ## Privé aujourd'hui, profil demain
///
/// **Personne d'autre ne voit ces champs.** Le *Qahal* — l'assemblée, le
/// rassemblement des lecteurs — n'a pas de serveur : rien de ce qui suppose
/// d'autres lecteurs n'existe encore, et l'onglet lui-même refuse de le
/// simuler. Publier une bio aujourd'hui la publierait donc vers personne, en
/// laissant croire le contraire.
///
/// Ils sont pourtant écrits **comme un profil** et non comme des préférences :
/// prénom, nom, bio, portrait. Le jour où le Qahal ouvre, ce sont ces
/// champs-là qui deviennent visibles, sans que personne ait à les ressaisir.
/// C'est la décision de l'auteur, prise le 27 août 2026.
///
/// ## Ce qui ne s'y trouve pas
///
/// Aucune date de naissance, aucun genre, aucun lieu. Un service de lecture
/// biblique n'en a pas l'usage, et les demander ferait porter au compte des
/// données que rien ne justifie — c'est la même règle qui interdit au serveur
/// de garder le texte des surlignages.
public struct Profil: Codable, Hashable, Sendable {
    public var prenom: String
    public var nom: String
    /// Quelques lignes, libres.
    public var bio: String
    /// Le nom du fichier du portrait dans le dossier des données, jamais son
    /// contenu.
    ///
    /// Une image dans le même fichier que le reste ferait un JSON de plusieurs
    /// centaines de kilo-octets, relu et réécrit à chaque changement de
    /// réglage. Le portrait vit à côté ; ceci n'en garde que l'adresse.
    public var portrait: String?

    public init(prenom: String = "", nom: String = "", bio: String = "", portrait: String? = nil) {
        self.prenom = prenom
        self.nom = nom
        self.bio = bio
        self.portrait = portrait
    }

    /// Le nom tel qu'on l'affiche, ou `nil` quand il n'y en a pas.
    ///
    /// Rend `nil` plutôt qu'une chaîne vide : une vue qui reçoit `""` dessine
    /// une ligne vide à la bonne hauteur, et l'écran a l'air cassé.
    public var nomAffiche: String? {
        let entier = "\(prenom) \(nom)".trimmingCharacters(in: .whitespacesAndNewlines)
        return entier.isEmpty ? nil : entier
    }

    /// Les initiales, pour tenir lieu de portrait tant qu'il n'y en a pas.
    ///
    /// Deux lettres au plus. Vide quand on ne sait rien — l'appelant dessine
    /// alors une silhouette, ce qui vaut mieux qu'un rond avec un point
    /// d'interrogation.
    public var initiales: String {
        [prenom, nom]
            .compactMap { $0.trimmingCharacters(in: .whitespaces).first }
            .prefix(2)
            .map { String($0).uppercased() }
            .joined()
    }

    /// Vrai quand rien n'a été rempli.
    public var estVide: Bool {
        nomAffiche == nil && bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && portrait == nil
    }

    /// Décodage tolérant, comme partout ailleurs dans ce fichier de données.
    ///
    /// Un profil écrit avant qu'un champ existe se relit sans erreur. Sans ça,
    /// ajouter une ligne au profil ferait perdre **tout** le fichier du
    /// lecteur — surlignages compris — au premier lancement suivant.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        prenom = try c.decodeIfPresent(String.self, forKey: .prenom) ?? ""
        nom = try c.decodeIfPresent(String.self, forKey: .nom) ?? ""
        bio = try c.decodeIfPresent(String.self, forKey: .bio) ?? ""
        portrait = try c.decodeIfPresent(String.self, forKey: .portrait)
    }
}
