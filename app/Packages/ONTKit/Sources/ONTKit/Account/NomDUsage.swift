import Foundation

/// Le nom d'usage — `@gloiiire_`.
///
/// **C'est le seul champ du profil qui soit un identifiant.** Le prénom, le nom
/// et la bio décrivent ; celui-ci **désigne**, et c'est par lui qu'un lecteur
/// en nommera un autre le jour où le Qahal ouvrira. Il porte donc des règles
/// que les autres n'ont pas.
///
/// La forme suit celle que tout le monde connaît — le lecteur en a déjà un
/// ailleurs, et il tapera le même :
///
/// * **des minuscules**, toujours. `@Gloire` et `@gloire` désigneraient deux
///   personnes différentes alors qu'on lit le même mot ; on replie donc à la
///   saisie plutôt que de laisser deux noms se ressembler ;
/// * **lettres latines, chiffres, points et tirets bas**, rien d'autre. Pas
///   d'accents ni d'espaces : un identifiant qui se prononce autrement qu'il ne
///   s'écrit ne se retrouve pas ;
/// * **entre 3 et 30 signes**, et jamais un point aux extrémités ni deux
///   points de suite — c'est ce qui rend `@a..b` et `@a.b` distincts à l'œil
///   nu sans l'être vraiment.
public enum NomDUsage {
    public static let minimum = 3
    public static let maximum = 30

    /// Replie une saisie vers ce qu'elle peut être.
    ///
    /// **Appelée à la frappe, pas à la validation.** Refuser après coup un nom
    /// qu'on vient de taper en entier oblige à tout reprendre ; l'écarter au
    /// moment où il s'écrit fait sentir la règle sans jamais l'énoncer.
    ///
    /// Le `@` de tête est absorbé : le lecteur le tape par habitude, et il
    /// n'appartient pas au nom — il appartient à la façon dont on l'affiche.
    public static func replier(_ saisie: String) -> String {
        var sortie = ""
        sortie.reserveCapacity(min(saisie.count, maximum))

        for caractere in saisie.lowercased() {
            guard sortie.count < maximum else { break }
            switch caractere {
            case "a"..."z", "0"..."9", "_":
                sortie.append(caractere)
            case ".":
                // Ni en tête, ni doublé. On ne rejette pas la frappe, on
                // l'ignore — le curseur n'avance pas, et c'est tout.
                if !sortie.isEmpty, sortie.last != "." { sortie.append(caractere) }
            default:
                // Le `@` d'habitude, les espaces, les accents : rien de tout
                // cela n'entre. Un accent replié en sa lettre nue ferait
                // qu'`@rené` et `@rene` désigneraient la même personne sans
                // qu'on l'ait dit.
                continue
            }
        }
        return sortie
    }

    /// Vrai quand le nom peut servir d'identifiant.
    ///
    /// Distinct de `replier` : un nom peut être **bien formé et trop court**.
    /// Replier une saisie de deux lettres rend deux lettres, et c'est correct —
    /// c'est en le validant qu'on refuse, jamais en le tapant.
    public static func valide(_ nom: String) -> Bool {
        guard nom.count >= minimum, nom.count <= maximum else { return false }
        guard nom.last != "." else { return false }
        return nom == replier(nom)
    }

    /// Ce qu'un écran doit dire quand le nom ne va pas, ou `nil` s'il va.
    ///
    /// Le message nomme **ce qui manque**, jamais la règle entière : « entre 3
    /// et 30 signes, lettres, chiffres, points et tirets bas » devant un nom de
    /// deux lettres oblige le lecteur à chercher laquelle des quatre clauses le
    /// concerne.
    public static func reproche(_ nom: String) -> String? {
        if nom.isEmpty { return nil }
        if nom.count < minimum { return "Au moins \(minimum) signes." }
        if nom.count > maximum { return "Au plus \(maximum) signes." }
        if nom.last == "." { return "Ne peut pas finir par un point." }
        return nil
    }
}
