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

    // MARK: - La nuit du site

    /// Le fond de `ontbible.com` — **#18090D**.
    ///
    /// Relevé dans `style/main.css` de la webapp, où il se nomme
    /// `--color-nuit`. Ce n'est pas un noir : c'est un aubergine si sombre
    /// qu'on le prend pour du noir jusqu'à ce que l'or se pose dessus.
    ///
    /// Les valeurs viennent de là et n'ont pas à être retouchées ici. Le site
    /// et la liseuse partagent déjà l'or — `--color-or` **est** `gold` — et
    /// `--color-important` **est** le bordeaux clair du thème sombre, au
    /// millième près. La parenté n'est pas une ressemblance qu'on entretient,
    /// c'est la même palette employée deux fois.
    static let nuit = Color(red: 0.094, green: 0.035, blue: 0.051)
    /// `--color-surface` du site — **#261016**.
    static let nuitSurface = Color(red: 0.149, green: 0.063, blue: 0.086)
    /// `--color-encre` du site — **#CFC5B9**, 11,4:1 sur la nuit.
    static let nuitEncre = Color(red: 0.812, green: 0.773, blue: 0.725)

    // MARK: - Surfaces de lecture

    public static func background(_ theme: ReadingTheme) -> Color {
        switch theme {
        case .parchment: Color(red: 0.98, green: 0.96, blue: 0.92)
        case .light: Color(white: 1)
        case .dark: Color(red: 0.09, green: 0.08, blue: 0.09)
        case .mystique: nuit
        }
    }

    public static func ink(_ theme: ReadingTheme) -> Color {
        switch theme {
        case .parchment: Color(red: 0.16, green: 0.13, blue: 0.11)
        case .light: Color(white: 0.1)
        case .dark: Color(red: 0.88, green: 0.86, blue: 0.83)
        case .mystique: nuitEncre
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
        //
        // La webapp est arrivée à la même teinte de son côté, sous le nom
        // `--color-important` : **#D87994**, au millième près. On ne l'a pas
        // alignée après coup — deux fonds sombres bordeaux appellent le même
        // rose pour s'en détacher.
        case .dark, .mystique: Color(red: 0.847, green: 0.475, blue: 0.580)
        }
    }

    /// L'or lisible sur le fond du thème — sur parchemin l'or pur passe mal.
    public static func accent(_ theme: ReadingTheme) -> Color {
        theme.isDark ? gold : goldDeep
    }

    /// L'encre d'un **titre** — plus vive que celle du corps.
    ///
    /// Le site distingue `encre` de `encre-vive` ; l'app ne le faisait pas, et
    /// ses titres d'unité retombaient sur l'encre du corps. Sur la nuit, c'est
    /// 11,4:1 au lieu de 15,3:1 — un titre qui ne domine plus rien.
    public static func inkStrong(_ theme: ReadingTheme) -> Color {
        switch theme {
        // `--color-encre-vive` du site — **#EDE3D6**.
        case .mystique: Color(red: 0.929, green: 0.890, blue: 0.839)
        case .parchment, .light, .dark: ink(theme)
        }
    }

    /// L'encre du **niveau 2** — la glose, la translittération, l'appareil.
    ///
    /// Toutes les valeurs visent **6,5:1** sur le fond de leur thème, ce qui
    /// est le niveau que le site tient pour sa glose. Un seul chiffre pour les
    /// quatre : le niveau 2 doit s'effacer autant partout, sinon il concurrence
    /// le corps sur un thème et disparaît sur un autre.
    ///
    /// L'encre du corps rabattue à 62 %, qui servait avant, donnait :
    ///
    ///     parchemin  4,38:1   sous le seuil AA de 4,5:1
    ///     clair      4,90:1
    ///     sombre     5,74:1
    ///     mystique   4,91:1   sous le seuil
    ///
    /// Deux thèmes sur quatre étaient donc en dessous du minimum, et personne
    /// ne pouvait le voir : une opacité ne dit pas ce qu'elle produit. C'est le
    /// test de contrastes qui l'a signalé, pas une relecture.
    public static func inkSoft(_ theme: ReadingTheme) -> Color {
        switch theme {
        // `--color-encre-douce` du site — **#9D948B**.
        case .mystique: Color(red: 0.616, green: 0.580, blue: 0.545)
        case .parchment: ink(theme).opacity(0.75)
        case .light: ink(theme).opacity(0.71)
        case .dark: ink(theme).opacity(0.67)
        }
    }

    /// La couleur de marque **employée comme encre**.
    ///
    /// Le bordeaux du logo sur les fonds clairs, l'**or** sur les fonds sombres.
    ///
    /// ## Pourquoi ce rôle a dû exister
    ///
    /// `burgundy` est une couleur de **marque** : elle est faite pour être un
    /// fond de carte, avec de l'or dessus. Quinze vues s'en servaient pourtant
    /// comme encre — un titre de section, un lemme du lexique, un intitulé de
    /// corpus, la teinte globale de l'app. C'était juste tant que tous les
    /// fonds étaient clairs, et c'est resté écrit ainsi quand le thème sombre
    /// est arrivé. Mesuré :
    ///
    ///     fond          burgundy   ce rôle
    ///     parchemin      13,6:1     13,6:1
    ///     clair          14,8:1     14,8:1
    ///     sombre          1,2:1      9,8:1
    ///     mystique        1,3:1     10,4:1
    ///
    /// 1,2:1, c'est du bordeaux sur du bordeaux. Les lemmes du lexique, les
    /// intitulés de section et l'onglet actif étaient **invisibles** sur les
    /// deux thèmes sombres, et le sont restés parce qu'un contraste ne se
    /// remarque pas dans une relecture de code : la ligne fautive dit
    /// simplement le nom de la marque.
    ///
    /// **Ne jamais écrire `ONTColors.burgundy` dans une couleur de texte.**
    /// La marque brute ne va que sur un fond qu'on choisit — `BurgundyCard`,
    /// le fond du widget. Pour de l'encre, ce rôle ; pour un accent doré,
    /// `accent(_:)`.
    public static func brandInk(_ theme: ReadingTheme) -> Color {
        theme.isDark ? gold : burgundy
    }

    /// Ce qui se pose **sur** un aplat de marque — texte et symboles.
    ///
    /// La couleur du fond de la page, retournée contre elle-même : encre claire
    /// sur bordeaux, nuit sur or. C'est la règle du site, dont le bouton
    /// principal est `bg-or text-nuit`.
    ///
    /// Elle existe parce qu'un aplat de marque ne se traite pas comme le reste.
    /// Les boutons de connexion posaient un `Label` sur une capsule bordeaux :
    /// dans un `Form`, l'icône d'un `Label` prend la **teinte d'accent**, qui
    /// était ce même bordeaux. L'icône était donc peinte de la couleur exacte
    /// de ce qu'elle recouvre — invisible, et invisible dans le code aussi,
    /// puisque personne ne l'avait colorée.
    public static func onBrand(_ theme: ReadingTheme) -> Color {
        background(theme)
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
        case .mystique: nuitSurface
        }
    }

    /// Le filet de séparation entre deux lignes.
    ///
    /// En mystique, un filet d'**or** et non d'encre — c'est `--color-filet`
    /// du site, soit l'or à 18 %. Sur une nuit aubergine, un filet d'encre
    /// grise fait sale ; l'or reste dans la famille du fond.
    public static func separator(_ theme: ReadingTheme) -> Color {
        switch theme {
        case .mystique: gold.opacity(0.18)
        case .dark: ink(theme).opacity(0.16)
        case .parchment, .light: ink(theme).opacity(0.10)
        }
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

    /// L'opacité de ce qui n'est **pas** sélectionné.
    ///
    /// Le procédé vient de Bible Strong : on ne marque pas le verset désigné,
    /// on efface le reste. Il tient à une condition — que les deux modes de
    /// lecture effacent pareil. En blocs, c'est la vue du verset qui s'estompe ;
    /// en prose continue, il n'y a plus de vue par verset et c'est le moteur de
    /// rendu qui doit le faire, run par run. Deux chemins, une seule valeur :
    /// écrite deux fois, elle aurait dérivé au premier réglage.
    public static let dimmedOpacity: Double = 0.32
}
