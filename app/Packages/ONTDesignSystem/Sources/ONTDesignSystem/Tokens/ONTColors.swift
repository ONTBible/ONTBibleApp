import ONTKit
import SwiftUI

/// La palette.
///
/// Relevée sur le combination mark de La Bible ONT — le bordeaux et l'or
/// viennent du logo, pas d'un choix arbitraire. Le parchemin les accompagne
/// parce qu'une liseuse ne se lit pas sur du blanc pur.
///
/// **Ne jamais écrire une couleur en dur ailleurs.** Une teinte qui n'est pas
/// ici est une teinte qu'on ne pourra pas décliner en thème sombre.
public enum ONTColors {
    // MARK: - Marque

    /// Le bordeaux du logo — fond des cartes, accent, titres de section.
    ///
    /// Relevé au pixel sur `La Bible ONT - Combination Mark.png` : **#421B26**.
    /// Le logo est la source unique — l'icône de l'app porte la même teinte,
    /// convertie en Display P3 dans `ONT.icon/icon.json`.
    public static let burgundy = Color(red: 0.259, green: 0.106, blue: 0.149)

    /// L'or du logo — texte sur bordeaux, filets, numéros de verset. **#CDBE83**.
    public static let gold = Color(red: 0.804, green: 0.745, blue: 0.514)
    /// L'or assombri — les intraduisibles sur fond clair, où l'or pur
    /// n'aurait pas un contraste suffisant.
    public static let goldDeep = Color(red: 0.65, green: 0.53, blue: 0.31)

    // MARK: - Surfaces de lecture

    public static func background(_ theme: ReadingTheme) -> Color {
        switch theme {
        case .parchment: Color(red: 0.98, green: 0.96, blue: 0.92)
        case .light: Color(white: 1)
        case .dark: Color(red: 0.09, green: 0.08, blue: 0.09)
        }
    }

    public static func ink(_ theme: ReadingTheme) -> Color {
        switch theme {
        case .parchment: Color(red: 0.16, green: 0.13, blue: 0.11)
        case .light: Color(white: 0.1)
        case .dark: Color(red: 0.88, green: 0.86, blue: 0.83)
        }
    }

    /// La couleur du **terme important** — le troisième niveau de marquage.
    ///
    /// Le bordeaux du logo, éclairci. **Même teinte exactement — 343°** : la
    /// parenté avec le fond des cartes et avec la marque doit se lire. Seules
    /// la clarté et la saturation montent, parce que le bordeaux d'origine
    /// est une *encre* et se confond avec celle du texte.
    ///
    /// Écart perceptuel à l'encre du parchemin, en CIE Lab :
    ///
    ///     #421B26  ΔE 18   l'origine — l'œil hésite, seul le gras marque
    ///     #862742  ΔE 39   ici
    ///     or       ΔE 44   les intraduisibles, pour comparaison
    ///
    /// Les deux marquages se détachent avec la même force : ni l'un ni
    /// l'autre ne prend le pas. En dessous de ΔE 25, une couleur ne se
    /// distingue plus de façon fiable dans un texte courant.
    public static func important(_ theme: ReadingTheme) -> Color {
        switch theme {
        case .parchment, .light: Color(red: 0.525, green: 0.153, blue: 0.259)
        // Sur fond sombre, le même bordeaux disparaît dans le noir. On remonte
        // la clarté à teinte constante jusqu'à 6,1:1 sur le fond — au-delà du
        // seuil AA du WCAG, et ΔE 47 avec l'encre claire.
        case .dark: Color(red: 0.847, green: 0.475, blue: 0.580)
        }
    }

    /// L'or lisible sur le fond du thème — sur parchemin l'or pur passe mal.
    public static func accent(_ theme: ReadingTheme) -> Color {
        theme == .dark ? gold : goldDeep
    }

    /// Une surface posée sur le fond : ligne de liste, carte, feuille.
    ///
    /// Sur parchemin, un blanc pur détonnerait — la surface est un parchemin
    /// plus clair, pas une autre matière. C'est ce qui donne à l'app une seule
    /// couleur de peau au lieu de quatre écrans qui ne se ressemblent pas.
    public static func surface(_ theme: ReadingTheme) -> Color {
        switch theme {
        case .parchment: Color(red: 1.0, green: 0.99, blue: 0.965)
        case .light: Color(white: 1)
        case .dark: Color(red: 0.145, green: 0.135, blue: 0.145)
        }
    }

    /// Le filet de séparation entre deux lignes.
    public static func separator(_ theme: ReadingTheme) -> Color {
        ink(theme).opacity(theme == .dark ? 0.16 : 0.10)
    }

    // MARK: - Surlignage

    /// La teinte réelle d'une couleur de surlignage.
    ///
    /// Le domaine ne connaît que le nom (`HighlightColor.gold`) ; la valeur
    /// est ici, ce qui permet de retoucher la palette sans migrer les données
    /// déjà enregistrées.
    ///
    /// Cinq teintes tirées vers le pastel plutôt que le fluo d'écolier : un
    /// surlignage se pose sur un texte qu'on lit longtemps, il ne doit pas
    /// crier ni rendre le texte illisible.
    public static func highlight(_ color: HighlightColor) -> Color {
        switch color {
        case .gold: Color(red: 0.91, green: 0.79, blue: 0.45)
        case .olive: Color(red: 0.72, green: 0.78, blue: 0.53)
        case .sky: Color(red: 0.62, green: 0.78, blue: 0.87)
        case .rose: Color(red: 0.92, green: 0.68, blue: 0.68)
        case .violet: Color(red: 0.78, green: 0.70, blue: 0.87)
        }
    }

    /// L'opacité d'un surlignage — assez pour se voir, assez peu pour que le
    /// texte reste au premier plan.
    public static let highlightOpacity: Double = 0.38
}
