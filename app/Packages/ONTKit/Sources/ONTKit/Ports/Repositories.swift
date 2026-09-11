import Foundation

/// Les ports — ce que le domaine attend du monde extérieur.
///
/// Un protocole par responsabilité, et non un gros objet qui saurait tout
/// faire. C'est ce qui permet à une vue de déclarer exactement ce dont elle a
/// besoin, et à un test de fournir une doublure de trois lignes plutôt qu'un
/// bundle complet.

// MARK: - Corpus

/// L'accès au texte.
public protocol CorpusRepository: Sendable {
    /// L'arborescence des 70 slots — assez légère pour le lancement.
    func corpora() throws -> [Corpus]
    /// Le contenu complet d'un livre, chargé à la demande.
    func book(_ id: String) throws -> Book
}

extension CorpusRepository {
    /// Tous les livres, dans l'ordre canonique des slots.
    public func allBooks() -> [BookOutline] {
        ((try? corpora()) ?? []).flatMap { corpus in
            corpus.modes.sorted { $0.order < $1.order }.flatMap(\.books)
        }
    }

    /// Les seuls livres qui portent du texte aujourd'hui.
    public func writtenBooks() -> [BookOutline] {
        allBooks().filter { !$0.empty }
    }

    /// Une unité précise, introduction comprise.
    public func chapter(book bookId: String, id chapterId: String) -> Chapter? {
        guard let book = try? book(bookId) else { return nil }
        if book.intro?.id == chapterId { return book.intro }
        return book.chapters.first { $0.id == chapterId }
    }
}

// MARK: - Lexique

/// L'accès au glossaire des intraduisibles.
public protocol GlossaryRepository: Sendable {
    func entries() throws -> [GlossaryEntry]
    /// Les passages où un lemme paraît.
    func occurrences(of lemma: String) -> [Occurrence]
}

/// Les fiches des **Shemot**.
///
/// **Un port distinct de `GlossaryRepository`**, et pas par symétrie : les deux
/// populations vivent dans deux fichiers, et un port commun ferait chercher un
/// nom propre dans le glossaire — où il n'est pas, et où la jointure échouerait
/// sans rien dire.
public protocol ShemotRepository: Sendable {
    func entries() throws -> [ShemEntry]
}

// MARK: - Les langues sources

/// L'accès au texte dans sa langue d'origine.
///
/// ## Pourquoi un port de plus, et non deux méthodes sur `CorpusRepository`
///
/// Parce que le poids n'est pas le même, et que le moment de lecture non plus.
/// Le corpus arrive au lancement ; un témoin, lui, ne se charge que si le
/// lecteur demande à voir la référence — `he-wlc/bereshit.json` pèse 476 Ko à
/// lui seul, et la plupart des lecteurs n'ouvriront jamais cette feuille. Le
/// mêler au corpus ferait payer ce prix à tout le monde, widget compris.
///
/// ## Deux méthodes, et la coupure entre elles est le manifeste
///
/// `sources(livre:)` ne lit que le manifeste — quelques kilo-octets, la liste
/// des témoins et leurs crédits. `unite(livre:temoin:unite:)` ouvre le fichier
/// du témoin. Un écran qui veut seulement dire « ce livre existe en hébreu et
/// en grec » n'a donc rien de lourd à charger.
///
/// ## Rien ne lève
///
/// L'absence est le cas ordinaire à tous les étages : six des sept livres du
/// manifeste n'ont aucun témoin, et un témoin annoncé peut ne pas être embarqué
/// — l'app ne livre que l'hébreu, le reste se télécharge. Faire lever ces cas
/// obligerait chaque appelant à traiter en erreur ce qui est un état normal.
public protocol SourcesRepository: Sendable {
    /// Les témoins d'un livre, ou ce qu'on dit quand il n'y en a pas.
    /// Ne lit que le manifeste — aucun texte n'est chargé.
    func sources(livre: String) -> SourcesDuLivre

    /// Le texte d'une unité chez un témoin, **chargé à la demande**.
    ///
    /// `nil` quand ce témoin ne porte pas ce livre, quand son fichier n'est ni
    /// sur le disque ni dans le bundle, ou quand l'unité n'y figure pas.
    func unite(livre: String, temoin: String, unite: String) -> UniteSource?
}

extension SourcesRepository {
    /// Le texte d'une unité chez **tous** ses témoins, dans l'ordre du
    /// manifeste. Les témoins introuvables sont omis, sans bruit.
    public func unite(livre: String, unite id: String) -> [UniteSource] {
        sources(livre: livre).temoinsDisponibles.compactMap {
            unite(livre: livre, temoin: $0.cle, unite: id)
        }
    }

    /// **La question que cette couche existe pour répondre** : pour telle unité
    /// et telle position, le texte source de chaque témoin disponible.
    ///
    /// `rang` est une **position**, jamais un numéro affiché — voir
    /// `UniteSource.verset(rang:)`. Un témoin qui n'a pas de verset à cette
    /// position est simplement absent du résultat : les témoins ne comptent pas
    /// toujours pareil, et l'Apocalypse 12 porte 18 versets au SBLGNT contre 17
    /// au byzantin.
    public func verset(livre: String, unite id: String, rang: Int) -> [VersetChezUnTemoin] {
        unite(livre: livre, unite: id).compactMap { source in
            source.verset(rang: rang).map { VersetChezUnTemoin(temoin: source.temoin, verset: $0) }
        }
    }
}

// MARK: - Recherche

/// L'index de recherche.
public protocol SearchIndex: Sendable {
    func records() -> [SearchRecord]
}

// MARK: - Ce que le lecteur produit

/// Les surlignages et les notes.
public protocol HighlightRepository: AnyObject {
    /// Ce qui se **montre** — les pierres tombales en sont exclues.
    func all() -> [Highlight]
    /// Ce qui se **synchronise** — pierres tombales comprises.
    ///
    /// Deux méthodes et non une, parce que les deux besoins sont opposés : une
    /// liste d'annotations ne doit pas afficher ce qui est supprimé, et un
    /// envoi qui omettrait les suppressions les perdrait.
    func allForSync() -> [Highlight]
    func highlight(chapterId: String, verse: Int) -> Highlight?
    func save(_ highlight: Highlight)
    func remove(_ highlight: Highlight)
}

/// La position de lecture.
public protocol PositionRepository: AnyObject {
    var position: ReadingPosition? { get }
    func remember(_ position: ReadingPosition)
}

/// Les réglages de lecture.
public protocol PreferencesRepository: AnyObject {
    var preferences: ReadingPreferences { get set }
}

/// Le vivier du verset du jour.
///
/// Un port à part et non une méthode de `CorpusRepository` : le widget n'a
/// besoin que de celui-ci, et lui donner accès au corpus entier l'obligerait à
/// charger un arbre de 750 Ko pour afficher trois lignes.
public protocol DailyVerseRepository: Sendable {
    func pool() -> [DailyVerse]
}

/// Le profil du lecteur.
///
/// Un port à part et non un champ des réglages : le profil se **supprime**
/// avec le compte, là où les réglages de lecture survivent à une
/// déconnexion. Les mêmes données dans le même dépôt finiraient par partir
/// ensemble, ou par rester ensemble — et l'une des deux serait fausse.
public protocol ProfilRepository: AnyObject {
    var profil: Profil { get set }
    /// Écrit le portrait et rend le nom du fichier.
    func enregistrerLePortrait(_ donnees: Data) throws -> String
    /// Les octets du portrait, ou `nil` s'il n'y en a pas.
    func portrait() -> Data?
    /// Tout effacer — appelé par l'effacement du compte.
    func oublier()
}

// MARK: - La prononciation

/// La feuille qui explique comment lire ce qui est écrit.
///
/// ## Pourquoi un port et non une constante
///
/// Le texte vit dans le vault — `lexique/prononciation.md` — et se relit comme
/// le reste du corpus. L'écrire dans l'app en ferait une seconde source, qui
/// divergerait à la première correction et que personne ne penserait à
/// remettre à jour.
///
/// Elle peut être **absente** : le pipeline n'écrit rien quand le vault ne la
/// porte pas, et l'écran dit alors ce qu'il attend au lieu de faire croire à
/// une panne.
public protocol PrononciationRepository: Sendable {
    func feuille() -> FeuilleDePrononciation?
}

/// Le titre et le corps de la feuille.
///
/// Des `Block`, jamais du markdown : la feuille cite `chokhmah`, `malʾakh` et
/// `Chanokh`, et c'est le rendu du corpus qui les pose en or et en terre
/// brûlée, touchables, sans une ligne de code de plus.
public struct FeuilleDePrononciation: Hashable, Sendable {
    public let titre: String
    public let blocs: [Block]

    public init(titre: String, blocs: [Block]) {
        self.titre = titre
        self.blocs = blocs
    }
}

// MARK: - Les chuqqot

/// Une **chuqqah** — un énoncé permanent de l'ontologie hébraïque.
///
/// De *chaqaq* (חָקַק), graver dans la pierre : ce qui est gravé tient de
/// soi-même, et le reste s'y appuie. Ni une opinion qu'on défend, ni un
/// commentaire qui accompagne un texte.
///
/// ## Pourquoi un type du domaine et non la fiche de lexique
///
/// Les deux portent des `Block`, et la tentation de les confondre est réelle.
/// Une fiche explique **un mot** et se consulte ; une chuqqah énonce **une
/// règle du fonctionnement** et se lit d'un bout à l'autre. C'est ce qui décide
/// de leur place à l'écran — une feuille pour l'une, une page pour l'autre — et
/// donc de leur type.
///
/// Réutiliser `GlossaryEntry` aurait coûté un `lemma` inventé, un `count` faux
/// et un `hebrew` vide : trois champs qui mentent, et qui se paieraient à la
/// première colonne qu'on ajoute à l'un des deux.
///
/// ## Ce que ce type ne porte pas, et c'est délibéré
///
/// **Aucun `Status`.** La garde vit dans le pipeline : une chuqqah en brouillon
/// n'entre jamais dans `dist/chuqqot.json` — décision de l'auteur du 9 septembre
/// 2026, parce qu'un énoncé permanent « en attente de validation » se contredit
/// lui-même. Un champ qui ne peut prendre qu'une valeur invite à l'autre.
public struct Chuqqah: Hashable, Sendable, Identifiable {
    /// Le nom du fichier, slugifié — `les-quatre-modes-de-presence`.
    ///
    /// C'est aussi son adresse sur le site, `/fr/chuqqot/{id}` : elle ne se
    /// renomme pas à la légère.
    public let id: String
    /// Le titre, lu de la ligne `# ` du fichier du vault.
    public let titre: String
    /// L'ordre de lecture. `chuqqot-0-intro` ouvre la série.
    ///
    /// **Un `Int` et non la position dans le tableau.** Le pipeline trie déjà
    /// ce qu'il émet, et l'app pourrait donc s'en remettre à l'ordre reçu. Elle
    /// ne le fait pas : un tri qu'on ne peut pas refaire est un tri qu'on ne
    /// peut pas vérifier, et l'épreuve qui garantit que l'introduction passe
    /// devant n'aurait plus rien à mesurer.
    public let rang: Int
    /// Le corps, en blocs de corpus.
    ///
    /// Des `Block`, jamais du markdown : une chuqqah cite `ʿolam`, `kavod`,
    /// `malʾakh`. C'est le rendu du corpus qui les pose en or et en terre
    /// brûlée, **touchables**, sans une ligne de code de plus ici.
    public let blocs: [Block]

    public init(id: String, titre: String, rang: Int, blocs: [Block]) {
        self.id = id
        self.titre = titre
        self.rang = rang
        self.blocs = blocs
    }
}

/// Ce qui donne accès aux chuqqot.
///
/// ## Pourquoi un port, et un port qui ne lève pas
///
/// Le texte vit dans le vault et se relit comme le reste du corpus ; l'écrire
/// dans l'app en ferait une seconde source, qui divergerait à la première
/// correction. C'est la même raison que pour la feuille de prononciation.
///
/// **Rien ne lève, et rien n'est optionnel.** Une liste vide est la réponse
/// normale aujourd'hui — les sept chuqqot écrites sont en brouillon, et la
/// garde du pipeline les retient. Distinguer « vide » de « absent » par un
/// `throws` ou un `nil` obligerait chaque appelant à trancher un cas qui ne
/// change rien à ce qu'il affiche : dans les deux cas, il n'y a rien à lire.
/// C'est à l'écran de dire *pourquoi* il n'y a rien, et il le dit en toutes
/// lettres.
public protocol ChuqqotRepository: Sendable {
    /// Les chuqqot publiées, **dans l'ordre de lecture**.
    func chuqqot() -> [Chuqqah]
}
