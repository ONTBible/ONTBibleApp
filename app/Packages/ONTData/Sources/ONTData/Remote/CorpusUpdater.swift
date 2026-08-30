import Foundation
import ONTKit

/// La mise à jour du corpus par le réseau.
///
/// ## Pourquoi le corpus sort du bundle
///
/// Il y vit encore, et il y reste — mais il n'y est plus seul. Tant qu'il n'y
/// avait que lui, corriger un verset demandait une compilation, un envoi à
/// Apple, une revue, puis que chaque lecteur installe la mise à jour. Une faute
/// de frappe mettait des jours à disparaître, et davantage chez qui n'a pas
/// activé les mises à jour automatiques.
///
/// Publié sur `ontbible.com/corpus/`, il atteint les lecteurs en minutes.
///
/// ## Le bundle reste la base, et ce n'est pas de la prudence
///
/// Une installation neuve doit lire le corpus **avant** d'avoir vu le réseau —
/// dans un train, dans un avion, sur un forfait épuisé. Le bundle garantit ça.
/// Le disque ne fait que le recouvrir, fichier par fichier.
///
/// ## Ce qui est téléchargé est écrit sur l'appareil
///
/// Dans `Application Support`, et **pas** dans `Caches` : iOS purge le second
/// quand l'espace manque, et l'on perdrait le corpus au pire moment — hors
/// ligne, sans moyen de le reprendre.
///
/// Il en est exclu des sauvegardes : ces vingt méga sont retéléchargeables, ils
/// n'ont rien à faire dans l'iCloud du lecteur.
public actor CorpusUpdater {
    /// Le manifeste publié — le seul fichier à nom fixe, et le point d'entrée.
    struct Manifest: Decodable, Sendable {
        struct Entry: Decodable, Sendable, Equatable {
            let chemin: String
            let empreinte: String
            let octets: Int
        }

        let schema: Int
        let genere: String
        let fichiers: [String: Entry]
        let livres: [String: Entry]

        /// Tout ce qu'il désigne, sous la forme `nom local → entrée`.
        ///
        /// Les noms locaux sont ceux qu'attend le lecteur de disque, calqués
        /// sur ceux du bundle : `corpus.json`, `books/bereshit.json`. Le nom
        /// **publié**, lui, porte l'empreinte — c'est ce qui autorise un cache
        /// d'un an.
        var tout: [(local: String, entree: Entry)] {
            let noms = [
                "plan": "corpus.json",
                "quotidien": "daily.json",
                "glossaire": "glossary.json",
                "occurrences": "occurrences.json",
            ]
            return fichiers.compactMap { cle, entree in
                noms[cle].map { (local: $0, entree: entree) }
            } + livres.map { (local: "books/\($0.key).json", entree: $0.value) }
        }
    }

    public enum Failure: LocalizedError {
        case unsupportedSchema(Int)

        public var errorDescription: String? {
            switch self {
            case .unsupportedSchema(let version):
                // Un manifeste plus récent que cette version de l'app décrit
                // peut-être des fichiers qu'elle ne saurait pas lire. Mieux
                // vaut ne rien faire et continuer sur le bundle que d'écrire
                // sur le disque quelque chose d'illisible.
                "Manifeste de corpus non pris en charge, version \(version)"
            }
        }
    }

    /// La version du manifeste que ce code sait lire.
    ///
    /// **2 depuis 1.0.3**, où l'accentuation a changé de nom sur le fil. Ce
    /// numéro est ce qui protège les versions antérieures : elles refusent le
    /// manifeste entier et gardent leur corpus embarqué, au lieu de lever sur
    /// un nœud qu'elles ne connaissent pas.
    static let schema = 2

    private let origine: URL
    private let dossier: URL
    private let session: URLSession
    /// Injectable : sans ça, l'épreuve de la garde dépendrait du bundle de
    /// l'hôte des tests, qui ne porte pas le corpus.
    let estampilleEmbarquee: Estampille?

    public init(
        origine: URL = URL(string: "https://ontbible.com/corpus/")!,
        dossier: URL? = nil,
        session: URLSession = .shared
    ) {
        self.init(origine: origine, dossier: dossier, session: session,
                  estampilleEmbarquee: Self.estampilleEmbarquee())
    }

    init(
        origine: URL,
        dossier: URL?,
        session: URLSession,
        estampilleEmbarquee: Estampille?
    ) {
        self.origine = origine
        self.dossier = dossier ?? Self.dossierParDefaut()
        self.session = session
        self.estampilleEmbarquee = estampilleEmbarquee
    }

    /// `Application Support/corpus`.
    ///
    /// Publique parce que les lecteurs de disque s'en servent comme valeur par
    /// défaut, et qu'un argument par défaut ne peut pas appeler ce qui est plus
    /// fermé que lui : la valeur est écrite dans l'interface du module, donc
    /// visible de qui l'appelle.
    public static func dossierParDefaut() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("corpus", isDirectory: true)
    }

    /// L'estampille d'un corpus — **ce qu'il contient**, pas quand on l'a compilé.
    ///
    /// ## Pourquoi il en fallait une
    ///
    /// L'app lit le disque quand il existe, le bundle sinon. Le disque est
    /// rempli par ce qui est publié. Tant que le publié est le plus récent des
    /// deux, tout va bien — et c'est faux à chaque fois qu'un build part avant
    /// un déploiement du site, c'est-à-dire à chaque livraison TestFlight.
    ///
    /// Mesuré sur simulateur le 30 août 2026 : bundle à 1913 occurrences de
    /// `shem`, disque à 217. Le dossier effacé, l'app le recréait au lancement
    /// en retéléchargeant l'ancien. La couche des noms propres serait arrivée
    /// chez tous les testeurs **sans un seul nom affiché**, et aucun test ne
    /// pouvait l'attraper : ils mesurent tous le corpus du bundle, que
    /// personne ne lit.
    ///
    /// ## Pourquoi ce n'est pas l'heure du build
    ///
    /// `build.rs` laisse `generated_at` vide, et le commentaire dit pourquoi :
    /// deux exécutions sur le même vault doivent produire le même octet, donc
    /// la même empreinte, donc aucun retéléchargement. Un `now()` republierait
    /// tout le corpus à des lecteurs dont rien n'a changé.
    ///
    /// La date porte donc celle du **contenu source** — le dernier commit du
    /// vault. Déterministe pour un vault donné, et croissante quand il change :
    /// exactement l'ordre qui manquait, sans rien sacrifier.
    ///
    /// ## Pourquoi un format strict, et pas `ISO8601DateFormatter`
    ///
    /// Parce que la comparaison se fait sur des chaînes, et que deux écritures
    /// du **même instant** s'ordonnent alors à l'envers :
    ///
    ///     "2026-08-30T00:14:00Z" < "2026-08-30T02:14:00+02:00"
    ///
    /// Une date bien formée mais dans un autre fuseau ferait garder le plus
    /// vieux des deux corpus en croyant garder le plus neuf — le défaut
    /// d'aujourd'hui, sous une forme bien plus difficile à voir qu'un champ
    /// vide. La session du site l'a relevé avant que ça arrive.
    ///
    /// D'où : **UTC, à la seconde, et rien d'autre.** Ce qui ne s'écrit pas
    /// ainsi n'est pas une estampille, quelle que soit sa vraisemblance.
    struct Estampille: Comparable, Sendable {
        let texte: String

        /// `2026-08-30T00:14:00Z`, strictement.
        init?(_ brut: String) {
            let c = Array(brut)
            guard c.count == 20, c[4] == "-", c[7] == "-", c[10] == "T",
                  c[13] == ":", c[16] == ":", c[19] == "Z" else { return nil }
            for i in [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18]
            where !c[i].isNumber { return nil }
            texte = brut
        }

        /// Sûre, parce que le format est fixe : à longueur et champs égaux,
        /// l'ordre lexicographique **est** l'ordre chronologique.
        static func < (a: Self, b: Self) -> Bool { a.texte < b.texte }
    }

    /// L'estampille du corpus que l'app embarque, lue de son `manifest.json`.
    ///
    /// `nil` quand elle manque ou ne s'écrit pas comme il faut — et le refus
    /// qui s'ensuit est délibéré, voir `synchroniser`.
    static func estampilleEmbarquee(_ bundle: Foundation.Bundle = .main) -> Estampille? {
        guard let url = bundle.url(forResource: "manifest", withExtension: "json"),
              let octets = try? Data(contentsOf: url),
              let objet = try? JSONSerialization.jsonObject(with: octets) as? [String: Any],
              let brut = objet["generatedAt"] as? String
        else { return nil }
        return Estampille(brut)
    }

    /// Va chercher ce qui a changé, et l'écrit.
    ///
    /// Rend le nombre de fichiers remplacés. Zéro veut dire « rien de neuf »,
    /// ce qui est le cas le plus fréquent et ne coûte qu'une requête de 800
    /// octets.
    ///
    /// **Ne jette pas sur une panne de réseau.** Une mise à jour est un
    /// agrément, pas une condition : l'app lit ce qu'elle a. Seules les erreurs
    /// qui disent quelque chose — un manifeste d'une version inconnue —
    /// remontent.
    @discardableResult
    public func synchroniser() async throws -> Int {
        guard let manifeste = try await manifestePublie() else { return 0 }
        guard manifeste.schema == Self.schema else {
            throw Failure.unsupportedSchema(manifeste.schema)
        }

        // **On n'accepte que ce qu'on peut prouver plus récent.**
        //
        // Refuser plutôt qu'accepter, quand l'ordre est indécidable : un corpus
        // qui ne se met pas à jour se voit et se répare ; un corpus
        // silencieusement remplacé par du plus vieux ne se voit pas. C'est
        // précisément le défaut qu'on corrige, et l'accepter « au cas où »
        // serait le reproduire dans sa correction.
        //
        // Conséquence assumée : tant que le site publie un `genere` vide, les
        // builds qui portent cette garde restent sur leur bundle. C'est
        // l'ordre de livraison — pipeline, site, app —, et l'inverse gèlerait
        // les mises à jour sans que rien ne les dégèle.
        guard let publiee = Estampille(manifeste.genere),
              let embarquee = estampilleEmbarquee,
              publiee > embarquee
        else { return 0 }

        try preparerLeDossier()
        var connus = empreintesConnues()
        var remplaces = 0

        for (local, entree) in manifeste.tout where connus[local] != entree.empreinte {
            // Un fichier qui échoue n'emporte pas les autres : le corpus est
            // fait de morceaux indépendants, et sept livres sur huit valent
            // mieux que rien.
            guard let octets = try? await telecharger(entree) else { continue }
            guard (try? ecrire(octets, vers: local)) != nil else { continue }
            // L'empreinte n'est notée que pour ce qui vient réellement d'être
            // écrit. Le registre enregistrait tout le manifeste dès qu'un seul
            // fichier passait : un téléchargement raté était alors déclaré à
            // jour, et jamais retenté — la correction qu'il portait n'arrivait
            // qu'au prochain changement de ce livre-là, c'est-à-dire peut-être
            // jamais.
            connus[local] = entree.empreinte
            remplaces += 1
        }

        if remplaces > 0 {
            // Écrit **après** les fichiers, et c'est tout le sujet — voir
            // ci-dessous.
            try? enregistrerLesEmpreintes(connus)
        }
        return remplaces
    }

    // MARK: - Le réseau

    private func manifestePublie() async throws -> Manifest? {
        let url = origine.appendingPathComponent("manifeste.json")
        guard let (octets, reponse) = try? await session.data(from: url),
            (reponse as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: octets)
    }

    private func telecharger(_ entree: Manifest.Entry) async throws -> Data {
        let (octets, reponse) = try await session.data(
            from: origine.appendingPathComponent(entree.chemin)
        )
        guard (reponse as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        // La taille annoncée fait office de somme de contrôle du pauvre : elle
        // ne prouve pas l'intégrité, mais elle attrape une réponse tronquée ou
        // une page d'erreur servie à la place du fichier — ce qui est le cas
        // réel qu'on veut éviter.
        guard octets.count == entree.octets else { throw URLError(.dataLengthExceedsMaximum) }
        return octets
    }

    // MARK: - Le disque

    private func preparerLeDossier() throws {
        var dossier = self.dossier
        try FileManager.default.createDirectory(
            at: dossier.appendingPathComponent("books", isDirectory: true),
            withIntermediateDirectories: true
        )
        var valeurs = URLResourceValues()
        valeurs.isExcludedFromBackup = true
        try? dossier.setResourceValues(valeurs)
    }

    /// Écriture **atomique**.
    ///
    /// `.atomic` écrit à côté puis renomme. Sans ça, une application tuée au
    /// milieu d'une écriture — l'utilisateur qui balaie, iOS qui récupère de la
    /// mémoire — laisserait un demi-livre sur le disque. Le défaut ne se verrait
    /// qu'à la lecture, des semaines plus tard, sur un chapitre au hasard.
    private func ecrire(_ octets: Data, vers local: String) throws {
        try octets.write(to: dossier.appendingPathComponent(local), options: .atomic)
    }

    private var registre: URL { dossier.appendingPathComponent("empreintes.json") }

    private func empreintesConnues() -> [String: String] {
        guard let octets = try? Data(contentsOf: registre),
            let table = try? JSONDecoder().decode([String: String].self, from: octets)
        else { return [:] }
        return table
    }

    /// Le registre est écrit **après** les fichiers, et c'est tout le sujet.
    ///
    /// Il dit « voici ce que j'ai », pas « voici ce qui existe ». L'écrire
    /// avant reviendrait à le promettre : une coupure entre les deux laisserait
    /// l'app persuadée de posséder un livre qu'elle n'a pas, et elle ne le
    /// retéléchargerait jamais.
    ///
    /// C'est pourquoi il reçoit la table **construite au fil des écritures**,
    /// et non le manifeste. Recopier le manifeste revenait à la même promesse,
    /// une couche plus haut : un fichier dont le téléchargement avait échoué y
    /// figurait à jour.
    private func enregistrerLesEmpreintes(_ table: [String: String]) throws {
        try JSONEncoder().encode(table).write(to: registre, options: .atomic)
    }
}
