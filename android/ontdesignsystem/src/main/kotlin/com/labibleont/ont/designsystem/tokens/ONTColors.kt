package com.labibleont.ont.designsystem.tokens

import androidx.compose.ui.graphics.Color
import com.labibleont.ont.kit.reader.HighlightColor
import com.labibleont.ont.kit.reader.ReadingTheme

/**
 * La palette.
 *
 * Relevée sur le combination mark de La Bible ONT — le bordeaux et l'or
 * viennent du logo, pas d'un choix arbitraire. Le parchemin les accompagne
 * parce qu'une liseuse ne se lit pas sur du blanc pur.
 *
 * **Ne jamais écrire une couleur en dur ailleurs.** Une teinte qui n'est pas
 * ici est une teinte qu'on ne pourra pas décliner en thème sombre.
 *
 * ## Les valeurs sont les mêmes qu'en Swift, à l'entier près
 *
 * Le Swift écrit ses couleurs en composantes flottantes, mais sa
 * documentation donne partout l'hexadécimal — et c'est l'hexadécimal qui est
 * la source : il vient du logo, ou de `main.css` du site. On l'écrit donc
 * directement ici, plutôt que de recopier des flottants dont on ne verrait pas
 * qu'ils ont dérivé.
 *
 * Le site et les deux liseuses n'emploient pas des palettes qui se
 * **ressemblent** : c'est la même palette, employée trois fois.
 *
 * ## Material You est écarté, délibérément
 *
 * La couleur dynamique d'Android repeindrait l'app aux teintes du fond d'écran
 * du lecteur. C'est la meilleure idée de Material 3, et la seule qu'on refuse :
 * ces couleurs-ci sont la marque, et un lecteur qui ouvre l'ONT doit y trouver
 * l'ONT. Tout le reste de Material — gestes, feuilles du bas, retour prédictif
 * — est pris tel quel.
 */
public object ONTColors {

    // ─────────────────────────────────────────────────────────────────────
    // La marque
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Le bordeaux du logo — fond des cartes, accent, titres de section.
     *
     * Relevé au pixel sur `La Bible ONT - Combination Mark.png` : **#421B26**.
     */
    public val burgundy: Color = Color(0xFF421B26)

    /** L'or du logo — texte sur bordeaux, filets, numéros de verset. **#CDBE83**. */
    public val gold: Color = Color(0xFFCDBE83)

    /**
     * L'or assombri — les intraduisibles sur fond clair, où l'or pur n'aurait
     * pas un contraste suffisant. **#A6874F**.
     */
    public val goldDeep: Color = Color(0xFFA6874F)

    /**
     * La terre brûlée des **Shemot** — les noms propres. **#603518** le jour.
     *
     * Choisie par Gloire parmi cinq candidats rendus dans les quatre thèmes, sur
     * un critère mesuré : l'écart CIE Lab contre les trois couches déjà
     * présentes, avec un plancher de 25. Elle donne **ΔE 34 de l'or profond, 33
     * du bordeaux, 29 de l'encre**.
     *
     * Le vieil or qu'il voulait d'abord était impossible — bronze à ΔE 11 de
     * l'or, brun doré à 17, cuivre à 20. Le lecteur n'aurait plus distingué un
     * concept d'un nom, ce qui est précisément la distinction que cette couche
     * existe pour porter.
     */
    public val burntEarth: Color = Color(0xFF603518)

    /** La même, éclaircie pour un fond sombre — **#A3704D**, teinte constante. */
    public val burntEarthLight: Color = Color(0xFFA3704D)

    // ─────────────────────────────────────────────────────────────────────
    // La nuit du site
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Le fond de `ontbible.com` — **#18090D**, son `--color-nuit`.
     *
     * Ce n'est pas un noir : c'est un aubergine si sombre qu'on le prend pour
     * du noir jusqu'à ce que l'or se pose dessus.
     */
    public val nuit: Color = Color(0xFF18090D)

    /** `--color-surface` du site — **#261016**. */
    internal val nuitSurface: Color = Color(0xFF261016)

    /** `--color-encre` du site — **#CFC5B9**, 11,4:1 sur la nuit. */
    public val nuitEncre: Color = Color(0xFFCFC5B9)

    // ─────────────────────────────────────────────────────────────────────
    // Surfaces de lecture
    // ─────────────────────────────────────────────────────────────────────

    public fun background(theme: ReadingTheme): Color = when (theme) {
        ReadingTheme.PARCHMENT -> Color(0xFFFAF5EB)
        ReadingTheme.LIGHT -> Color(0xFFFFFFFF)
        ReadingTheme.DARK -> Color(0xFF171417)
        ReadingTheme.MYSTIQUE -> nuit
    }

    public fun ink(theme: ReadingTheme): Color = when (theme) {
        ReadingTheme.PARCHMENT -> Color(0xFF29211C)
        ReadingTheme.LIGHT -> Color(0xFF1A1A1A)
        ReadingTheme.DARK -> Color(0xFFE0DBD4)
        ReadingTheme.MYSTIQUE -> nuitEncre
    }

    /**
     * La couleur de l'**accentuation** — le troisième niveau de marquage.
     *
     * Le bordeaux du logo, éclairci. **Même teinte exactement — 343°** : la
     * parenté avec le fond des cartes et avec la marque doit se lire. Seules
     * la clarté et la saturation montent, parce que le bordeaux d'origine est
     * une *encre* et se confond avec celle du texte.
     *
     * Écart perceptuel à l'encre du parchemin, en CIE Lab :
     *
     *     #421B26  ΔE 18   l'origine — l'œil hésite, seul le gras marque
     *     #862742  ΔE 39   ici
     *     or       ΔE 44   les intraduisibles, pour comparaison
     *
     * En dessous de ΔE 25, une couleur ne se distingue plus de façon fiable
     * dans un texte courant.
     *
     * Sur fond sombre, le même bordeaux disparaît dans le noir. On remonte la
     * clarté à teinte constante jusqu'à 6,1:1 sur le fond. La webapp est
     * arrivée à la même teinte de son côté sous le nom `--color-important`,
     * **#D87994**, au millième près : deux fonds sombres bordeaux appellent le
     * même rose pour s'en détacher.
     */
    public fun accentuation(theme: ReadingTheme): Color = when (theme) {
        ReadingTheme.PARCHMENT, ReadingTheme.LIGHT -> Color(0xFF862742)
        ReadingTheme.DARK, ReadingTheme.MYSTIQUE -> Color(0xFFD87994)
    }

    /** L'or lisible sur le fond du thème — sur parchemin l'or pur passe mal. */
    public fun accent(theme: ReadingTheme): Color =
        if (theme.isDark) gold else goldDeep

    /** La couleur d'un **Shem**, selon la peau. */
    public fun shem(theme: ReadingTheme): Color =
        if (theme.isDark) burntEarthLight else burntEarth

    /**
     * L'encre d'un **titre** — plus vive que celle du corps.
     *
     * Le site distingue `encre` de `encre-vive` ; sans ce rôle, les titres
     * d'unité retombent sur l'encre du corps. Sur la nuit, c'est 11,4:1 au
     * lieu de 15,3:1 — un titre qui ne domine plus rien.
     */
    public fun inkStrong(theme: ReadingTheme): Color = when (theme) {
        // `--color-encre-vive` du site — **#EDE3D6**.
        ReadingTheme.MYSTIQUE -> Color(0xFFEDE3D6)
        else -> ink(theme)
    }

    /**
     * L'encre du **niveau 2** — la glose, la translittération, l'appareil.
     *
     * ## Deux régimes, et pourquoi il en faut deux
     *
     * Les quatre valeurs ont longtemps visé un seul chiffre, 6,5:1, au motif
     * que le niveau 2 doit s'effacer autant partout. Le raisonnement était
     * faux, et ça se voyait à l'usage avant de se calculer : en parchemin on ne
     * distinguait pas où finissait la traduction et où commençait le
     * commentaire ; en mystique, si.
     *
     *     parchemin   corps 15,4:1   glose 6,6:1   écart de clarté ΔL* 23,6
     *     mystique    corps 12,0:1   glose 6,9:1   écart de clarté ΔL* 18,2
     *
     * Le parchemin séparait **davantage** sur le papier et se lisait moins
     * bien. La cause est physique : la **halation**. Sur fond sombre, un texte
     * clair rayonne — le corps éclaire, et la glose recule d'elle-même. Sur
     * fond clair, les deux sont de l'encre posée ; seule la grisaille les
     * distingue, et il en faut beaucoup plus.
     *
     *     fonds clairs    ≈ 4,6:1   l'écart doit être franc
     *     fonds sombres   ≈ 6,5:1   la halation fait le reste
     *
     * ## Ce qu'on ne fait pas
     *
     * Descendre sous **4,5:1** : la glose est un niveau de lecture, pas une
     * décoration — on lit des pages qui n'en sont faites que d'elle.
     *
     * Virer au gris. `main.css` du site l'écrit : « Jamais de blanc pur, et
     * jamais un gris ». L'encre douce du parchemin garde donc exactement la
     * chaleur de son corps, R−B = +13 dans les deux.
     */
    public fun inkSoft(theme: ReadingTheme): Color = when (theme) {
        // `--color-encre-douce` du site — **#9D948B**, 6,50:1.
        ReadingTheme.MYSTIQUE -> Color(0xFF9D948B)
        // **#756E68** — 4,62:1 sur le parchemin, ΔL* 33,4.
        ReadingTheme.PARCHMENT -> Color(0xFF756E68)
        // **#757575** — 4,61:1 sur le blanc, ΔL* 40,0.
        ReadingTheme.LIGHT -> Color(0xFF757575)
        // Inchangé : sur fond sombre, la halation sépare déjà. ΔL* 24,1.
        ReadingTheme.DARK -> ink(theme).copy(alpha = 0.67f)
    }

    /**
     * La couleur de marque **employée comme encre**.
     *
     * Le bordeaux sur les fonds clairs, l'**or** sur les fonds sombres.
     *
     *     fond          burgundy   ce rôle
     *     parchemin      13,6:1     13,6:1
     *     clair          14,8:1     14,8:1
     *     sombre          1,2:1      9,8:1
     *     mystique        1,3:1     10,4:1
     *
     * 1,2:1, c'est du bordeaux sur du bordeaux. Côté iOS, quinze vues
     * employaient la marque brute comme encre : les lemmes du lexique, les
     * intitulés de section et l'onglet actif étaient **invisibles** sur les
     * deux thèmes sombres, et le sont restés parce qu'un contraste ne se
     * remarque pas en relecture — la ligne fautive dit simplement le nom de la
     * marque.
     *
     * **Ne jamais employer [burgundy] comme couleur de texte.** La marque brute
     * ne va que sur un fond qu'on choisit.
     */
    public fun brandInk(theme: ReadingTheme): Color =
        if (theme.isDark) gold else burgundy

    /**
     * Ce qui se pose **sur** un aplat de marque — texte et symboles.
     *
     * La couleur du fond de la page, retournée contre elle-même : encre claire
     * sur bordeaux, nuit sur or. C'est la règle du site, dont le bouton
     * principal est `bg-or text-nuit`.
     */
    public fun onBrand(theme: ReadingTheme): Color = background(theme)

    /**
     * Une surface posée sur le fond : ligne de liste, carte, feuille.
     *
     * Sur parchemin, un blanc pur détonnerait — la surface est un parchemin
     * plus clair, pas une autre matière. C'est ce qui donne à l'app une seule
     * couleur de peau au lieu de quatre écrans qui ne se ressemblent pas.
     */
    public fun surface(theme: ReadingTheme): Color = when (theme) {
        ReadingTheme.PARCHMENT -> Color(0xFFFFFCF6)
        ReadingTheme.LIGHT -> Color(0xFFFFFFFF)
        ReadingTheme.DARK -> Color(0xFF252225)
        ReadingTheme.MYSTIQUE -> nuitSurface
    }

    /**
     * Le filet de séparation entre deux lignes.
     *
     * En mystique, un filet d'**or** et non d'encre — c'est `--color-filet` du
     * site, soit l'or à 18 %. Sur une nuit aubergine, un filet d'encre grise
     * fait sale ; l'or reste dans la famille du fond.
     */
    public fun separator(theme: ReadingTheme): Color = when (theme) {
        ReadingTheme.MYSTIQUE -> gold.copy(alpha = 0.18f)
        ReadingTheme.DARK -> ink(theme).copy(alpha = 0.16f)
        ReadingTheme.PARCHMENT, ReadingTheme.LIGHT -> ink(theme).copy(alpha = 0.10f)
    }

    // ─────────────────────────────────────────────────────────────────────
    // Surlignage
    // ─────────────────────────────────────────────────────────────────────

    /**
     * La teinte réelle d'une couleur de surlignage.
     *
     * Le domaine ne connaît que le nom ([HighlightColor.GOLD]) ; la valeur est
     * ici, ce qui permet de retoucher la palette sans migrer les surlignages
     * déjà enregistrés.
     *
     * Cinq teintes tirées vers le pastel plutôt que le fluo d'écolier : un
     * surlignage se pose sur un texte qu'on lit longtemps, il ne doit ni crier
     * ni rendre le texte illisible.
     */
    public fun highlight(color: HighlightColor): Color = when (color) {
        HighlightColor.GOLD -> Color(0xFFE8C973)
        HighlightColor.OLIVE -> Color(0xFFB8C787)
        HighlightColor.SKY -> Color(0xFF9EC7DE)
        HighlightColor.ROSE -> Color(0xFFEBADAD)
        HighlightColor.VIOLET -> Color(0xFFC7B3DE)
    }

    /**
     * L'opacité d'un surlignage — assez pour se voir, assez peu pour que le
     * texte reste au premier plan.
     */
    public const val HIGHLIGHT_OPACITY: Float = 0.38f

    /**
     * L'opacité de ce qui n'est **pas** sélectionné.
     *
     * Le procédé vient de Bible Strong : on ne marque pas le verset désigné, on
     * efface le reste. Il tient à une condition — que les deux modes de lecture
     * effacent pareil. En blocs, c'est la vue du verset qui s'estompe ; en
     * prose continue, il n'y a plus de vue par verset et c'est le moteur de
     * rendu qui doit le faire, fragment par fragment. Deux chemins, une seule
     * valeur : écrite deux fois, elle aurait dérivé au premier réglage.
     */
    public const val DIMMED_OPACITY: Float = 0.32f
}
