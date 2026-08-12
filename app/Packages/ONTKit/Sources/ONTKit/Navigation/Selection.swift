import Foundation

/// Un lemme, présentable par `sheet(item:)`.
///
/// Plutôt qu'une conformité rétroactive `String: Identifiable` : celle-ci
/// serait globale, s'appliquerait à toutes les chaînes de l'app, et entrerait
/// en conflit le jour où une bibliothèque en déclare une autre.
public struct LemmaSelection: Identifiable, Hashable, Sendable {
    public let id: String

    public init(_ lemma: String) { id = lemma }
}

/// Un numéro de verset, présentable par `sheet(item:)`.
public struct VerseSelection: Identifiable, Hashable, Sendable {
    public let id: Int

    public init(_ verse: Int) { id = verse }
}
