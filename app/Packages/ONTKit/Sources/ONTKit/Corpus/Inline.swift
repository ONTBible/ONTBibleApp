import Foundation

/// Un nœud du texte ONT.
///
/// Le CLAUDE.md §2.1 pose trois niveaux, et tout l'enjeu de la liseuse est de
/// ne jamais les aplatir :
///
/// - **niveau 1** — le corps de la traduction : `.text`, et `.term` pour les
///   intraduisibles qui restent en hébreu translittéré ;
/// - **niveau 2** — `.gloss`, la voix du projet, qui explicite ce que le
///   lecteur hébreu comprenait sans qu'on le lui dise ;
/// - **niveau 3** — `.translit`, la paire translittération + hébreu, et
///   `.hebrew` pour une séquence hébraïque isolée.
///
/// Les garder distincts, c'est ce qui rend les trois interrupteurs de lecture
/// gratuits : masquer un niveau, c'est ne pas émettre ses nœuds.
public enum Inline: Hashable, Sendable {
    case text(String)
    /// Un intraduisible. `lemma` est la clé qui ouvre sa fiche de lexique.
    case term(String, lemma: String)
    /// `(*chasdo* / חַסְדּוֹ)` — les deux parts sont séparées parce qu'elles ne se
    /// composent pas de la même façon : latine italique d'un côté, fonte
    /// hébraïque et direction RTL de l'autre.
    case translit(String, hebrew: String)
    /// Une séquence en écriture hébraïque rencontrée hors d'un `.translit`.
    case hebrew(String)
    case gloss([Inline])
    /// Une **accentuation** — ni corps ordinaire, ni intraduisible.
    ///
    /// La troisième catégorie, née d'un défaut : des mots mis en gras pour
    /// insister se retrouvaient déclarés intraduisibles, donc affichés en or
    /// et touchables, ouvrant une fiche de lexique vide. L'intention était
    /// juste, il lui manquait sa marque.
    ///
    /// Elle porte sa propre couleur et **ne se touche pas** : elle n'a pas de
    /// fiche, et un mot qui répond au doigt sans rien avoir à dire est pire
    /// qu'un mot qui ne répond pas.
    case accentuation([Inline])
    case emphasis([Inline])
    case link([Inline], href: String)
    /// Une coupure de ligne signifiante — le bloc de référence d'une feuille
    /// d'introduction empile ses champs ainsi.
    case lineBreak
}

// Le décodage vivait ici, et il n'y est plus.
//
// `Inline` portait son propre `init(from decoder:)` : le domaine savait donc
// lire le JSON du pipeline, et un champ renommé dans le vault se propageait
// jusqu'au cœur de l'app. C'est la dépendance à l'envers — le domaine ne doit
// rien connaître du monde extérieur.
//
// Elle vit maintenant dans `ONTData` : `ONTSchema.Inline` est engendré depuis
// `schema.rs` à chaque build, et `SchemaMapping.swift` le traduit vers ce
// type-ci. Le `switch` de cette traduction est exhaustif, donc **un type de
// nœud ajouté au pipeline casse la compilation de l'app**.

public extension [Inline] {
    /// Le texte nu, pour un titre, un résumé ou une recherche.
    ///
    /// Par défaut ne rend que le corps de la traduction — c'est la voix du
    /// texte, sans l'appareil.
    /// **Ce qui est omis laisse ses espaces derrière lui**, et il faut les
    /// reprendre. « Quand ⟦hébreu⟧ commença » devient « Quand  commença » avec
    /// deux espaces : le nœud disparaît, pas les espaces qui l'entouraient. En
    /// lecture ça ne se voit pas — le nœud est rendu ; ici, si.
    ///
    /// **Le repli se fait en écrivant, pas après.** Il a d'abord été une
    /// seconde passe sur le texte assemblé : deux chaînes entières allouées là
    /// où une suffit, et le calcul des ancres de position rappelle cette
    /// fonction sur tout un bloc à chaque évaluation. Mesuré à 0,28 ms pour
    /// trente versets — 3 % d'une image à 120 Hz, pour une réponse qu'on
    /// pouvait obtenir en un seul parcours.
    func plainText(gloss: Bool = false, level3: Bool = false) -> String {
        var repliage = Repliage()
        ecrire(dans: &repliage, gloss: gloss, level3: level3)
        return repliage.sortie
    }

    private func ecrire(dans repliage: inout Repliage, gloss: Bool, level3: Bool) {
        for node in self {
            switch node {
            case .text(let value):
                repliage.ajouter(value)
            case .term(let value, _):
                repliage.ajouter(value)
            case .hebrew(let value):
                if level3 { repliage.ajouter(value) }
            case .translit(let translit, let hebrew):
                if level3 { repliage.ajouter("(\(translit) / \(hebrew))") }
            case .gloss(let children):
                if gloss { children.ecrire(dans: &repliage, gloss: gloss, level3: level3) }
            case .emphasis(let children), .accentuation(let children), .link(let children, _):
                children.ecrire(dans: &repliage, gloss: gloss, level3: level3)
            case .lineBreak:
                repliage.ajouter("\n")
            }
        }
    }
}

/// Le repli des espaces, appliqué **au fil de l'écriture**.
///
/// Un espace n'est pas écrit quand il se présente : il est **retenu**, et c'est
/// ce qui le suit qui décide s'il sert d'espace ou s'il se perd. Un nœud ne sait
/// pas ce qui vient après lui — c'est pourquoi la décision ne peut pas se
/// prendre nœud par nœud, et pourquoi elle n'a pas non plus besoin d'une
/// seconde passe.
private struct Repliage {
    private(set) var sortie = ""
    private var espaceEnAttente = false

    /// Ce qui ne prend jamais d'espace devant, en français.
    ///
    /// Le point et la virgule, la parenthèse et le crochet fermants, les points
    /// de suspension. Le point-virgule, les deux-points, le point
    /// d'exclamation, l'interrogation et le chevron fermant en prennent un,
    /// eux — c'est la règle française, et le corpus l'applique déjà.
    ///
    /// La règle vaut quelle que soit l'origine de l'espace : une omission en
    /// laisse, mais un espace avant un point serait faux même écrit à la main.
    private static let sansEspaceDevant: Set<Character> = [".", ",", ")", "]", "…"]

    mutating func ajouter(_ morceau: String) {
        for caractere in morceau {
            switch caractere {
            case " ", "\t":
                espaceEnAttente = !sortie.isEmpty
            case "\n":
                espaceEnAttente = false
                while sortie.last == " " { sortie.removeLast() }
                sortie.append(caractere)
            default:
                if espaceEnAttente, sortie.last != "\n",
                    !Self.sansEspaceDevant.contains(caractere)
                {
                    sortie.append(" ")
                }
                espaceEnAttente = false
                sortie.append(caractere)
            }
        }
    }
}

public extension [Inline] {
    /// Tous les intraduisibles de l'arbre, dans l'ordre du texte.
    var lemmas: [String] {
        flatMap { node -> [String] in
            switch node {
            case .term(_, let lemma): [lemma]
            case .gloss(let children), .emphasis(let children), .accentuation(let children),
                .link(let children, _):
                children.lemmas
            default: []
            }
        }
    }
}
