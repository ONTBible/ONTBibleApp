import Foundation
import ONTKit

/// La forme des fichiers de `dist/sources/`, et sa traduction vers le domaine.
///
/// # ⚠︎ Ces DTO sont **écrits à la main**
///
/// `Schema.swift` est engendré depuis `pipeline/src/schema.rs` : un champ
/// renommé là-bas casse la compilation ici, en nommant le fichier et la ligne.
/// **Ce n'est pas le cas de cette couche-ci.** Le codegen ne couvre pas
/// `pipeline/src/sources.rs`, et rien ne garantit donc que ce fichier suive.
///
/// Un nom de champ qui dérive ne casserait pas la compilation : il ferait
/// décoder `nil` là où il y avait une valeur, et la feuille de référence
/// s'ouvrirait vide — ou, pire, sans les mots touchables, ce qui se lit
/// exactement comme un témoin qui n'étiquette pas.
///
/// C'est pourquoi `SourcesDuBundleTests` décode le **vrai fichier émis** et
/// vérifie des valeurs connues. Elle est le seul garde-fou de cette couche, et
/// elle a été éprouvée : un champ renommé la fait rougir.
///
/// # La source de vérité
///
/// `pipeline/src/sources.rs` — `ManifesteSources`, `TemoinPublie`,
/// `LivrePublie`, `FichierPublie`, `LivreSources`, `VersetPublie`, `MotPublie`.
///
/// ```text
/// sources/manifeste.json          les témoins, leurs crédits, les empreintes
/// sources/<témoin>/<livre>.json   un fichier par livre et par témoin
/// ```
public enum ONTSources {
    /// `sources/manifeste.json`.
    public struct Manifeste: Decodable, Sendable {
        public let schema: Int
        /// L'estampille de la génération — la date du dernier commit du
        /// vault, **la même valeur au caractère près** que le `generatedAt`
        /// du manifeste du corpus sorti du même passage. Jamais un `now()` :
        /// deux exécutions sur le même vault doivent produire le même octet.
        ///
        /// Absente tant que `ONT_GENERE` n'est pas posé (émise par la
        /// #286 depuis `config::genere`, « vide plutôt que fausse ») — et
        /// `SourcesUpdater` refuse alors, car un manifeste sans date n'est
        /// pas prouvable plus récent.
        public let genere: String?
        public let temoins: [String: Temoin]
        public let livres: [String: Livre]
    }

    public struct Temoin: Decodable, Sendable {
        public let nom: String
        public let langue: String
        public let attribution: String
        public let degre: String?
    }

    public struct Livre: Decodable, Sendable {
        /// Vide quand aucun témoin ne porte ce livre — et alors `transmission`
        /// doit parler. C'est le cas de six livres sur sept aujourd'hui.
        public let temoins: [String: Fichier]
        public let transmission: String?
        /// Écrit **en français et accentué** — « témoin », « fichier ». Le
        /// pipeline émet la chaîne telle quelle, sans `rename` ; un décodage qui
        /// attendrait « temoin » sans accent trouverait toujours `nil` et
        /// perdrait la nuance sans qu'aucune erreur ne le dise.
        public let cause: String?
        /// Les divergences entre **éditions imprimées** — pas encore lues par la
        /// liseuse. Déclaré pour mémoire : un champ ignoré ne coûte rien, et
        /// l'omettre ferait croire qu'il n'existe pas.
        public let editions: Fichier?
    }

    public struct Fichier: Decodable, Sendable {
        /// Le chemin **relatif à la racine du corpus** — `sources/he-wlc/bereshit.json`.
        /// C'est le manifeste qui dit où est le fichier ; le recomposer à partir
        /// du témoin et du livre serait réécrire une convention qu'on ne
        /// contrôle pas.
        public let chemin: String
        public let octets: Int
        public let sha256: String
    }

    /// `sources/<témoin>/<livre>.json`.
    public struct LivreSources: Decodable, Sendable {
        public let temoin: String
        /// Unité ONT → ses versets, **dans l'ordre**. L'ordre du tableau est la
        /// donnée ; `n` ne l'est pas.
        public let unites: [String: [Verset]]
    }

    public struct Verset: Decodable, Sendable {
        /// Le numéro à afficher. **Pas une clé** — il se répète.
        public let n: Int
        public let t: String
        /// Absent quand le témoin n'étiquette pas : `skip_serializing_if` côté
        /// pipeline, donc un tableau vide par défaut ici.
        public let mots: [Mot]

        enum CodingKeys: String, CodingKey {
            case n, t, mots
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            n = try c.decode(Int.self, forKey: .n)
            t = try c.decode(String.self, forKey: .t)
            mots = try c.decodeIfPresent([Mot].self, forKey: .mots) ?? []
        }
    }

    public struct Mot: Decodable, Sendable {
        public let t: String
        public let lem: String?
        public let morph: String?
        /// La translittération que le vault a écrite pour cette forme.
        ///
        /// `skip_serializing_if` côté pipeline — `MotPublie.translit` : la clé
        /// est simplement **absente** pour deux mots sur trois, ce que
        /// `decodeIfPresent` du décodeur synthétisé traite déjà.
        public let translit: String?
        /// La fiche ONT que ce mot ouvre. **Le même type que le niveau 3 du
        /// corpus** — `{"t":"term","lemma":"bara"}` —, et c'est voulu : le
        /// pipeline réemploie `CibleDuNiveauTrois`, donc la liseuse réemploie le
        /// DTO engendré. Deux décodeurs pour une même forme finiraient par
        /// diverger.
        public let cible: ONTSchema.CibleDuNiveauTrois?
    }
}

// MARK: - La forme du fichier devient le domaine

extension ONTKit.Temoin {
    /// `cle` ne vit pas dans l'objet du manifeste : c'est la clé du
    /// dictionnaire qui le porte. Elle entre donc ici.
    init(cle: String, _ dto: ONTSources.Temoin) {
        self.init(
            cle: cle,
            nom: dto.nom,
            langue: Langue(code: dto.langue),
            attribution: dto.attribution,
            degre: dto.degre
        )
    }
}

extension CauseDeLAbsence {
    init(_ brut: String) {
        switch brut {
        case "témoin": self = .temoin
        case "fichier": self = .fichier
        default: self = .autre(brut)
        }
    }
}

extension MotSource {
    /// `rang` vient de la **position** dans le tableau, pas du DTO : le fichier
    /// ne le porte pas, et c'est l'ordre qui fait l'identité.
    init(rang: Int, _ dto: ONTSources.Mot) {
        self.init(
            rang: rang,
            texte: dto.t,
            lemme: dto.lem,
            morphologie: dto.morph,
            translitteration: dto.translit,
            cible: dto.cible.map(CibleDuNiveauTrois.init)
        )
    }
}

extension VersetSource {
    init(rang: Int, _ dto: ONTSources.Verset) {
        self.init(
            rang: rang,
            numero: dto.n,
            texte: dto.t,
            mots: dto.mots.enumerated().map(MotSource.init)
        )
    }
}

extension ONTSources.Manifeste {
    /// Ce que le domaine sait d'un livre.
    ///
    /// **`temoins` vide devient `.aucune`**, et c'est tout l'intérêt du type
    /// somme : au-delà d'ici, la liste vide n'existe plus, et personne ne peut
    /// oublier de la tester.
    ///
    /// L'ordre des témoins est celui des clés triées. Le pipeline émet une
    /// `BTreeMap`, donc un ordre stable ; un dictionnaire Swift ne l'est pas, et
    /// sans ce tri la feuille de référence changerait d'ordre à chaque
    /// lancement.
    func sources(livre: String) -> SourcesDuLivre {
        guard let entree = livres[livre] else {
            return .aucune(nil)
        }
        let cles = entree.temoins.keys.sorted()
        guard !cles.isEmpty else {
            return .aucune(
                entree.transmission.map {
                    Transmission(explication: $0, cause: entree.cause.map(CauseDeLAbsence.init))
                }
            )
        }
        return .temoins(cles.compactMap { cle in
            temoins[cle].map { ONTKit.Temoin(cle: cle, $0) }
        })
    }
}

extension ONTSources.LivreSources {
    /// Le texte d'une unité, traduit une fois le témoin connu.
    func unite(_ id: String, temoin: ONTKit.Temoin) -> UniteSource? {
        guard let versets = unites[id] else { return nil }
        return UniteSource(
            temoin: temoin,
            unite: id,
            versets: versets.enumerated().map(VersetSource.init)
        )
    }
}


// MARK: - Le socle : les sources du bundle

/// Les langues sources embarquées avec l'app.
///
/// ## Ce que le bundle porte, et ce qu'il ne porte pas
///
/// **L'hébreu seul.** `scripts/corpus.sh` recopie `manifeste.json` et le dossier
/// `he-wlc`, nommément, et rien d'autre — décision de l'auteur du 11 septembre
/// 2026. L'hébreu n'est pas une langue source parmi d'autres : c'est celle de la
/// quasi-totalité du corpus, celle qu'on ouvre en touchant un verset. La mettre
/// à la demande reviendrait à mettre la fonctionnalité à la demande.
///
/// Le grec, le guèze et le latin sont donc **annoncés par le manifeste sans
/// être présents**. C'est un état normal, et c'est pourquoi
/// `unite(livre:temoin:unite:)` rend `nil` plutôt que de lever.
///
/// ## Pourquoi `BundleLoader` ne sert pas ici
///
/// Il préfixe tout par `data/`, et c'était juste tant que tout passait par
/// `buildPhase: resources` — une phase de ressources **aplatit**
/// l'arborescence, `data/books/bereshit.json` devient `bereshit.json` à la
/// racine du paquet.
///
/// Les langues sources ont brisé ça le 11 septembre 2026 : `he-wlc/bereshit.json`
/// porte **le même nom de base** que le livre, et Xcode refuse de produire deux
/// fois le même fichier. `project.yml` les fait donc entrer en **référence de
/// dossier**, qui préserve les chemins — et le dossier atterrit à la racine des
/// ressources, sous `sources/`, *sans* `data/` devant.
///
/// Mesuré dans le paquet construit, pas déduit : `sources/he-wlc/bereshit.json`
/// niché, `bereshit.json` à plat, les deux côte à côte.
///
/// ## Et il en sort un invariant commode
///
/// > Le `chemin` du manifeste vaut des deux côtés.
///
/// `sources/he-wlc/bereshit.json` désigne le fichier aussi bien sous la racine
/// du corpus téléchargé que sous la racine des ressources du paquet. Disque et
/// bundle lisent donc la **même** chaîne, et il n'y a pas deux conventions à
/// tenir d'accord.
///
/// `@unchecked Sendable` assumé, comme les voisins : les caches sont protégés
/// par un verrou et le contenu décodé est immuable.
public final class BundleSourcesRepository: SourcesRepository, @unchecked Sendable {
    private let bundle: Foundation.Bundle
    private let lock = NSLock()
    private var manifesteCharge = false
    private var manifeste: ONTSources.Manifeste?
    /// Par **chemin**, pas par livre : un livre a plusieurs témoins, et le
    /// chemin est justement la clé qui les distingue.
    private var fichiers: [String: ONTSources.LivreSources] = [:]

    public init(bundle: Foundation.Bundle = .main) {
        self.bundle = bundle
    }

    public func sources(livre: String) -> SourcesDuLivre {
        lock.lock()
        defer { lock.unlock() }
        return leManifeste()?.sources(livre: livre) ?? .aucune(nil)
    }

    public func unite(livre: String, temoin cle: String, unite id: String) -> UniteSource? {
        lock.lock()
        defer { lock.unlock() }

        guard let manifeste = leManifeste(),
            let chemin = manifeste.livres[livre]?.temoins[cle]?.chemin,
            let dto = manifeste.temoins[cle]
        else { return nil }
        return leFichier(chemin)?.unite(id, temoin: Temoin(cle: cle, dto))
    }

    /// À appeler **le verrou tenu**.
    private func leManifeste() -> ONTSources.Manifeste? {
        if manifesteCharge { return manifeste }
        manifesteCharge = true
        manifeste = lire("sources/manifeste.json")
        return manifeste
    }

    /// À appeler **le verrou tenu**.
    private func leFichier(_ chemin: String) -> ONTSources.LivreSources? {
        if let cache = fichiers[chemin] { return cache }
        guard let charge: ONTSources.LivreSources = lire(chemin) else { return nil }
        fichiers[chemin] = charge
        return charge
    }

    /// Lit un fichier niché du paquet, ou rend `nil`.
    ///
    /// **Jamais de repli à plat.** `BundleLoader` en a un — faute de trouver
    /// `data/x/bereshit.json`, il cherche `bereshit.json` à la racine. Ici ce
    /// repli tomberait sur le **livre ONT** du même nom : un fichier qui existe,
    /// qui se lit, et qui n'est pas ce qu'on demandait.
    private func lire<T: Decodable>(_ chemin: String) -> T? {
        guard let (dossier, nom) = BundleSourcesRepository.decouper(chemin),
            let url = bundle.url(forResource: nom, withExtension: "json", subdirectory: dossier),
            let octets = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: octets)
    }

    /// `sources/he-wlc/bereshit.json` → (`sources/he-wlc`, `bereshit`).
    ///
    /// Foundation veut un sous-dossier et un nom sans extension ; le manifeste,
    /// lui, donne un chemin entier. La découpe est ici plutôt qu'aux deux points
    /// d'appel, parce qu'elle se tromperait deux fois.
    ///
    /// Un chemin sans dossier rend `nil` : il désignerait la racine du paquet,
    /// là où le repli à plat ferait exactement le dégât qu'on vient d'écarter.
    static func decouper(_ chemin: String) -> (dossier: String, nom: String)? {
        let morceaux = chemin.split(separator: "/").map(String.init)
        guard let dernier = morceaux.last, morceaux.count > 1 else { return nil }
        let nom = dernier.hasSuffix(".json") ? String(dernier.dropLast(5)) : dernier
        return (morceaux.dropLast().joined(separator: "/"), nom)
    }
}
