import Foundation

/// Le renvoi d'une sélection de versets — « 1-3, 7 ».
///
/// Dans `ONTKit` et non dans la feature de lecture, parce que la forme est
/// lue **et** écrite : la vue la produit pour l'afficher et la partager, le
/// routeur la relit dans un lien reçu. Deux implémentations d'un même format
/// finiraient par diverger, et le jour où elles divergent un lien partagé
/// n'ouvre plus le bon passage.
///
/// Vit hors de la vue, et c'est le résultat d'un plantage : la première
/// version calculait l'intervalle dans le corps de la barre d'actions, avec un
/// `numbers[0]` sur un tableau supposé non vide. Quand le lecteur
/// désélectionnait son dernier verset, SwiftUI réévaluait la barre sortante
/// avec une sélection déjà vide — index hors limites, app fermée.
///
/// La leçon n'est pas « ajouter un garde » mais « sortir le calcul de la vue » :
/// ici il s'éprouve en trois lignes, y compris le cas vide.
public enum VerseRange {
    /// « 1-3, 7 » plutôt que « 1, 2, 3, 7 ».
    ///
    /// Renvoie une chaîne vide pour une sélection vide — un renvoi qui ne
    /// renvoie à rien.
    public static func label(_ verses: Set<Int>) -> String {
        let numbers = verses.sorted()
        guard let first = numbers.first else { return "" }

        var groups: [String] = []
        var start = first
        var previous = first

        for n in numbers.dropFirst() {
            if n == previous + 1 {
                previous = n
                continue
            }
            groups.append(borne(start, previous))
            start = n
            previous = n
        }
        groups.append(borne(start, previous))
        return groups.joined(separator: ", ")
    }

    /// Le renvoi complet, titre du chapitre compris — « Bereshit 1:1-3, 7 ».
    public static func reference(_ verses: Set<Int>, chapterTitle: String) -> String {
        let intervals = label(verses)
        return intervals.isEmpty ? chapterTitle : "\(chapterTitle):\(intervals)"
    }

    private static func borne(_ start: Int, _ end: Int) -> String {
        start == end ? "\(start)" : "\(start)-\(end)"
    }

    /// L'opération inverse : « 1-3, 7 » redevient {1, 2, 3, 7}.
    ///
    /// Tolérante par construction. Un renvoi arrive d'une URL, donc de
    /// l'extérieur : « 3-1 » se lit à l'endroit, un morceau illisible est
    /// ignoré plutôt que de faire échouer tout le lien, et un intervalle
    /// absurde est borné. Le pire cas rend un ensemble vide, jamais une
    /// erreur — un lien à moitié compris vaut mieux qu'un lien mort.
    public static func parse(_ raw: String) -> Set<Int> {
        // Une borne haute : `?v=1-99999999` ne doit pas allouer des millions
        // d'entiers parce que quelqu'un a bricolé l'adresse.
        let plafond = 400

        var verses: Set<Int> = []
        for morceau in raw.split(separator: ",") {
            let bornes = morceau.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            switch bornes.count {
            case 1:
                verses.insert(bornes[0])
            case 2:
                let bas = min(bornes[0], bornes[1])
                let haut = max(bornes[0], bornes[1])
                guard haut - bas < plafond else { continue }
                verses.formUnion(bas...haut)
            default:
                continue
            }
        }
        return verses.filter { $0 > 0 }
    }
}
