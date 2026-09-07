package com.labibleont.ont.designsystem.typography

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp
import com.labibleont.ont.designsystem.tokens.ONTColors
import com.labibleont.ont.kit.reader.ReadingFont
import com.labibleont.ont.kit.reader.ReadingTheme

/**
 * La fabrique de styles, pour un thème et une taille donnés.
 *
 * ## Des `SpanStyle` et non des styles de vue
 *
 * Tous les niveaux du texte cohabitent **dans une même ligne** : un verset peut
 * porter du corps, un intraduisible, une glose et de l'hébreu sans qu'aucun ne
 * commence un nouveau paragraphe. Un style de composable ne saurait pas les
 * mêler ; un `SpanStyle` se pose sur une plage d'un `AnnotatedString`, ce qui
 * est exactement la granularité du problème.
 *
 * C'est le pendant direct des `AttributedString` de la liseuse iOS.
 *
 * ## La taille arrive déjà mise à l'échelle
 *
 * [size] est en `sp`, donc le facteur d'accessibilité du système s'y applique
 * tout seul — l'équivalent Android du Dynamic Type. Aucun plafond n'est posé :
 * un lecteur qui monte le curseur le fait parce qu'il ne voit pas autrement.
 */
public data class ONTTypography(
    /** La taille du corps, en `sp`. */
    public val size: Float,
    public val theme: ReadingTheme,
    /** La fonte du corps, choisie par le lecteur. */
    public val face: ReadingFont = ReadingFont.LITERATA,
) {
    private val body = ONTFonts.family(face)
    private val ink: Color get() = ONTColors.ink(theme)

    /** L'encre du niveau 2. */
    private val soft: Color get() = ONTColors.inkSoft(theme)

    /**
     * Les gloses sont plus petites : c'est la voix du projet, elle ne doit pas
     * concurrencer celle du texte.
     */
    private val glossSize: Float get() = size * 0.86f

    private val Float.pt: TextUnit get() = this.sp

    // ── Les styles ──────────────────────────────────────────────────────

    /** Titre d'unité. */
    public val display: SpanStyle
        get() = SpanStyle(
            fontFamily = ONTFonts.display,
            fontWeight = FontWeight.SemiBold,
            fontSize = (size * 1.7f).pt,
            color = ONTColors.inkStrong(theme),
        )

    /**
     * Titre de section, à l'intérieur d'une unité.
     *
     * La couleur passe par le thème depuis qu'on a mesuré : le bordeaux posé en
     * dur donnait 1,23:1 sur le fond sombre. Un titre invisible.
     */
    public val heading: SpanStyle
        get() = SpanStyle(
            fontFamily = ONTFonts.display,
            fontWeight = FontWeight.SemiBold,
            fontSize = (size * 1.25f).pt,
            color = ONTColors.brandInk(theme),
        )

    /** Niveau 1 — le corps de la traduction. */
    public val corpus: SpanStyle
        get() = SpanStyle(fontFamily = body, fontSize = size.pt, color = ink)

    /** Niveau 1 — un intraduisible, touchable. */
    public val term: SpanStyle
        get() = SpanStyle(
            fontFamily = body,
            fontSize = size.pt,
            color = ONTColors.accent(theme),
        )

    /**
     * Niveau 1 — un **Shem**, touchable.
     *
     * Même graisse et même corps que l'intraduisible : ce sont deux couches du
     * texte, pas deux importances. Seule la teinte les sépare, et c'est
     * suffisant parce qu'elles ne se rencontrent presque jamais dans la même
     * phrase.
     */
    public val shem: SpanStyle
        get() = SpanStyle(
            fontFamily = body,
            fontSize = size.pt,
            color = ONTColors.shem(theme),
        )

    /**
     * Niveau 1 — une accentuation, qui ne se touche pas.
     *
     * Semi-gras **et** colorée : la couleur seule ne suffit pas — un lecteur
     * daltonien ne verrait rien, et l'accessibilité n'est pas une option sur un
     * texte qu'on lit des heures.
     */
    public val accentuation: SpanStyle
        get() = SpanStyle(
            fontFamily = body,
            fontWeight = FontWeight.SemiBold,
            fontSize = size.pt,
            color = ONTColors.accentuation(theme),
        )

    /**
     * Niveau 2 — une glose.
     *
     * **Deux signaux, jamais la pente.** Elle se distingue par la taille et par
     * la couleur, et c'est délibéré : Gloire a un kératocône, et une cornée
     * déformée diffuse la lumière au point que l'inclinaison des jambages
     * devient le pire discriminant possible. Un italique seul aurait paru
     * élégant et n'aurait rien distingué.
     *
     * L'italique du niveau 3 — [translit] — vient **par-dessus** ces deux
     * signaux, jamais à leur place.
     */
    public val gloss: SpanStyle
        get() = SpanStyle(fontFamily = body, fontSize = glossSize.pt, color = soft)

    /** Niveau 3 — la translittération, latine italique. */
    public val translit: SpanStyle
        get() = SpanStyle(
            fontFamily = body,
            fontSize = glossSize.pt,
            fontStyle = FontStyle.Italic,
            color = soft,
        )

    /** Niveau 3 — l'hébreu. */
    public val hebrew: SpanStyle
        get() = SpanStyle(
            fontFamily = ONTFonts.hebrew,
            fontSize = (size * ONTFonts.HEBREW_SCALE).pt,
            color = ink.copy(alpha = 0.85f),
        )

    /** L'hébreu à l'intérieur d'une glose ou d'une translittération. */
    public val hebrewSmall: SpanStyle
        get() = SpanStyle(
            fontFamily = ONTFonts.hebrew,
            fontSize = (glossSize * ONTFonts.HEBREW_SCALE).pt,
            color = ink.copy(alpha = 0.85f),
        )

    /** Le numéro de verset, en exposant. */
    public val verseNumber: SpanStyle
        get() = SpanStyle(
            fontFamily = body,
            fontSize = (size * 0.62f).pt,
            color = ONTColors.accent(theme),
        )

    /** Le décalage vertical du numéro de verset. */
    public val verseBaselineOffset: Float get() = size * 0.34f

    /**
     * Une ponctuation d'appareil — parenthèses, crochets de glose.
     *
     * Non italique, délibérément : une italique incline aussi les crochets, et
     * un « [ » penché se confond avec une barre oblique. L'appareil doit rester
     * droit même quand ce qu'il encadre ne l'est pas.
     */
    public val apparatus: SpanStyle
        get() = SpanStyle(fontFamily = body, fontSize = glossSize.pt, color = soft)
}

/**
 * L'interligne naturel de Literata, en multiples du corps.
 *
 * Relevé dans sa table `hhea` — 1177 + 308 pour 1000 unités par cadratin —
 * et non estimé. C'est la valeur que la liseuse iOS a mesurée le jour où un
 * interligne « à peu près 1,35 » s'est révélé faux de dix pour cent.
 *
 * ## Pourquoi Android en a besoin alors qu'iOS ne le nomme pas
 *
 * Les deux plateformes ne comptent pas la même chose. `SwiftUI.lineSpacing`
 * **ajoute** des points à l'interligne que la fonte porte déjà ; Compose
 * `lineHeight` **fixe** la hauteur totale et efface le naturel. Le même
 * réglage rendait donc deux textes différents : au défaut de 0,5, iOS
 * composait à 1,735 fois le corps et Android à 1,500 — treize et demi pour
 * cent plus serré, et jusqu'à vingt-quatre pour cent au bas du curseur.
 *
 * Pour retrouver la même page, Compose doit donc rajouter à la main ce que
 * SwiftUI tenait de la fonte.
 */
public const val INTERLIGNE_NATUREL: Float = 1.485f

/**
 * L'interligne total, en multiples du corps, pour un réglage donné.
 *
 * La formule est celle d'iOS — `scaledTextSize × lineSpacing × 0.5` ajouté au
 * naturel —, ramenée en multiple parce que Compose raisonne ainsi.
 */
public fun interligne(reglage: Double): Float =
    INTERLIGNE_NATUREL + reglage.toFloat() * 0.5f
