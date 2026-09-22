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
    /// Le nom d'usage, sans son `@` — `gloiiire_`.
    ///
    /// **Le seul champ du profil qui soit un identifiant** : les autres
    /// décrivent, celui-ci désigne. C'est par lui qu'un lecteur en nommera un
    /// autre le jour où le Qahal ouvrira. Ses règles vivent dans `NomDUsage`.
    public var nomDUsage: String
    public var prenom: String
    public var nom: String
    /// Quelques lignes, libres.
    public var bio: String
    /// L'adresse à laquelle on peut joindre le lecteur.
    ///
    /// **Elle n'est pas celle de la connexion**, et c'est tout l'intérêt.
    /// « Se connecter avec Apple » permet de masquer son adresse : le compte
    /// s'ouvre alors sous un relais `@privaterelay.appleid.com` que le lecteur
    /// n'a jamais choisi, et qu'aucun service tiers ne connaît. `session.email`
    /// peut donc être absente, ou présente et inutilisable.
    ///
    /// Celle-ci est ==déclarée par le lecteur, pour ce qu'il veut en faire== :
    /// aujourd'hui retrouver son Gravatar, demain être prévenu d'une parution.
    /// Les deux demandent la même chose — une adresse qu'il emploie vraiment.
    ///
    /// Vide tant qu'il n'en a pas saisi : on ne recopie pas celle de la
    /// session à sa place. Une adresse pré-remplie qu'il n'a pas relue est une
    /// adresse qu'il croira avoir validée.
    public var courriel: String
    /// **Quand** le lecteur a accepté d'être prévenu par courriel — et `nil`
    /// s'il ne l'a pas fait.
    ///
    /// La date *est* le consentement. Un booléen à côté d'un horodatage se
    /// désynchronise, et il faut alors deviner lequel des deux croire. Le RGPD
    /// demande de pouvoir **prouver** un consentement, pas seulement de le
    /// détenir : sans date, il n'y a rien à montrer.
    public var courrielsConsentis: Date?
    /// Le nom du fichier du portrait dans le dossier des données, jamais son
    /// contenu.
    ///
    /// Une image dans le même fichier que le reste ferait un JSON de plusieurs
    /// centaines de kilo-octets, relu et réécrit à chaque changement de
    /// réglage. Le portrait vit à côté ; ceci n'en garde que l'adresse.
    public var portrait: String?
    /// Quand il a changé pour la dernière fois.
    ///
    /// **C'est ce qui arbitre entre deux appareils** — dernier écrit gagné,
    /// la même règle que les surlignages. Sans lui, un appareil resté
    /// longtemps hors ligne réimposerait au retour un nom qu'on a changé
    /// ailleurs entre-temps.
    public var updatedAt: Date

    public init(
        nomDUsage: String = "", prenom: String = "", nom: String = "", bio: String = "",
        courriel: String = "", courrielsConsentis: Date? = nil,
        portrait: String? = nil, updatedAt: Date = Date()
    ) {
        self.nomDUsage = nomDUsage
        self.prenom = prenom
        self.nom = nom
        self.bio = bio
        self.courriel = courriel
        self.courrielsConsentis = courrielsConsentis
        self.portrait = portrait
        self.updatedAt = updatedAt
    }

    /// Le nom tel qu'on l'affiche, ou `nil` quand il n'y en a pas.
    ///
    /// Rend `nil` plutôt qu'une chaîne vide : une vue qui reçoit `""` dessine
    /// une ligne vide à la bonne hauteur, et l'écran a l'air cassé.
    public var nomAffiche: String? {
        let entier = "\(prenom) \(nom)".trimmingCharacters(in: .whitespacesAndNewlines)
        return entier.isEmpty ? nil : entier
    }

    /// Comment nommer ce lecteur **dans une barre latérale**, sans jamais rendre
    /// vide.
    ///
    /// Distinct de `nomAffiche`, qui rend `nil` exprès : un écran de profil doit
    /// pouvoir ne rien écrire, une ligne de barre doit toujours porter un
    /// libellé. Trois recours, du plus personnel au plus neutre — le prénom et
    /// le nom, le nom d'usage, puis « Vous ».
    ///
    /// « Vous » n'est pas un pis-aller : c'est ce qu'une app écrit d'un lecteur
    /// qu'elle ne connaît pas encore, et ça se lit très bien.
    public var nomDeBarre: String {
        if let nomAffiche { return nomAffiche }
        if !nomDUsage.isEmpty { return nomDUsage }
        return "Vous"
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
    /// Le nom d'usage tel qu'on l'affiche, `@` compris — ou `nil` s'il n'y en a
    /// pas. **Le `@` appartient à l'affichage, jamais à la donnée** : le garder
    /// dans le champ ferait qu'un jour quelqu'un stockerait `@@gloiiire_`.
    public var arobase: String? {
        nomDUsage.isEmpty ? nil : "@\(nomDUsage)"
    }

    public var estVide: Bool {
        nomDUsage.isEmpty && nomAffiche == nil && bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && portrait == nil
    }

    /// Décodage tolérant, comme partout ailleurs dans ce fichier de données.
    ///
    /// Un profil écrit avant qu'un champ existe se relit sans erreur. Sans ça,
    /// ajouter une ligne au profil ferait perdre **tout** le fichier du
    /// lecteur — surlignages compris — au premier lancement suivant.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nomDUsage = try c.decodeIfPresent(String.self, forKey: .nomDUsage) ?? ""
        prenom = try c.decodeIfPresent(String.self, forKey: .prenom) ?? ""
        nom = try c.decodeIfPresent(String.self, forKey: .nom) ?? ""
        bio = try c.decodeIfPresent(String.self, forKey: .bio) ?? ""
        // Tolérant : les profils écrits avant ce champ n'en portent pas, et
        // un décodage strict les rendrait illisibles d'un coup.
        courriel = try c.decodeIfPresent(String.self, forKey: .courriel) ?? ""
        courrielsConsentis = try c.decodeIfPresent(Date.self, forKey: .courrielsConsentis)
        portrait = try c.decodeIfPresent(String.self, forKey: .portrait)
        // `.distantPast` et non `Date()` pour un fichier écrit avant ce champ :
        // un profil sans horodatage doit **perdre** contre n'importe quel autre,
        // et non gagner parce qu'on vient de le lire.
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }
}
