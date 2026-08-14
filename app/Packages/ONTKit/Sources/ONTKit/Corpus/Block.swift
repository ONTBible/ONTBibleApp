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
