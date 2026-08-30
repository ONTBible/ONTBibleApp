import Foundation

/// Une lettre de l'index, et ce qu'elle rassemble.
public struct TrancheAlphabetique<Element>: Identifiable, Sendable
where Element: Sendable {
    /// La lettre affichée dans le rail — une seule, en capitale.
    public let lettre: String
    public let entrees: [Element]

    public var id: String { lettre }

    public init(lettre: String, entrees: [Element]) {
        self.lettre = lettre
        self.entrees = entrees
    }
}

/// Le classement alphabétique d'une liste, pour le rail de lettres.
///
/// ## Ce que « la lettre d'un mot » veut dire ici
///
/// Le lexique de l'ONT n'est pas une liste de mots français. Il porte des
/// translittérations (*chesed*, *She'ol*), des apostrophes, des accents, et une
/// colonne d'hébreu. Trois décisions en découlent :
///
/// * **on classe sur le titre affiché**, jamais sur l'hébreu. C'est ce que le
///   lecteur voit et ce qu'il cherche du pouce ; classer sur l'hébreu ferait
///   un rail dont aucune lettre ne correspond à ce qui est à l'écran ;
/// * **les accents se replient** — `É` et `E` sont la même lettre. Deux
///   entrées voisines à l'œil sous deux lettres différentes rendraient le rail
///   inutilisable ;
/// * **l'apostrophe et les signes ne comptent pas** : `'Elohim` se range sous
///   `E`. Une lettre `'` dans le rail ne dit rien à personne.
///
/// Tout ce qui ne commence par aucune lettre — un chiffre, un signe — va sous
/// **`#`**, placé en fin de rail comme dans Contacts.
public enum IndexAlphabetique {
    /// La lettre sous laquelle un titre se range.
    public static func lettre(de titre: String) -> String {
        // Le premier caractère **alphabétique**, pas le premier caractère : un
        // titre qui ouvre sur une apostrophe se rangerait sinon sous un signe.
        let replie = titre.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        guard let premiere = replie.first(where: { $0.isLetter }) else { return "#" }
        return String(premiere).uppercased()
    }

    /// Découpe une liste **déjà triée** en tranches.
    ///
    /// Elle n'ordonne pas : le classement appartient à qui fournit la liste, et
    /// le refaire ici ferait deux vérités sur un même écran — celle de la liste
    /// et celle du rail.
    public static func trancher<Element: Sendable>(
        _ elements: [Element],
        titre: (Element) -> String
    ) -> [TrancheAlphabetique<Element>] {
        var tranches: [TrancheAlphabetique<Element>] = []

        for element in elements {
            let lettre = lettre(de: titre(element))
            if let derniere = tranches.last, derniere.lettre == lettre {
                tranches[tranches.count - 1] = TrancheAlphabetique(
                    lettre: lettre, entrees: derniere.entrees + [element])
            } else {
                tranches.append(TrancheAlphabetique(lettre: lettre, entrees: [element]))
            }
        }
        return tranches
    }
}
