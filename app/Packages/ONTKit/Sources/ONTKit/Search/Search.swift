import Foundation

/// Une entrée de l'index de recherche, telle que le pipeline l'émet.
public struct SearchRecord: Sendable, Hashable {
    public enum Kind: String, Sendable {
        case verse, heading, prose
    }

    public let b: String
    public let c: String
    public let v: Int
    public let k: Kind
    /// Le corps de la traduction, plié.
    public let t: String
    /// Les gloses seules, pliées.
    public let g: String
    /// L'hébreu dénudé de son niqqud et de ses te'amim.
    public let h: String
    /// Les lemmes d'intraduisibles présents.
    public let l: [String]
    /// Le corps tel qu'il s'affiche, pour l'extrait.
    public let x: String

    /// Initialiseur public — l'init mémberwise synthétisé reste interne, et
    /// les tests comme les doublures ont besoin de fabriquer des entrées.
    public init(
        b: String, c: String, v: Int, k: Kind,
        t: String, g: String, h: String, l: [String], x: String
    ) {
        self.b = b; self.c = c; self.v = v; self.k = k
        self.t = t; self.g = g; self.h = h; self.l = l; self.x = x
    }

    public var bookId: String { b }
    public var chapterId: String { c }
    public var verse: Int? { v == 0 ? nil : v }
}

// `SearchFile` vivait ici — une enveloppe de fichier, pas un concept de l'ONT.

/// Où chercher — les niveaux du texte, en question de recherche.
///
/// « Où le texte dit-il **chesed** » et « où l'explique-t-on » sont deux
/// questions distinctes (§2.1), et l'une ne doit pas noyer l'autre.
public enum SearchScope: String, CaseIterable, Sendable {
    case body = "Dans le texte"
    case gloss = "Dans les gloses"
    case all = "Partout"
}

public struct SearchHit: Identifiable, Hashable, Sendable {
    public let record: SearchRecord
    /// Là où la correspondance a été trouvée.
    public let level: Occurrence.Level
    public let score: Int
    /// L'extrait, avec la plage à mettre en évidence.
    public let snippet: String
    public let range: Range<String.Index>?

    /// L'identité d'un résultat.
    ///
    /// **Le rang du verset ne suffit pas à distinguer deux enregistrements.**
    /// Les intertitres portent tous `v = 0` : `bereshit-15` en compte quatre,
    /// dont deux contiennent « alliance ». Sans le texte, deux résultats bien
    /// distincts partageaient le même identifiant.
    ///
    /// Ce que ça produisait diffère selon la plateforme, et c'est ce qui l'a
    /// rendu invisible ici : **Compose lève** — `Key was already used` —, là où
    /// SwiftUI écrit un avertissement en console et continue. Un `ForEach` aux
    /// identifiants doublés peut alors réutiliser la mauvaise vue ou garder
    /// l'état d'une ligne sur une autre : ça ne ressemble pas à une panne, ça
    /// ressemble à un résultat qui clignote.
    ///
    /// Le texte plié plutôt qu'un rang d'itération : il est **stable d'une
    /// recherche à l'autre**, là où un compteur dépendrait de l'ordre de
    /// parcours. Un identifiant qui change entre deux rendus de la même
    /// requête défait les animations qu'il sert à tenir.
    public var id: String {
        "\(record.c)-\(record.v)-\(level.rawValue)-\(record.t)"
    }
}

/// Le moteur de recherche.
///
/// Volontairement sans index inversé : à l'échelle du corpus — quelques
/// dizaines de milliers d'entrées une fois les 70 slots rédigés — un balayage
/// de sous-chaînes sur des chaînes déjà pliées prend quelques millisecondes.
/// Un index inversé ajouterait de la complexité sans gain mesurable, et
/// interdirait la recherche par sous-chaîne au milieu d'un mot, qui est
/// précisément ce qu'on veut pour l'hébreu et les formes construites.
public enum SearchEngine {
    /// Plie une chaîne latine pour la comparaison.
    ///
    /// Doit rester **identique** au `fold` du pipeline, sinon l'index et la
    /// requête ne se rencontrent jamais.
    public static func fold(_ input: String) -> String {
        input
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "ʼ", with: "'")
            .replacingOccurrences(
                of: "\\s+",
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespaces)
    }

    /// Dénude l'hébreu : consonnes seules, sans niqqud ni te'amim.
    ///
    /// C'est ce qui permet à une saisie au clavier hébreu ordinaire — sans
    /// voyelles, comme on écrit l'hébreu tous les jours — de rencontrer un
    /// texte biblique intégralement vocalisé. Sans ça, taper חסד ne trouverait
    /// jamais חֶסֶד.
    public static func stripHebrew(_ input: String) -> String {
        let punctuation: Set<Character> = ["־", "׀", "׃", "׆", "׳", "״"]
        let stripped = input.unicodeScalars.filter { scalar in
            !scalar.properties.isDiacritic
                && scalar.properties.generalCategory != .nonspacingMark
        }
        return String(String.UnicodeScalarView(stripped))
            .filter { !punctuation.contains($0) }
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    public static func isHebrew(_ input: String) -> Bool {
        input.unicodeScalars.contains { (0x0590...0x05FF).contains($0.value) }
    }

    /// Cherche dans l'index.
    ///
    /// - Parameters:
    ///   - lemmas: les lemmes du glossaire, pour que taper « chesed » trouve
    ///     aussi les passages où le terme ne paraît qu'en hébreu.
    public static func search(
        _ query: String,
        in records: [SearchRecord],
        scope: SearchScope,
        lemmas: Set<String> = [],
        limit: Int = 300
    ) -> [SearchHit] {
        let raw = query.trimmingCharacters(in: .whitespaces)
        guard raw.count >= 2 else { return [] }

        // Une requête en écriture hébraïque se compare à la forme dénudée.
        let hebrewNeedle = isHebrew(raw) ? stripHebrew(raw) : nil
        let needle = fold(raw)
        let lemmaNeedle = lemmas.contains(needle) ? needle : nil

        var hits: [SearchHit] = []

        for record in records {
            if let hebrewNeedle {
                guard record.h.contains(hebrewNeedle) else { continue }
                hits.append(hit(record, level: .body, score: 500))
                continue
            }

            var matched = false

            if scope != .gloss, let found = record.t.range(of: needle) {
                // Un mot entier vaut mieux qu'un fragment, et un début de
                // verset mieux qu'un milieu.
                var score = 300
                if record.t.hasPrefix(needle) { score += 60 }
                if isWordBoundary(record.t, at: found) { score += 40 }
                if record.k == .heading { score += 30 }
                hits.append(hit(record, level: .body, score: score))
                matched = true
            }

            if scope != .body, record.g.contains(needle) {
                hits.append(hit(record, level: .gloss, score: 150))
                matched = true
            }

            // Le lemme rattrape les passages où le terme n'est qu'en hébreu.
            if !matched, let lemmaNeedle, record.l.contains(lemmaNeedle) {
                hits.append(hit(record, level: .body, score: 100))
            }
        }

        return Array(
            hits
                .sorted { left, right in
                    left.score == right.score
                        ? left.record.c < right.record.c
                        : left.score > right.score
                }
                .prefix(limit)
        )
    }

    private static func hit(
        _ record: SearchRecord,
        level: Occurrence.Level,
        score: Int
    ) -> SearchHit {
        SearchHit(record: record, level: level, score: score, snippet: record.x, range: nil)
    }

    /// Vrai si la correspondance commence et finit sur une frontière de mot.
    private static func isWordBoundary(_ text: String, at range: Range<String.Index>) -> Bool {
        let before = range.lowerBound == text.startIndex
            ? true
            : !text[text.index(before: range.lowerBound)].isLetter
        let after = range.upperBound == text.endIndex
            ? true
            : !text[range.upperBound].isLetter
        return before && after
    }
}
