import Foundation

/// La fiche d'un **Shem** — un porteur de nom.
///
/// ## Pourquoi ce n'est pas une entrée de glossaire
///
/// Elle en a la tenue sans en être une. Un intraduisible dit **ce qu'un concept
/// est** — `chesed` reste en hébreu parce que « bonté » rate quelque chose. Une
/// fiche de Shem dit **ce qu'un nom met sur les épaules de qui le porte** :
/// *Avraham* est « père d'une multitude », *Peleg* le partage.
///
/// Les mêler ferait promettre une fiche de concept là où il y a un porteur, et
/// remplirait l'onglet Lexique de trois cents noms qui n'y ont rien à faire.
/// C'est la distinction que toute cette couche existe pour tenir.
///
/// D'où un fichier à part — `shemot.json` —, un port à part, et une feuille à
/// part.
public struct ShemEntry: Hashable, Sendable, Identifiable {
    /// La clé de jointure avec `Inline.shem(_:lemma:)`.
    public let lemma: String
    /// La forme d'affichage — `Qayin`, `Tuval-Qayin`, `Na'amah`.
    public let title: String
    /// Le corps de la fiche, **titres de section compris**.
    ///
    /// Quatre à six mouvements, là où une fiche d'intraduisible est un bloc de
    /// prose : la racine, le porteur, ce qu'il fait ailleurs dans le corpus, ce
    /// que son nom porte après lui, et les renvois.
    public let definition: [Block]

    public var id: String { lemma }

    public init(lemma: String, title: String, definition: [Block]) {
        self.lemma = lemma
        self.title = title
        self.definition = definition
    }

    /// Vrai quand la fiche n'a rien à dire du nom.
    ///
    /// Même garde que pour un intraduisible, et pour la même raison : un écran
    /// qui montre un en-tête et rien dessous a l'air complet.
    public var sansDefinition: Bool { definition.isEmpty }
}
