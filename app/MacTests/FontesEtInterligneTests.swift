import AppKit
import Foundation
import ONTDesignSystem
import SwiftUI
import Testing

@testable import ONTMac

/// **Les fontes du projet sont-elles seulement chargées sur le Mac ?**
///
/// iOS les inscrit par `UIAppFonts`, dans l'`Info.plist`. macOS ne connaît pas
/// cette clé : il lit `ATSApplicationFontsPath`. La cible du Mac ne déclarait
/// ni l'une ni l'autre — les `.ttf` étaient copiés dans le bundle, et personne
/// ne les inscrivait.
///
/// Le défaut est silencieux par construction : `Font.custom` retombe sur la
/// fonte système quand le nom ne se résout pas, sans rien dire. La liseuse
/// paraissait juste, à ceci près que **rien de sa typographie ne s'appliquait**
/// — ni Literata, choisie pour la lecture longue, ni EzraSIL, seule à porter le
/// niqqud et les te'amim.
///
/// Et la garde qui aurait dû l'attraper ne gardait rien : `ONTFonts.hebrewAvailable`
/// vérifie la fonte sous `canImport(UIKit)` et rend `true` en dur ailleurs. Le
/// catalogue du design system affichait donc « embarquée » sur le Mac quoi qu'il
/// arrive.
@MainActor
@Suite("Les fontes du Mac")
struct FontesDuMacTests {
    @Test(
        "chaque fonte embarquée se résout",
        arguments: [
            "EzraSIL",
            "Literata-Regular",
            "Literata-Italic",
            "Literata-SemiBold",
        ])
    func lesFontesSeResolvent(_ nom: String) {
        #expect(
            NSFont(name: nom, size: 12) != nil,
            """
            « \(nom) » ne se résout pas : le texte retombe sur la fonte système \
            sans que rien ne le dise. Vérifier `ATSApplicationFontsPath` dans \
            l'`Info.plist` de la cible ONTMac.
            """)
    }

    /// La fonte hébraïque porte le niqqud ; sans elle, les voyelles se
    /// décrochent des consonnes. C'est la seule dont l'absence se *voit*, et
    /// c'est aussi celle qui compte le plus pour la relecture.
    @Test("l'hébreu ne retombe pas sur la fonte système")
    func lHebreuEstBienEzra() {
        let fonte = NSFont(name: ONTFonts.hebrew, size: 20)
        #expect(fonte != nil)
        #expect(fonte?.fontName.contains("Ezra") == true, "rendu : \(fonte?.fontName ?? "aucune")")
    }
}

/// **Pourquoi une ligne qui porte de l'hébreu est plus haute que ses voisines.**
///
/// Mesuré le 30 août 2026, fontes inscrites. Trois bancs ont répondu à côté
/// avant celui-ci : le premier composait l'hébreu avec la fonte système, le
/// deuxième le *latin*, et le troisième comparait EzraSIL au système plutôt
/// qu'à Literata. Aucun n'échouait ; tous avaient l'air justes.
///
/// **Ce n'est pas qu'une fonte soit plus haute que l'autre.** Leurs boîtes de
/// ligne sont presque identiques à taille égale — rapport 0,995 — et la mise à
/// l'échelle de l'hébreu ne la porte qu'à 1,074 :
///
///     Literata 20      asc 23,54   desc −6,16   → boîte 29,70
///     EzraSIL 21,6     asc 23,18   desc −8,72   → boîte 31,90
///
/// C'est **la composition des deux** qui hausse la ligne. TextKit prend
/// l'ascendante la plus haute et la descendante la plus basse parmi les courses
/// de la ligne — et elles ne viennent pas de la même fonte : l'ascendante de
/// Literata, la descendante d'EzraSIL.
///
///     23,54 + 8,72 = 32,26     contre 29,70 pour Literata seule     → +2,56
///
/// Ce qui prédit le mesuré au point près, sur un bloc de trois lignes de 420 pt :
///
///     tout latin              90,00
///     avec fragment, 1,08×    93,00     écart +3,00
///     avec fragment, 1,00×    92,00     écart +2,00
///
/// L'échelle n'est donc pas la cause, seulement un aggravant d'un point : même
/// à 1,00×, la descendante d'EzraSIL passe deux points sous celle de Literata.
///
/// **Le remède existe et il est exact** — une hauteur de ligne imposée referme
/// l'écart à zéro, mesuré par TextKit à trois hauteurs :
///
///     sans style     latin 90,00   mêlé 93,00   écart +3,00
///     imposé 26      latin 78,00   mêlé 78,00   écart  0,00
///     imposé 30      latin 90,00   mêlé 90,00   écart  0,00
///     imposé 34      latin 102,00  mêlé 102,00  écart  0,00
///
/// — mais il n'est pas atteignable depuis `SwiftUI.Text`, qui **ignore** le
/// style de paragraphe. Mesuré en balayant la hauteur imposée de 20 à 90 points
/// sans que le rendu bouge d'un point : ce n'est pas « honoré mais
/// insuffisant », c'est ignoré.
///
/// Ces deux épreuves gardent les deux moitiés du constat. **Celle du bas
/// échouera le jour où SwiftUI honorerait le style de paragraphe** — et ce
/// jour-là le remède devient bon marché, au lieu d'exiger de rendre l'écran de
/// lecture partagé par un `NSViewRepresentable`. Trois points sur un bloc ne
/// valent pas ce prix aujourd'hui ; ils le vaudront peut-être demain.
@MainActor
@Suite("L'interligne des lignes mêlées")
struct InterligneTests {
    private static let taille: CGFloat = 20

    private func boite(_ f: NSFont) -> CGFloat { f.ascender - f.descender + f.leading }

    /// **La cause : deux fontes, une seule ligne.**
    ///
    /// L'épreuve ne compare pas les boîtes — elles se valent, et c'est
    /// précisément ce qui a égaré la première explication. Elle mesure la ligne
    /// *composée*, qui prend le plus haut et le plus bas de chaque côté.
    @Test("la ligne mêlée dépasse chacune des deux fontes prises seule")
    func laCause() throws {
        let latin = try #require(NSFont(name: "Literata-Regular", size: Self.taille))
        let hebreu = try #require(
            NSFont(name: ONTFonts.hebrew, size: Self.taille * ONTFonts.hebrewScale))

        // Ce que TextKit compose pour une ligne qui porte les deux.
        let melee = max(latin.ascender, hebreu.ascender) - min(latin.descender, hebreu.descender)

        #expect(
            melee > boite(latin),
            "la ligne mêlée ne dépasse plus le latin seul — l'écart d'interligne a disparu")
        #expect(
            melee > boite(hebreu),
            "la ligne mêlée ne dépasse plus l'hébreu seul")

        // Mesuré à 2,56 pt, et c'est ce que le rendu montre : +3,00 sur un bloc
        // de trois lignes. La borne basse garde le fait, pas le chiffre.
        let ecart = melee - boite(latin)
        #expect(ecart > 1, "l'écart composé est tombé à \(ecart) pt")
    }

    /// Un bloc de trois lignes, rendu à hauteur de ligne imposée. Si SwiftUI
    /// l'honorait, imposer 20 et imposer 90 ne donneraient pas la même hauteur.
    @Test("SwiftUI.Text ignore le style de paragraphe")
    func leLevierMort() {
        func hauteur(_ imposee: CGFloat) -> CGFloat {
            var texte = AttributedString(
                "Au commencement, Elohim créa les cieux et la terre, et la terre était informe et vide.")
            texte.font = .custom("Literata-Regular", size: Self.taille)
            let style = NSMutableParagraphStyle()
            style.minimumLineHeight = imposee
            style.maximumLineHeight = imposee
            texte.appKit.paragraphStyle = style
            let vue = Text(texte).frame(width: 420, alignment: .leading)
            return ImageRenderer(content: vue).nsImage?.size.height ?? 0
        }

        let serrée = hauteur(20)
        let large = hauteur(90)
        #expect(serrée > 0)
        #expect(
            serrée == large,
            """
            SwiftUI honore maintenant le style de paragraphe (\(serrée) → \(large)). \
            L'interligne des lignes mêlées se corrige alors sans passer par TextKit — \
            à reconsidérer plutôt qu'à contourner.
            """)
    }
}
