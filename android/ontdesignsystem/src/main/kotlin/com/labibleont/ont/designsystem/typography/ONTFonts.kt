package com.labibleont.ont.designsystem.typography

import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import com.labibleont.ont.designsystem.R
import com.labibleont.ont.kit.reader.ReadingFont

/**
 * Les familles de fontes, telles que Compose les attend.
 *
 * Les fichiers sont ceux de la liseuse iOS, recopiés au build par
 * `copierLesFontes`. Les deux plateformes composent donc avec les **mêmes**
 * dessins de lettres — ce qui est la condition pour que les captures comparées
 * veuillent dire quelque chose.
 */
public object ONTFonts {

    /**
     * L'hébreu — Ezra SIL.
     *
     * Une fonte à part, et pas seulement pour l'écriture : elle porte le niqqud
     * et les te'amim à leur place. Une fonte système hébraïque les décrocherait
     * de leur consonne, et le niveau 3 deviendrait illisible sans que rien ne
     * le signale.
     */
    public val hebrew: FontFamily = FontFamily(Font(R.font.ezra_sil))

    /**
     * Les titres — Jost SemiBold.
     *
     * La géométrique de l'édition imprimée. Elle ne sert qu'aux titres : sur un
     * paragraphe entier, une géométrique fatigue là où une serif porte.
     */
    public val display: FontFamily = FontFamily(
        Font(R.font.jost_semi_bold, FontWeight.SemiBold),
    )

    /**
     * La famille correspondant au choix du lecteur.
     *
     * ## Georgia n'existe pas ici, et c'est documenté depuis iOS
     *
     * Le Swift le dit déjà : Georgia « appartient à Microsoft, donc
     * disparaîtrait hors d'iOS ». Nous y sommes. Android livre Noto Serif à sa
     * place — une serif système, robuste et familière, exactement le rôle que
     * Georgia tenait.
     *
     * On garde donc le choix dans les réglages plutôt que de le retirer : un
     * lecteur qui a réglé Georgia sur son iPhone et synchronise son compte
     * retrouve « la fonte du système » sur Android. Retirer l'entrée l'aurait
     * silencieusement renvoyé à Literata.
     */
    public fun family(font: ReadingFont): FontFamily = when (font) {
        ReadingFont.LITERATA -> FontFamily(
            Font(R.font.literata_regular, FontWeight.Normal),
            Font(R.font.literata_italic, FontWeight.Normal, FontStyle.Italic),
            Font(R.font.literata_semi_bold, FontWeight.SemiBold),
        )
        ReadingFont.EB_GARAMOND -> FontFamily(
            Font(R.font.ebgaramond_regular, FontWeight.Normal),
            Font(R.font.ebgaramond_italic, FontWeight.Normal, FontStyle.Italic),
            Font(R.font.ebgaramond_semi_bold, FontWeight.SemiBold),
        )
        ReadingFont.SPECTRAL -> FontFamily(
            Font(R.font.spectral_regular, FontWeight.Normal),
            Font(R.font.spectral_italic, FontWeight.Normal, FontStyle.Italic),
            Font(R.font.spectral_semi_bold, FontWeight.SemiBold),
        )
        ReadingFont.SOURCE_SERIF -> FontFamily(
            Font(R.font.source_serif4_regular, FontWeight.Normal),
            Font(R.font.source_serif4_italic, FontWeight.Normal, FontStyle.Italic),
            Font(R.font.source_serif4_semi_bold, FontWeight.SemiBold),
        )
        ReadingFont.NEWSREADER -> FontFamily(
            Font(R.font.newsreader_regular, FontWeight.Normal),
            Font(R.font.newsreader_italic, FontWeight.Normal, FontStyle.Italic),
            Font(R.font.newsreader_semi_bold, FontWeight.SemiBold),
        )
        ReadingFont.JOST -> FontFamily(
            Font(R.font.jost_regular, FontWeight.Normal),
            Font(R.font.jost_italic, FontWeight.Normal, FontStyle.Italic),
            Font(R.font.jost_semi_bold, FontWeight.SemiBold),
        )
        ReadingFont.GEORGIA -> FontFamily.Serif
    }

    /**
     * L'hébreu compose plus petit que le latin à taille égale : sans cette
     * correction, les deux écritures ne s'accordent pas sur une même ligne.
     */
    public const val HEBREW_SCALE: Float = 1.08f
}
