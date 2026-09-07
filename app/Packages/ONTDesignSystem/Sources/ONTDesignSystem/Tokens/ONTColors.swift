import ONTKit
import SwiftUI

#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif

/// La palette.
///
/// Relevée sur le combination mark de La Bible ONT — le bordeaux et l'or
/// viennent du logo, pas d'un choix arbitraire. Le parchemin les accompagne
/// parce qu'une liseuse ne se lit pas sur du blanc pur.
///
/// **Ne jamais écrire une couleur en dur ailleurs.** Une teinte qui n'est pas
/// ici est une teinte qu'on ne pourra pas décliner en thème sombre.
public enum ONTColors {
    // MARK: - Les rôles fonctionnels

    /// Le danger — supprimer, échouer, perdre.
    ///
    /// La braise de la gamme : une terre cuite qui penche bordeaux, pas un
    /// rouge d'alerte industriel — la maison garde sa voix jusque dans ses
    /// refus. 600 sur les fonds clairs (4,9:1 sur parchemin), 300 sur les
    /// nuits (10,3:1) — vérifié à la génération de la gamme.
    public static func danger(_ theme: ReadingTheme) -> Color {
        theme.isDark ? ONTGamme.braise300 : ONTGamme.braise600
    }

    /// Le voile derrière un propos de danger — pastille, fond de ligne.
    public static func dangerSurface(_ theme: ReadingTheme) -> Color {
        theme.isDark ? ONTGamme.braise900.opacity(0.55) : ONTGamme.braise100
    }

    /// Le succès — validé, synchronisé, verrouillé.
    ///
    /// **700 sur clair et non 600** : le cèdre 600 rend 4,4:1 sur parchemin,
    /// juste sous la barre des 4,5. Le cran au-dessus la passe sans changer de
    /// voix.
    public static func succes(_ theme: ReadingTheme) -> Color {
        theme.isDark ? ONTGamme.cedre300 : ONTGamme.cedre700
    }

    public static func succesSurface(_ theme: ReadingTheme) -> Color {
        theme.isDark ? ONTGamme.cedre900.opacity(0.55) : ONTGamme.cedre100
    }

    /// L'avertissement — en attente, brouillon, à vérifier.
    public static func avertissement(_ theme: ReadingTheme) -> Color {
        theme.isDark ? ONTGamme.ambre300 : ONTGamme.ambre600
    }

    public static func avertissementSurface(_ theme: ReadingTheme) -> Color {
        theme.isDark ? ONTGamme.ambre900.opacity(0.55) : ONTGamme.ambre100
    }

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

    /// La couleur de l'**accentuation** — le troisième niveau de marquage.
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
    public static func accentuation(_ theme: ReadingTheme) -> Color {
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

    /// La terre brûlée des **Shemot** — les noms propres.
    ///
    /// Une troisième couche de marquage, à côté de l'or des intraduisibles et
    /// du bordeaux de l'accentuation. Le choix de la teinte est celui de
    /// l'auteur, parmi cinq candidats rendus sur *Bereshit* 4:17 dans les
    /// quatre thèmes.
    ///
    /// **Un vieil or était impossible** : l'espace chaud est occupé. Bronze à
    /// ΔE 11 de l'or, brun doré à 17, cuivre à 20 — le lecteur n'aurait plus
    /// distingué un concept d'un nom.
    ///
    /// `#603518` le jour, remonté à teinte constante sur fond sombre comme le
    /// bordeaux devient rose.
    ///
    /// **Trois valeurs se sont succédé, et chacune tombait sur une mesure que
    /// la précédente n'avait pas faite** :
    ///
    ///     #A3704D   4,33:1   sous AA — mesuré contre les autres marquages,
    ///                        jamais contre le fond
    ///     #AA7550   4,66:1   au-dessus d'AA, mais le marquage le plus faible
    ///                        du thème sombre — l'or y est à 9,8, le bordeaux
    ///                        à 6,15
    ///     #BA8C6C   6,17:1   ici. À hauteur du bordeaux, qui est le seuil que
    ///                        ce projet s'est donné en le remontant lui-même
    ///
    /// Le commentaire de `accentuation` dit du rose qu'il tient « 6,1:1 sur le
    /// fond — au-delà du seuil AA ». **Le projet a donc un standard plus haut
    /// qu'AA**, écrit nulle part et tenu partout ; le Shem s'y range.
    ///
    /// `ContrastesTests` mesure maintenant tout ça au lieu de le commenter.
    public static func shem(_ theme: ReadingTheme) -> Color {
        theme.isDark
            ? Color(red: 0.729, green: 0.549, blue: 0.424)
            : Color(red: 0.376, green: 0.208, blue: 0.094)
    }

    /// Deux couleurs mêlées, sans dépendre d'une version du système.
    ///
    /// `Color.mix(with:by:)` fait la même chose et demande **macOS 15** quand
    /// les paquets en déclarent 14. L'appel ne casse alors que la compilation
    /// du Mac — invisible depuis un build iOS, qui est le seul qu'on lance
    /// d'ordinaire. C'est ainsi qu'on perd la vérification la plus rapide
    /// qu'on ait, et c'était déjà arrivé au dégradé de l'ouverture.
    ///
    /// L'interpolation est linéaire par composante, comme la sienne.
    public static func melange(_ depart: Color, vers arrivee: Color, part: Double) -> Color {
        let p = min(max(part, 0), 1)
        func composantes(_ c: Color) -> (Double, Double, Double) {
            #if canImport(UIKit)
                let n = UIColor(c).cgColor.components ?? [0, 0, 0]
            #else
                let n = NSColor(c).cgColor.components ?? [0, 0, 0]
            #endif
            let v = n.map(Double.init)
            return v.count > 2 ? (v[0], v[1], v[2]) : (v[0], v[0], v[0])
        }
        let a = composantes(depart)
        let b = composantes(arrivee)
        return Color(
            red: a.0 + (b.0 - a.0) * p,
            green: a.1 + (b.1 - a.1) * p,
            blue: a.2 + (b.2 - a.2) * p
        )
    }

    /// L'or lisible sur le fond du thème — sur parchemin l'or pur passe mal.
    public static func accent(_ theme: ReadingTheme) -> Color {
        theme.isDark ? gold : goldDeep
    }

    /// L'or du **numéro de verset, quand son verset est surligné**.
    ///
    /// Le numéro de verset est le seul rôle doré qui s'affiche par-dessus un
    /// surlignage — les autres (brouillon, puces, pied d'unité) sont hors du
    /// corps du texte. Et le sol change sous lui : ce n'est plus la page, c'est
    /// la page voilée à 0,38 par la teinte que le lecteur a posée.
    ///
    /// Sur les thèmes clairs, l'or n'a pas de quoi encaisser ce voile :
    ///
    ///     parchemin   page nue 3,11   sous voile 2,53
    ///     clair       page nue 3,39   sous voile 2,68
    ///
    /// **Le seuil de 3:1 n'est pas en cause — la valeur l'est.** Que l'or se
    /// repère au lieu de se lire est une décision inscrite, et elle tient. Mais
    /// elle a été prise en regardant la page nue, un sol où l'or a 0,11 de
    /// marge ; elle n'a jamais examiné celui-ci. Tenir la décision, c'est donc
    /// bouger la valeur là où le sol a changé — pas abaisser la barre.
    ///
    /// D'où `#967A48` sous voile, sur les thèmes clairs seulement : la même
    /// opération de clarté à teinte constante qui a donné le rose du bordeaux,
    /// la terre brûlée du Shem et la palette de nuit des surlignages. Elle rend
    /// 3,02:1 au pire voile. La marque du projet, elle, ne bouge pas d'un cran
    /// partout où elle s'affiche aujourd'hui.
    ///
    /// Sur les thèmes sombres, `accent` tient déjà par-dessus la palette de
    /// nuit — rien à corriger, donc rien à changer.
    public static func accentSurSurlignage(_ theme: ReadingTheme) -> Color {
        theme.isDark ? accent(theme) : Color(red: 0.588, green: 0.478, blue: 0.282)
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
    /// ## Ce qu'on calibre, et ce qu'on ne calibre plus
    ///
    /// Les quatre valeurs ont longtemps visé **6,5:1**, le niveau que le site
    /// tient pour sa glose. Un seul chiffre pour les quatre, au motif que le
    /// niveau 2 doit s'effacer autant partout.
    ///
    /// Le raisonnement était faux, et ça se voyait à l'usage bien avant de se
    /// calculer : en parchemin, on ne distinguait pas où finissait la
    /// traduction et où commençait le commentaire ; en mystique, si. Mesuré
    /// sur la même page, les deux, à l'écran :
    ///
    ///     parchemin   corps 15,4:1   glose 6,6:1   écart de clarté ΔL* 23,6
    ///     mystique    corps 12,0:1   glose 6,9:1   écart de clarté ΔL* 18,2
    ///
    /// Le parchemin séparait donc **davantage** sur le papier, et se lisait
    /// moins bien. La cause est physique, et le site la documente déjà pour
    /// l'autre bord : la **halation**. Sur fond sombre, un texte clair rayonne
    /// — le corps éclaire, et la glose recule d'elle-même. Sur fond clair, les
    /// deux sont de l'encre posée, de même épaisseur apparente ; seule la
    /// grisaille les distingue, et il en faut beaucoup plus.
    ///
    /// Un même rapport ne produit donc pas le même recul selon le fond. On
    /// calibre désormais sur le **recul perçu**, ce qui donne deux régimes :
    ///
    ///     fonds clairs    ≈ 4,6:1   l'écart doit être franc
    ///     fonds sombres   ≈ 6,5:1   la halation fait le reste
    ///
    /// ## Ce qu'on ne fait pas
    ///
    /// Descendre sous **4,5:1**. La glose est un niveau de lecture, pas une
    /// décoration : on lit des pages qui n'en sont faites que d'elle. Le test
    /// de contrastes tient ce plancher, et la marge est mince à dessein.
    ///
    /// Virer au gris. `main.css` du site l'écrit : « Jamais de blanc pur, et
    /// jamais un gris » — l'encre garde la chaleur du papier. L'encre douce du
    /// parchemin conserve donc exactement la chaleur de son corps, R−B = +13
    /// dans les deux. Celle du thème clair est neutre parce que son corps
    /// l'est déjà.
    ///
    /// ## L'état d'avant l'avant
    ///
    /// L'encre du corps rabattue à 62 % donnait 4,38:1 en parchemin et 4,91:1
    /// en mystique — deux thèmes sous le minimum, que personne ne pouvait voir
    /// parce qu'une opacité ne dit pas ce qu'elle produit. D'où les couleurs
    /// écrites en clair ici : une valeur qu'on lit vaut mieux qu'un facteur
    /// qu'il faut appliquer pour savoir où l'on est.
    public static func inkSoft(_ theme: ReadingTheme) -> Color {
        switch theme {
        // `--color-encre-douce` du site — **#9D948B**, 6,50:1.
        case .mystique: Color(red: 0.616, green: 0.580, blue: 0.545)
        // **#756E68** — 4,62:1 sur le parchemin, ΔL* 33,4.
        case .parchment: Color(red: 0.459, green: 0.431, blue: 0.408)
        // **#757575** — 4,61:1 sur le blanc, ΔL* 40,0.
        case .light: Color(red: 0.459, green: 0.459, blue: 0.459)
        // Inchangé : sur fond sombre, la halation sépare déjà. ΔL* 24,1.
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

    /// Ce qui se pose sur un aplat de marque quand on veut **l'or**, et non le
    /// simple retournement du fond.
    ///
    /// L'or ne peut pas être demandé directement, parce que l'aplat de marque
    /// **est déjà l'or** sur les thèmes sombres : `brandInk` rend `burgundy` en
    /// clair et `gold` en sombre. Écrire `.foregroundStyle(gold)` sur un bouton
    /// de connexion donnerait donc de l'or sur bordeaux en clair — ce qu'on
    /// veut — et de l'or sur or en sombre, c'est-à-dire un bouton vide.
    ///
    /// La règle tient en une phrase : **l'or va sur le bordeaux, et rien ne va
    /// sur l'or que le fond de la page**. En sombre, l'intention d'or est déjà
    /// portée par la capsule elle-même ; ce qui s'y pose retombe donc sur
    /// `onBrand`.
    public static func onBrandAccent(_ theme: ReadingTheme) -> Color {
        theme.isDark ? onBrand(theme) : gold
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
    /// La teinte d'un surlignage, **sur le thème où elle se pose**.
    ///
    /// ## Le seul jeton qui ignorait le thème
    ///
    /// `ink`, `accent`, `accentuation`, `shem`, `surface`, `separator` — tous
    /// prennent `ReadingTheme`. Le surlignage, non : il posait cinq pastels
    /// choisis pour du parchemin sur une nuit aubergine.
    ///
    /// **Ce que ça donnait**, voile à 0,38 sur fond sombre :
    ///
    ///     encre 5,5   or 4,1   bordeaux 2,6   Shem 1,9
    ///
    /// Le voile éclaircit le fond ; le texte, lui, avait été choisi pour du
    /// noir. Un intraduisible en or sur un surlignage or ne se distinguait plus
    /// du texte ordinaire — c'est-à-dire précisément le mot que le lecteur
    /// avait voulu retenir.
    ///
    /// ## Ce qui a été écarté
    ///
    /// **Baisser l'opacité ne marche pas.** Mesuré : sur fond clair on plafonne
    /// à 2,9 même à 0,12, parce que le coupable y est l'or à 3,11 *sans aucun
    /// surlignage*. Et sur fond sombre, où ça marcherait, il faut 0,12 — à ce
    /// niveau le surlignage ne se détache plus du fond que de 1,25:1. On aurait
    /// un surlignage invisible pour sauver un mot lisible.
    ///
    /// ## La palette de nuit
    ///
    /// Même teinte, clarté descendue jusqu'à ce que **tous** les marquages
    /// tiennent 4,6:1 sur **les deux** fonds sombres — pas seulement le plus
    /// clément. La saturation est conservée : c'est elle qui fait qu'on
    /// reconnaît « le bleu » et « le rose » l'un de l'autre à travers cinq
    /// surlignages.
    public static func highlight(_ color: HighlightColor, _ theme: ReadingTheme) -> Color {
        guard theme.isDark else { return highlightDeJour(color) }
        return switch color {
            case .gold: Color(red: 0.413, green: 0.323, blue: 0.068)
            case .olive: Color(red: 0.303, green: 0.347, blue: 0.163)
            case .sky: Color(red: 0.161, green: 0.358, blue: 0.469)
            case .rose: Color(red: 0.672, green: 0.168, blue: 0.168)
            case .violet: Color(red: 0.415, green: 0.257, blue: 0.593)
        }
    }

    /// Les cinq pastels d'origine, pour le parchemin et le blanc.
    private static func highlightDeJour(_ color: HighlightColor) -> Color {
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
