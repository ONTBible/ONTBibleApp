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
    /// Un terme **important** — ni corps ordinaire, ni intraduisible.
    ///
    /// La troisième catégorie, née d'un défaut : des mots mis en gras pour
    /// insister se retrouvaient déclarés intraduisibles, donc affichés en or
    /// et touchables, ouvrant une fiche de lexique vide. L'intention était
    /// juste, il lui manquait sa marque.
    ///
    /// Il porte sa propre couleur et **ne se touche pas** : il n'a pas de
    /// fiche, et un mot qui répond au doigt sans rien avoir à dire est pire
    /// qu'un mot qui ne répond pas.
    case important([Inline])
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
    func plainText(gloss: Bool = false, level3: Bool = false) -> String {
        reduce(into: "") { output, node in
            switch node {
            case .text(let value):
                output += value
            case .term(let value, _):
                output += value
            case .hebrew(let value):
                if level3 { output += value }
            case .translit(let translit, let hebrew):
                if level3 { output += "(\(translit) / \(hebrew))" }
            case .gloss(let children):
                if gloss { output += children.plainText(gloss: gloss, level3: level3) }
            case .emphasis(let children), .important(let children), .link(let children, _):
                output += children.plainText(gloss: gloss, level3: level3)
            case .lineBreak:
                output += "\n"
            }
        }
    }

    /// Tous les intraduisibles de l'arbre, dans l'ordre du texte.
    var lemmas: [String] {
        flatMap { node -> [String] in
            switch node {
            case .term(_, let lemma): [lemma]
            case .gloss(let children), .emphasis(let children), .important(let children),
                .link(let children, _):
                children.lemmas
            default: []
            }
        }
    }
}
