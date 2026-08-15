import Foundation

/// Un verset ONT.
///
/// `n` est la numérotation **interne** à l'unité (CLAUDE.md §2.2) : elle
/// repart de 1 à chaque unité fonctionnelle et ne correspond pas au numéro
/// biblique. Le renvoi biblique vit dans le sous-titre du chapitre.
public struct Verse: Hashable, Sendable, Identifiable {
    public let n: Int
    public let nodes: [Inline]

    /// L'init mémberwise synthétisé est interne au module. `ONTData` fabrique
    /// des versets en traduisant le DTO engendré, et les tests en fabriquent
    /// pour les aperçus.
    public init(n: Int, nodes: [Inline]) {
        self.n = n
        self.nodes = nodes
    }

    public var id: Int { n }
}

/// Un bloc de mise en page.
public enum Block: Hashable, Sendable {
    case heading(level: Int, nodes: [Inline])
    case verses([Verse])
    case paragraph([Inline])
    case list(ordered: Bool, items: [[Inline]])
    case quote([Inline])
    case table(headers: [[Inline]], rows: [[[Inline]]])
    case rule
}

// Le décodage est parti dans `ONTData` — voir `Inline.swift` pour le pourquoi,
// et `SchemaMapping.swift` pour la traduction.

extension Block: Identifiable {
    public var id: Int { hashValue }
}

extension Array where Element == Block {
    /// Les blocs de versets consécutifs, réunis en un seul.
    ///
    /// ## Pourquoi le mode « versets à la suite » ne faisait rien
    ///
    /// La prose continue se fabrique dans la vue en composant **un bloc** en
    /// un seul `Text`. Elle ne peut donc lier que ce que le bloc contient
    /// déjà — et le corpus, lui, découpe surtout au verset : 504 blocs d'un
    /// seul verset contre 109 qui en groupent deux à six. Là où le corpus
    /// groupait, le mode marchait ; partout ailleurs — Bereshit 11 en
    /// entier — il rendait exactement la même chose que le mode blocs.
    ///
    /// Rien ne le signalait : le réglage s'enregistrait, la branche s'exécutait,
    /// le rendu ne changeait pas d'un pixel.
    ///
    /// Réunir ici plutôt que dans la vue, parce que c'est une question de
    /// **texte** et non d'affichage : le découpage du corpus sert le mode
    /// d'étude, où chaque verset se tient seul. La lecture suivie demande
    /// l'autre découpage, et rien n'oblige à ce que le premier soit le seul
    /// que le domaine sache produire.
    ///
    /// Les titres coupent, et c'est voulu : « Les toledot de Shem » ouvre une
    /// section, la prose ne doit pas l'enjamber. Tout ce qui n'est pas un
    /// verset traverse sans changement.
    ///
    /// On accumule les versets dans un tampon plutôt que de reconstruire le
    /// dernier bloc à chaque tour. `.verses(precedents + suite)` recopiait tout
    /// ce qui précède à chaque verset ajouté : quadratique, et refait à chaque
    /// évaluation du corps de la liseuse — c'est-à-dire à chaque appui.
    public func fusingConsecutiveVerses() -> [Block] {
        var resultat: [Block] = []
        resultat.reserveCapacity(count)
        var tampon: [Verse] = []

        func vider() {
            guard !tampon.isEmpty else { return }
            resultat.append(.verses(tampon))
            tampon.removeAll(keepingCapacity: true)
        }

        for bloc in self {
            if case .verses(let suite) = bloc {
                tampon.append(contentsOf: suite)
            } else {
                vider()
                resultat.append(bloc)
            }
        }
        vider()
        return resultat
    }
}
