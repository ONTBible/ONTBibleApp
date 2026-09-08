import Foundation
import ONTKit
import Observation

/// Le modèle du lexique.
///
/// Ne dépend que de `GlossaryRepository` : la feature n'a aucune raison de
/// pouvoir lire le corpus, et ne le peut donc pas.
@MainActor
@Observable
public final class LexiconModel {
    private let glossary: any GlossaryRepository
    private let shemot: any ShemotRepository
    private let feuilles: any PrononciationRepository

    /// Le dépôt lui-même, pour la feuille — elle recharge la fiche entière,
    /// définition comprise, et n'a que faire de la liste allégée.
    public var depotDesNoms: any ShemotRepository { shemot }

    public private(set) var entries: [GlossaryEntry] = []
    private var byLemma: [String: GlossaryEntry] = [:]

    /// Les fiches des noms propres — **273 contre 61 termes**.
    ///
    /// Elles vivent dans `shemot.json`, un port à part et une feuille à part :
    /// un Shem désigne un porteur, un terme désigne un concept. Le Lexique les
    /// montre côte à côte parce qu'un lecteur qui cherche un mot ne sait pas
    /// d'avance dans quelle couche il tombe — mais il ne les mélange pas.
    public private(set) var noms: [ShemEntry] = []

    /// La feuille de prononciation, ou `nil` tant que le vault ne la porte pas.
    ///
    /// Lue une fois comme le reste : elle change quand le corpus change, et
    /// `recharger()` la reprend avec lui.
    public private(set) var prononciation: FeuilleDePrononciation?

    public init(
        glossary: any GlossaryRepository,
        shemot: any ShemotRepository,
        feuilles: any PrononciationRepository
    ) {
        self.glossary = glossary
        self.shemot = shemot
        self.feuilles = feuilles
        load()
    }

    private func load() {
        entries = (try? glossary.entries()) ?? []
        noms = (try? shemot.entries()) ?? []
        prononciation = feuilles.feuille()
        byLemma = Dictionary(entries.map { ($0.lemma, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// À appeler quand le lexique sur disque a changé.
    ///
    /// `entries` est chargé une fois, à la construction. Une entrée corrigée en
    /// cours de route restait donc invisible jusqu'au lancement suivant, alors
    /// même qu'elle était déjà écrite sur le disque.
    public func glossaryChanged() {
        load()
    }

    public func entry(_ lemma: String) -> GlossaryEntry? { byLemma[lemma] }

    /// Les passages où un intraduisible paraît.
    ///
    /// `bodyOnly` répond à « où ce mot est dans le texte », par opposition à
    /// « où on l'explique » — deux questions distinctes (§2.1), et la fiche
    /// doit pouvoir poser l'une sans l'autre.
    public func occurrences(_ lemma: String, bodyOnly: Bool) -> [Occurrence] {
        let all = glossary.occurrences(of: lemma)
        return bodyOnly ? all.filter { $0.level == .body } : all
    }

    /// Le filtre du catalogue.
    public enum Scope: String, CaseIterable, Sendable {
        case tagged = "Intraduisibles"
        case fixed = "Vocabulaire fixé"
        case all = "Tout"
        case shemot = "Shemot"

        // **« Tout » avait été retiré, puis rendu.**
        //
        // Je l'avais ôté au motif qu'il mentait : il montre toutes les entrées
        // de glossaire, donc pas les Shemot, qui vivent dans un autre fichier.
        // Gloire l'a redemandé, et il a raison — lu à sa place, entre
        // « Vocabulaire fixé » et « Shemot », il se comprend comme **tout le
        // vocabulaire**, ce qui est exact. Les deux premiers segments en sont
        // les parts ; le quatrième est une autre espèce.
        //
        // Retirer une porte parce que son nom pourrait s'entendre de travers
        // coûte plus que de laisser l'ordre l'expliquer.

        /// Vrai quand ce cas montre des **noms propres** et non des termes.
        ///
        /// La distinction ne tient pas au filtre mais à ce qu'on affiche : deux
        /// types différents, deux rangées différentes, deux feuilles
        /// différentes. Un booléen ici évite de disperser le `switch` dans la
        /// vue.
        public var montreLesNoms: Bool { self == .shemot }
    }

    /// Les Shemot que la recherche laisse passer.
    ///
    /// Même repli d'accents et de casse que pour les termes : on cherche
    /// « Michel » et on trouve `Mikhaʾel`.
    public func nomsFiltres(search: String) -> [ShemEntry] {
        guard !search.isEmpty else { return noms }
        let needle = search.folding(
            options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return noms.filter { nom in
            [nom.title, nom.lemma].contains { champ in
                champ.folding(
                    options: [.diacriticInsensitive, .caseInsensitive], locale: .current
                ).contains(needle)
            }
        }
    }

    public func filtered(scope: Scope, search: String) -> [GlossaryEntry] {
        let pool = switch scope {
        case .tagged: entries.filter(\.tagged)
        case .fixed: entries.filter { !$0.tagged }
        case .all: entries
        // Les Shemot ne passent pas par ici : ce sont des `ShemEntry`, pas des
        // entrées de glossaire. `nomsFiltres` répond pour eux.
        case .shemot: [GlossaryEntry]()
        }

        guard !search.isEmpty else { return pool }
        let needle = search.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: .current
        )

        return pool.filter { entry in
            [entry.title, entry.lemma, entry.rendering ?? "", entry.hebrew ?? "",
             entry.forms.joined(separator: " ")]
                .joined(separator: " ")
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .contains(needle)
        }
    }
}
