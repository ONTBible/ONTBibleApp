package com.labibleont.ont.designsystem

import androidx.compose.ui.graphics.Color
import com.labibleont.ont.designsystem.tokens.ONTColors
import com.labibleont.ont.kit.reader.HighlightColor
import com.labibleont.ont.kit.reader.ReadingTheme
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/**
 * Ce que le lecteur peut réellement lire.
 *
 * ## Pourquoi ce fichier existe
 *
 * Android n'avait **aucune** mesure de contraste. Les mêmes jetons qu'iOS, les
 * mêmes quatre peaux, et rien qui les éprouve. iOS en avait une, et c'est elle
 * qui a trouvé le défaut que ce fichier garde désormais fermé.
 *
 * ## Le sol voilé, que personne ne mesurait
 *
 * Un contraste se mesure d'ordinaire contre la page nue. Mais un verset
 * **surligné** ne se lit pas sur la page : il se lit sur le pastel que le
 * lecteur y a posé. C'est le cas le plus défavorable, et c'est aussi le passage
 * qui lui importe le plus — on ne surligne pas au hasard.
 *
 * Avant correction, en thème Mystique sous voile : encre 5,87, or du terme 5,37,
 * **Shem 2,37**. Le Shem n'était pas le coupable, il était le plus exposé — le
 * défaut était que `highlight` ignorait le thème, seul jeton du système dans ce
 * cas.
 *
 * ## Le seuil, et pourquoi il est à 4,5
 *
 * C'est le seuil AA du texte courant. Le projet tient plus haut sans l'avoir
 * écrit — le bordeaux est noté « 6,1:1 — au-delà du seuil AA » — mais un
 * plancher qu'on peut tenir vaut mieux qu'un idéal qu'on abaisse à la première
 * gêne.
 *
 * ## Contre quoi on tient, et ce n'est pas une norme
 *
 * **Gloire a un kératocône bilatéral.** La cornée déformée diffuse la lumière :
 * les bords se dédoublent, les contours proches se confondent. Le projet visait
 * au-dessus d'AA depuis des semaines sans que la raison soit écrite nulle part,
 * et une raison non écrite est une raison qu'on abaisse le jour où elle gêne.
 *
 * Ce qui en découle vaut au-delà du contraste, et touche ce fichier de près :
 *
 * - **distinguer deux niveaux de texte par la pente est le pire choix
 *   possible.** Un italique se lit à l'inclinaison des jambages, exactement ce
 *   qu'un halo efface. Ce qui tient est la **couleur**, la **taille**, l'**air**
 *   autour. `ONTTypography` fait déjà ainsi — une glose est plus petite *et*
 *   plus douce, l'italique du niveau 3 n'est qu'un renfort par-dessus deux
 *   signaux qui suffisent — mais ce fichier-ci est le seul qui le mesure ;
 * - **une dette de contraste n'est pas un détail cosmétique.** Les douze lignes
 *   inscrites plus bas sont l'or de la marque sur les peaux claires, et
 *   c'est bien une décision de Gloire — mais elle la prend en connaissant ce
 *   qu'elle lui coûte à lui, pas à un lecteur théorique.
 *
 * La note vient de la session iOS, le 30 août 2026, en portant la liseuse sur
 * Mac. Elle valait pour les trois plateformes et n'était écrite dans aucune.
 */
class ContrastesTest {

    private companion object {
        /** Le seuil AA du texte courant. */
        const val SEUIL = 4.5

        /** Le voile posé sur un verset surligné. */
        val VOILE = ONTColors.HIGHLIGHT_OPACITY.toDouble()

        /** Ce qu'on tolère d'écart avant de parler de changement. */
        const val JEU = 0.02

        /**
         * Les dettes reconnues — ce qui est sous le seuil et qu'on assume.
         *
         * ## Pourquoi on inscrit au lieu de corriger
         *
         * Toutes ces lignes sont **l'or profond du logo** sur les peaux claires.
         * C'est la couleur de la marque, relevée sur le combination mark : la
         * changer est une décision de Gloire, pas la nôtre. iOS a fait le même
         * choix pour la même raison.
         *
         * Inscrire vaut mieux que taire : le chiffre est là, il est daté, et le
         * jour où quelqu'un voudra le corriger il saura de combien.
         *
         * ## Le cliquet serre dans les deux sens
         *
         * Une valeur qui **empire** fait échouer — c'est l'usage attendu. Mais
         * une valeur qui **s'améliore** fait échouer aussi, en demandant que la
         * dette inscrite descende.
         *
         * Sans ce second sens un cliquet se desserre tout seul : on corrige à
         * moitié, la table garde l'ancien chiffre, et la moitié gagnée peut être
         * reperdue en silence sans qu'aucun test ne bouge. L'idée vient de la
         * session du site.
         */
        val DETTES: Map<String, Double> = mapOf(
            "l'or d'un intraduisible · PARCHMENT · page nue" to 3.12,
            "l'or d'un intraduisible · PARCHMENT · gold" to 2.68,
            "l'or d'un intraduisible · PARCHMENT · olive" to 2.60,
            "l'or d'un intraduisible · PARCHMENT · sky" to 2.60,
            "l'or d'un intraduisible · PARCHMENT · rose" to 2.55,
            "l'or d'un intraduisible · PARCHMENT · violet" to 2.54,
            "l'or d'un intraduisible · LIGHT · page nue" to 3.39,
            "l'or d'un intraduisible · LIGHT · gold" to 2.83,
            "l'or d'un intraduisible · LIGHT · olive" to 2.74,
            "l'or d'un intraduisible · LIGHT · sky" to 2.75,
            "l'or d'un intraduisible · LIGHT · rose" to 2.69,
            "l'or d'un intraduisible · LIGHT · violet" to 2.69,
        )
    }

    /**
     * Éprouve un cas — contre le seuil, ou contre sa dette inscrite.
     */
    private fun eprouver(cle: String, mesure: Double) {
        val dette = DETTES[cle]
        if (dette == null) {
            assertTrue(
                "$cle : ${"%.2f".format(mesure)}:1, sous $SEUIL — " +
                    "et aucune dette n'est inscrite pour ce cas",
                mesure >= SEUIL,
            )
            return
        }
        assertTrue(
            "$cle : ${"%.2f".format(mesure)}:1, alors que la dette inscrite est " +
                "${"%.2f".format(dette)} — c'est pire qu'avant",
            mesure >= dette - JEU,
        )
        assertTrue(
            "$cle : ${"%.2f".format(mesure)}:1, mieux que la dette inscrite de " +
                "${"%.2f".format(dette)} — descends-la à ${"%.2f".format(mesure)}, " +
                "sans quoi le gain pourra se reperdre en silence",
            mesure <= dette + JEU,
        )
    }

    /** La luminance relative, telle que WCAG la définit. */
    private fun luminance(c: Color): Double {
        fun canal(v: Float): Double {
            val d = v.toDouble()
            return if (d <= 0.03928) d / 12.92 else ((d + 0.055) / 1.055).pow(2.4)
        }
        return 0.2126 * canal(c.red) + 0.7152 * canal(c.green) + 0.0722 * canal(c.blue)
    }

    private fun rapport(a: Color, b: Color): Double {
        val la = luminance(a)
        val lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /** Le pastel posé sur la page, à l'opacité du surlignage. */
    private fun voile(pastel: Color, fond: Color): Color = Color(
        red = pastel.red * VOILE.toFloat() + fond.red * (1 - VOILE.toFloat()),
        green = pastel.green * VOILE.toFloat() + fond.green * (1 - VOILE.toFloat()),
        blue = pastel.blue * VOILE.toFloat() + fond.blue * (1 - VOILE.toFloat()),
    )

    @Test
    fun `le texte se lit sur la page nue, dans les quatre peaux`() {
        for (theme in ReadingTheme.entries) {
            val fond = ONTColors.background(theme)
            for ((nom, encre) in encres(theme)) {
                eprouver("$nom · $theme · page nue", rapport(encre, fond))
            }
        }
    }

    @Test
    fun `le texte se lit sur un verset surligne, dans les quatre peaux`() {
        // Vingt cas — quatre peaux fois cinq pastels — pour chaque marquage.
        for (theme in ReadingTheme.entries) {
            val fond = ONTColors.background(theme)
            for (pastel in HighlightColor.entries) {
                val sol = voile(ONTColors.highlight(pastel, theme), fond)
                for ((nom, encre) in encres(theme)) {
                    eprouver("$nom · $theme · ${pastel.cle}", rapport(encre, sol))
                }
            }
        }
    }

    /**
     * Les trois marquages du corps, dans la peau donnée.
     *
     * L'accentuation n'y figure pas : elle porte **aussi** une graisse, donc son
     * relevé seul dirait moins que ce que l'œil reçoit. La mesurer comme les
     * autres reviendrait à lui appliquer un critère qui n'est pas le sien.
     */
    private fun encres(theme: ReadingTheme): kotlin.collections.List<Pair<String, Color>> =
        listOf(
            "l'encre" to ONTColors.ink(theme),
            "l'or d'un intraduisible" to ONTColors.accent(theme),
            "la terre brûlée d'un Shem" to ONTColors.shem(theme),
        )
}
