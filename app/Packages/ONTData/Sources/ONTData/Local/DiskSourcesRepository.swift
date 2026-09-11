import Foundation
import ONTKit

/// Les langues sources, lues du disque quand elles y sont, du bundle sinon.
///
/// ## Le même montage que le corpus, et pour la même raison
///
/// Le bundle n'est pas un repli, c'est le socle : il porte l'hébreu, et il fait
/// marcher une installation neuve avant tout réseau. Ce qui se télécharge vient
/// le **recouvrir**, fichier par fichier. Il n'y a donc aucun état
/// intermédiaire invalide : à tout instant, chaque témoin est lisible dans
/// l'une ou l'autre version, jamais dans aucune.
///
/// ## Le manifeste se recouvre **en entier**, jamais par moitié
///
/// C'est la seule différence avec `DiskCorpusRepository`, et elle compte. Le
/// manifeste local dit à la fois *quels témoins existent* et *où sont leurs
/// fichiers*. Mélanger un manifeste du disque avec des fichiers du bundle —
/// ou l'inverse — ferait chercher un chemin qu'un des deux ne connaît pas.
///
/// Donc : si `sources/manifeste.json` est sur le disque, **tout** se lit du
/// disque et le bundle ne répond plus ; sinon, tout vient du socle. La
/// bascule est d'un bloc.
///
/// ## Le témoin se charge à la demande
///
/// `he-wlc/bereshit.json` pèse 476 Ko, et la plupart des lecteurs n'ouvriront
/// jamais la feuille de référence. Le manifeste, lui, fait deux kilo-octets :
/// il se charge dès qu'on demande si un livre a des sources, le texte seulement
/// quand on demande à le voir. Un cache par fichier, comme les voisins.
///
/// ## Ce que le téléchargeur n'apporte pas encore
///
/// `CorpusUpdater.Manifest.tout` nomme six fichiers et les livres ; **il ignore
/// `sources/`**. Rien n'écrit donc ces fichiers sur le disque aujourd'hui, et
/// ce dépôt lit de fait le bundle. Ce n'est pas une raison pour lire le bundle
/// en dur : le mode développeur du Mac reconstruit le corpus depuis le vault et
/// le fait regarder par `regarder(_:)` — c'est ce chemin-là qui sert dès
/// maintenant, et c'est celui-là même qui avait manqué au corpus (l'auteur
/// voyait « 45 » affiché sur un chapitre que la liseuse n'ouvrait pas).
///
/// `@unchecked Sendable` assumé : les caches sont protégés par un verrou et le
/// contenu décodé est immuable.
public final class DiskSourcesRepository: SourcesRepository, @unchecked Sendable {
    private var dossier: URL
    private let socle: any SourcesRepository
    private let lock = NSLock()
    private var manifesteCharge = false
    private var manifeste: ONTSources.Manifeste?
    /// Par **chemin**, pas par livre : un livre a plusieurs témoins, et le
    /// chemin est justement la clé qui les distingue.
    private var fichiers: [String: ONTSources.LivreSources] = [:]

    public init(
        dossier: URL = CorpusUpdater.dossierParDefaut(),
        socle: any SourcesRepository = BundleSourcesRepository()
    ) {
        self.dossier = dossier
        self.socle = socle
    }

    public func sources(livre: String) -> SourcesDuLivre {
        lock.lock()
        guard let manifeste = leManifeste() else {
            // Le verrou est rendu **avant** d'appeler le socle. Le garder
            // exposerait à un interblocage le jour où le socle voudrait, lui
            // aussi, verrouiller quelque chose — c'est la leçon de
            // `DiskGlossaryRepository.occurrences(of:)`.
            lock.unlock()
            return socle.sources(livre: livre)
        }
        defer { lock.unlock() }
        return manifeste.sources(livre: livre)
    }

    public func unite(livre: String, temoin cle: String, unite id: String) -> UniteSource? {
        lock.lock()
        guard let manifeste = leManifeste() else {
            lock.unlock()
            return socle.unite(livre: livre, temoin: cle, unite: id)
        }
        defer { lock.unlock() }

        guard let chemin = manifeste.livres[livre]?.temoins[cle]?.chemin,
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

    /// Lit un fichier du disque, ou rend `nil`.
    ///
    /// **Aucune erreur ne remonte**, et c'est délibéré : un fichier absent est
    /// le cas normal — ce témoin n'a pas été téléchargé — et un fichier
    /// illisible ne doit pas empêcher de lire le reste.
    private func lire<T: Decodable>(_ chemin: String) -> T? {
        guard let octets = try? Data(contentsOf: dossier.appendingPathComponent(chemin)) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: octets)
    }

    /// Oublie ce qui est en mémoire, après une mise à jour.
    public func oublier() {
        lock.lock()
        defer { lock.unlock() }
        manifesteCharge = false
        manifeste = nil
        fichiers.removeAll()
    }

    /// **Change la source, sans changer le dépôt.**
    ///
    /// Voir `DiskCorpusRepository.regarder(_:)` : les langues sources suivent le
    /// corpus, sans quoi l'aperçu du Mac montrerait l'hébreu d'un autre texte.
    ///
    /// On vide les caches dans le même verrou : les rendre séparément laisserait
    /// une fenêtre où le dossier est neuf et le contenu ancien.
    public func regarder(_ nouveau: URL) {
        lock.lock()
        defer { lock.unlock() }
        dossier = nouveau
        manifesteCharge = false
        manifeste = nil
        fichiers.removeAll()
    }
}
