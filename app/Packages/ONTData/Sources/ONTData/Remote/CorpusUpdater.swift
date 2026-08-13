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
    static let schema = 1

    private let origine: URL
    private let dossier: URL
    private let session: URLSession

    public init(
        origine: URL = URL(string: "https://ontbible.com/corpus/")!,
        dossier: URL? = nil,
        session: URLSession = .shared
    ) {
        self.origine = origine
        self.dossier = dossier ?? Self.dossierParDefaut()
        self.session = session
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

        try preparerLeDossier()
        let connus = empreintesConnues()
        var remplaces = 0

        for (local, entree) in manifeste.tout where connus[local] != entree.empreinte {
            // Un fichier qui échoue n'emporte pas les autres : le corpus est
            // fait de morceaux indépendants, et sept livres sur huit valent
            // mieux que rien.
            guard let octets = try? await telecharger(entree) else { continue }
            guard (try? ecrire(octets, vers: local)) != nil else { continue }
            remplaces += 1
        }

        if remplaces > 0 {
            try? enregistrerLesEmpreintes(depuis: manifeste)
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
    /// Il dit « voici ce que j'ai ». L'écrire avant reviendrait à le promettre :
    /// une coupure entre les deux laisserait l'app persuadée de posséder un
    /// livre qu'elle n'a pas, et elle ne le retéléchargerait jamais.
    private func enregistrerLesEmpreintes(depuis manifeste: Manifest) throws {
        let table = Dictionary(
            manifeste.tout.map { ($0.local, $0.entree.empreinte) },
            uniquingKeysWith: { premier, _ in premier }
        )
        try JSONEncoder().encode(table).write(to: registre, options: .atomic)
    }
}
