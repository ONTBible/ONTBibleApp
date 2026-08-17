import ONTDesignSystem
import ONTKit
import SwiftUI
import Testing
import UIKit

/// Les contrastes de la palette, mesurés.
///
/// ## Pourquoi ces tests existent
///
/// Une couleur illisible ne se voit pas dans une relecture de code. La ligne
/// fautive dit `ONTColors.burgundy` — le nom de la marque, sur une vue qui
/// affiche un titre. Rien n'alerte. Il faut ouvrir l'app, choisir le bon thème,
/// aller sur le bon écran, et *regarder*.
///
/// C'est ce qui s'est passé : le bordeaux du logo servait d'encre à quinze
/// endroits, et rendait les lemmes du lexique, les intitulés de section et
/// l'onglet actif invisibles sur les deux thèmes sombres — **1,06:1** sur une
/// ligne de liste, soit du bordeaux sur du bordeaux. Le défaut est arrivé avec
/// le thème sombre et y est resté ; le thème mystique n'a fait que le montrer.
///
/// Ces tests parcourent **tous les thèmes × tous les rôles**. Un thème ajouté
/// demain est mesuré sans qu'on y pense, et un rôle qui passe sous le seuil
/// fait tomber la suite au lieu d'attendre qu'on tombe dessus.
struct ThemeContrastTests {
    /// Le rapport de contraste WCAG entre deux couleurs.
    ///
    /// Les couleurs de rôle peuvent être translucides — `inkSoft` l'est sur
    /// trois thèmes sur quatre. Une opacité ne se mesure pas dans l'absolu :
    /// on l'aplatit d'abord sur le fond, sans quoi le calcul porte sur une
    /// couleur que personne ne voit.
    private func contraste(_ avant: Color, sur fond: Color) -> Double {
        let f = composantes(fond)
        let a = composantes(avant)
        let aplati = (
            r: a.r * a.alpha + f.r * (1 - a.alpha),
            g: a.g * a.alpha + f.g * (1 - a.alpha),
            b: a.b * a.alpha + f.b * (1 - a.alpha)
        )
        let l1 = luminance(aplati)
        let l2 = luminance((r: f.r, g: f.g, b: f.b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    private func composantes(_ couleur: Color) -> (r: Double, g: Double, b: Double, alpha: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(couleur).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }

    private func luminance(_ c: (r: Double, g: Double, b: Double)) -> Double {
        func canal(_ v: Double) -> Double {
            v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * canal(c.r) + 0.7152 * canal(c.g) + 0.0722 * canal(c.b)
    }

    // MARK: - Le corps du texte

    @Test("l'encre du corps est lisible sur son fond", arguments: ReadingTheme.allCases)
    func bodyInkOnBackground(_ theme: ReadingTheme) {
        let mesure = contraste(ONTColors.ink(theme), sur: ONTColors.background(theme))
        // 7:1, le seuil AAA : c'est un texte qu'on lit des heures, pas une
        // étiquette qu'on parcourt.
        #expect(mesure >= 7, "\(theme.label) : encre du corps à \(arrondi(mesure)):1, seuil AAA 7:1")
    }

    @Test("le niveau 2 reste lisible", arguments: ReadingTheme.allCases)
    func softInkOnBackground(_ theme: ReadingTheme) {
        let mesure = contraste(ONTColors.inkSoft(theme), sur: ONTColors.background(theme))
        #expect(mesure >= 4.5, "\(theme.label) : glose à \(arrondi(mesure)):1, seuil AA 4,5:1")
    }

    /// Le niveau 2 doit **reculer** derrière le corps, et pas seulement rester
    /// lisible.
    ///
    /// ## Pourquoi un second test, et pourquoi deux seuils
    ///
    /// Le plancher ci-dessus n'empêche rien : on peut le tenir tout en calant
    /// les quatre thèmes sur un même rapport, ce qui est précisément l'erreur
    /// qu'on a corrigée. Les quatre visaient 6,5:1, et en parchemin on ne
    /// distinguait plus la traduction de son commentaire.
    ///
    /// Un même rapport ne produit pas le même recul selon le fond. Sur fond
    /// sombre, un texte clair **rayonne** : le corps éclaire, la glose recule
    /// d'elle-même. Sur fond clair, les deux sont de l'encre posée, et il faut
    /// un écart de clarté bien plus grand pour obtenir le même effacement.
    ///
    /// D'où deux seuils, sur la clarté perçue (L* de la CIE) plutôt que sur le
    /// rapport de contraste — c'est L* qui dit ce que l'œil range devant et
    /// derrière.
    @Test("le niveau 2 recule derrière le corps", arguments: ReadingTheme.allCases)
    func softInkRecedesFromInk(_ theme: ReadingTheme) {
        let fond = ONTColors.background(theme)
        let ecart = abs(clarte(ONTColors.ink(theme), sur: fond)
            - clarte(ONTColors.inkSoft(theme), sur: fond))
        // Les fonds clairs n'ont pas la halation pour les aider.
        let seuil: Double = theme.isDark ? 18 : 30
        #expect(
            ecart >= seuil,
            "\(theme.label) : la glose ne recule que de ΔL* \(arrondi(ecart)), il en faut \(seuil)"
        )
    }

    /// La clarté perçue d'une couleur, une fois posée sur son fond.
    ///
    /// L* de la CIE, sur l'échelle 0–100 : c'est la grandeur qui suit l'œil,
    /// là où la luminance brute suit le photomètre. Deux couleurs de même
    /// luminance peuvent se ranger l'une devant l'autre ; deux couleurs de L*
    /// éloignés, non.
    private func clarte(_ couleur: Color, sur fond: Color) -> Double {
        let f = composantes(fond)
        let c = composantes(couleur)
        let y = luminance((
            r: c.r * c.alpha + f.r * (1 - c.alpha),
            g: c.g * c.alpha + f.g * (1 - c.alpha),
            b: c.b * c.alpha + f.b * (1 - c.alpha)
        ))
        return y > 0.008856 ? 116 * pow(y, 1.0 / 3) - 16 : 903.3 * y
    }

    // MARK: - Les couleurs de marque employées comme encre

    @Test("la marque employée comme encre se détache du fond", arguments: ReadingTheme.allCases)
    func brandInkOnBackground(_ theme: ReadingTheme) {
        let mesure = contraste(ONTColors.brandInk(theme), sur: ONTColors.background(theme))
        // 3:1 : ce rôle porte des titres de section et des libellés d'interface,
        // pas du texte courant.
        #expect(mesure >= 3, "\(theme.label) : marque-encre à \(arrondi(mesure)):1, seuil 3:1")
    }

    /// Le cas qui manquait, et par lequel le défaut est entré.
    ///
    /// Une ligne de liste n'est pas le fond de la page : sur parchemin elle est
    /// plus claire, sur la nuit elle est plus **claire** aussi. Un rôle mesuré
    /// sur le seul fond de page peut donc passer et rester illisible là où il
    /// s'affiche vraiment — les lemmes du lexique sont sur une surface.
    @Test("la marque employée comme encre se détache d'une surface", arguments: ReadingTheme.allCases)
    func brandInkOnSurface(_ theme: ReadingTheme) {
        let mesure = contraste(ONTColors.brandInk(theme), sur: ONTColors.surface(theme))
        #expect(mesure >= 3, "\(theme.label) : marque-encre sur surface à \(arrondi(mesure)):1")
    }

    @Test("l'accent doré se détache du fond", arguments: ReadingTheme.allCases)
    func accentOnBackground(_ theme: ReadingTheme) {
        let mesure = contraste(ONTColors.accent(theme), sur: ONTColors.background(theme))
        #expect(mesure >= 3, "\(theme.label) : accent à \(arrondi(mesure)):1, seuil 3:1")
    }

    @Test("l'accent doré se détache d'une surface", arguments: ReadingTheme.allCases)
    func accentOnSurface(_ theme: ReadingTheme) {
        let mesure = contraste(ONTColors.accent(theme), sur: ONTColors.surface(theme))
        #expect(mesure >= 3, "\(theme.label) : accent sur surface à \(arrondi(mesure)):1")
    }

    @Test("le terme important se détache du fond", arguments: ReadingTheme.allCases)
    func importantOnBackground(_ theme: ReadingTheme) {
        let mesure = contraste(ONTColors.important(theme), sur: ONTColors.background(theme))
        // Du texte courant, dans une phrase : le seuil plein.
        #expect(mesure >= 4.5, "\(theme.label) : terme important à \(arrondi(mesure)):1, seuil AA 4,5:1")
    }

    // MARK: - Ce qui se pose sur un aplat de marque

    /// Le cas des boutons de connexion.
    ///
    /// Un aplat de marque — capsule bordeaux, capsule dorée — porte du texte et
    /// des symboles. Rien ne garantissait qu'ils s'en détachent : l'icône des
    /// boutons « Continuer avec… » était peinte de la teinte d'accent du
    /// formulaire, c'est-à-dire de la couleur exacte de la capsule.
    @Test("ce qui se pose sur un aplat de marque s'en détache", arguments: ReadingTheme.allCases)
    func onBrandOverBrandInk(_ theme: ReadingTheme) {
        let mesure = contraste(ONTColors.onBrand(theme), sur: ONTColors.brandInk(theme))
        // 4,5:1 : ces capsules portent des libellés qu'on lit, pas des ornements.
        #expect(mesure >= 4.5, "\(theme.label) : texte sur aplat de marque à \(arrondi(mesure)):1")
    }

    /// L'or du logo porte du texte sur la carte du verset du jour et dans le
    /// widget, où le fond est le bordeaux de la marque quel que soit le thème.
    @Test("l'or se détache du bordeaux de la carte")
    func goldOverBurgundyCard() {
        let mesure = contraste(ONTColors.gold, sur: ONTColors.burgundy)
        #expect(mesure >= 4.5, "or sur bordeaux à \(arrondi(mesure)):1")
    }

    // MARK: - La règle qui a été enfreinte

    /// Le bordeaux brut ne va **que** sur un fond qu'on choisit.
    ///
    /// Ce test ne mesure pas un rendu, il énonce la règle : `burgundy` est une
    /// couleur de fond de carte, avec de l'or dessus. Employée comme encre elle
    /// tombe à 1,2:1 sur les thèmes sombres. C'est `brandInk(_:)` qu'il faut.
    @Test("le bordeaux brut serait illisible comme encre sur les fonds sombres")
    func rawBurgundyWouldBeUnreadable() {
        for theme in ReadingTheme.allCases where theme.isDark {
            let mesure = contraste(ONTColors.burgundy, sur: ONTColors.background(theme))
            #expect(
                mesure < 3,
                """
                \(theme.label) : le bordeaux brut passe désormais à \(arrondi(mesure)):1 sur ce fond.
                Si c'est voulu, ce test n'a plus lieu d'être — mais tant qu'il tient,
                il rappelle pourquoi `brandInk(_:)` existe.
                """
            )
        }
    }

    private func arrondi(_ v: Double) -> String { String(format: "%.2f", v) }
}
