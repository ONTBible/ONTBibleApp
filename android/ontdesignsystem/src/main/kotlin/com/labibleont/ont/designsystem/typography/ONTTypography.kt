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

    /** Niveau 2 — une glose. */
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
