import Foundation

/// Un verset ONT.
///
/// `n` est la numérotation **interne** à l'unité (CLAUDE.md §2.2) : elle
/// repart de 1 à chaque unité fonctionnelle et ne correspond pas au numéro
/// biblique. Le renvoi biblique vit dans le sous-titre du chapitre.
public struct Verse: Decodable, Hashable, Sendable, Identifiable {
    public let n: Int
    public let nodes: [Inline]

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

extension Block: Decodable {
    private enum CodingKeys: String, CodingKey {
        case t, level, nodes, verses, ordered, items, headers, rows
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .t)

        switch kind {
        case "heading":
            self = .heading(
                level: try container.decode(Int.self, forKey: .level),
                nodes: try container.decode([Inline].self, forKey: .nodes)
            )
        case "verses":
            self = .verses(try container.decode([Verse].self, forKey: .verses))
        case "para":
            self = .paragraph(try container.decode([Inline].self, forKey: .nodes))
        case "list":
            self = .list(
                ordered: try container.decode(Bool.self, forKey: .ordered),
                items: try container.decode([[Inline]].self, forKey: .items)
            )
        case "quote":
            self = .quote(try container.decode([Inline].self, forKey: .nodes))
        case "table":
            self = .table(
                headers: try container.decode([[Inline]].self, forKey: .headers),
                rows: try container.decode([[[Inline]]].self, forKey: .rows)
            )
        case "rule":
            self = .rule
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .t,
                in: container,
                debugDescription: "Type de bloc inconnu : « \(kind) »."
            )
        }
    }
}

extension Block: Identifiable {
    public var id: Int { hashValue }
}
