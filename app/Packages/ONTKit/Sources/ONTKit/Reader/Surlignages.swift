import Foundation

/// Un surlignage rendu **lisible** — son texte, son renvoi, sa place.
///
/// Le dépôt ne garde qu'une adresse : livre, unité, verset. C'est délibéré, et
/// c'est la même raison qui interdit au serveur de garder le texte — un
/// surlignage rattaché à une identité révèle des convictions religieuses, donc
/// on n'en stocke que le strict nécessaire. Le texte se **recompose** depuis le
/// corpus embarqué, à chaque affichage.
public struct SurlignageSitue: Identifiable, Hashable, Sendable {
    public let surlignage: Highlight
    /// Le corps du verset, sans balisage.
    public let texte: String
    /// Le renvoi tel qu'on le lit — « Bereshit 1:1 ».
    public let renvoi: String

    public var id: UUID { surlignage.id }

    public init(surlignage: Highlight, texte: String, renvoi: String) {
        self.surlignage = surlignage
        self.texte = texte
        self.renvoi = renvoi
    }
}

/// Les surlignages d'un livre, dans l'ordre où on les a lus.
public struct LivreSurligne: Identifiable, Hashable, Sendable {
    public let livre: BookOutline
    public let surlignages: [SurlignageSitue]

    public var id: String { livre.id }

    public init(livre: BookOutline, surlignages: [SurlignageSitue]) {
        self.livre = livre
        self.surlignages = surlignages
    }
}

/// Rassembler ce qu'un lecteur a marqué.
///
/// **Dans l'ordre du corpus, pas par date.** On cherche « ce que j'ai marqué
/// dans *Bereshit* », jamais « ce que j'ai marqué mardi » : un classement
/// chronologique disperse un même livre sur toute la liste, et deux séances de
/// lecture du même chapitre s'y retrouvent aux deux bouts.
///
/// La date reste sur chaque ligne — elle situe, elle ne classe pas.
public enum Surlignages {
    /// Assemble les surlignages en livres.
    ///
    /// - Parameters:
    ///   - surlignages: ce que le dépôt rend, **pierres tombales déjà exclues**
    ///     (`HighlightRepository.all()`).
    ///   - livres: les livres dans l'ordre canonique des slots.
    ///   - texte: rend le corps d'un verset, ou `nil` s'il n'existe plus.
    ///
    /// Un surlignage dont le verset est introuvable est **écarté**, pas rendu
    /// vide : un livre remanié entre deux publications déplace des versets, et
    /// une ligne sans texte ne dirait au lecteur ni ce qu'il avait marqué ni
    /// pourquoi elle est là.
    public static func parLivre(
        _ surlignages: [Highlight],
        livres: [BookOutline],
        texte: (Highlight) -> (corps: String, renvoi: String)?
    ) -> [LivreSurligne] {
        // Le rang d'un livre, pour trier sans chercher dans un tableau à chaque
        // comparaison. `slot` est le numéro canonique du corpus.
        let rang = Dictionary(
            livres.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { premier, _ in premier }
        )
        // Le rang d'une unité **dans son livre** : les unités ne portent pas de
        // numéro exploitable — « Bereshit 11 » se trierait après « Bereshit 2 »
        // en comparant les chaînes. C'est leur ordre dans le sommaire qui fait
        // foi, comme partout ailleurs dans l'app.
        var rangDUnite: [String: Int] = [:]
        for livre in livres {
            for (i, unite) in livre.chapters.enumerated() {
                rangDUnite[unite.id] = i
            }
        }

        let groupes = Dictionary(grouping: surlignages, by: \.bookId)

        return livres.compactMap { livre in
            guard let siens = groupes[livre.id], !siens.isEmpty else { return nil }

            let situes =
                siens
                .compactMap { surlignage -> SurlignageSitue? in
                    guard let rendu = texte(surlignage) else { return nil }
                    return SurlignageSitue(
                        surlignage: surlignage, texte: rendu.corps, renvoi: rendu.renvoi)
                }
                .sorted { a, b in
                    let ua = rangDUnite[a.surlignage.chapterId] ?? Int.max
                    let ub = rangDUnite[b.surlignage.chapterId] ?? Int.max
                    if ua != ub { return ua < ub }
                    return a.surlignage.verse < b.surlignage.verse
                }

            guard !situes.isEmpty else { return nil }
            return LivreSurligne(livre: livre, surlignages: situes)
        }
        .sorted { (rang[$0.livre.id] ?? Int.max) < (rang[$1.livre.id] ?? Int.max) }
    }

    /// Le décompte par couleur, pour le filtre.
    ///
    /// Rendu dans l'ordre déclaré de `HighlightColor` et non dans celui des
    /// surlignages : un filtre dont les entrées changent de place selon ce
    /// qu'on a marqué en dernier ne se retrouve pas deux fois au même endroit.
    public static func parCouleur(_ surlignages: [Highlight]) -> [(HighlightColor, Int)] {
        HighlightColor.allCases.compactMap { couleur in
            let n = surlignages.filter { $0.color == couleur }.count
            return n > 0 ? (couleur, n) : nil
        }
    }
}
