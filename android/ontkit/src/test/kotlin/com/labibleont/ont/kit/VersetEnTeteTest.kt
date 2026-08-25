package com.labibleont.ont.kit

import com.labibleont.ont.kit.corpus.Block
import com.labibleont.ont.kit.corpus.Inline
import com.labibleont.ont.kit.corpus.Verse
import com.labibleont.ont.kit.corpus.versetAuProrata
import com.labibleont.ont.kit.corpus.versetEnTete
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Retenir où l'on en est **en lisant**, pas seulement en tapant un verset.
 *
 * Android n'enregistrait la position qu'au tap. Lire un chapitre d'un bout à
 * l'autre sans rien toucher ne retenait rien, et la carte « Reprendre » ne
 * pouvait quasiment jamais paraître.
 */
class VersetEnTeteTest {

    private fun v(n: Int) = Verse(n = n, nodes = listOf(Inline.Text("…")))
    private fun versets(vararg n: Int) = Block.Verses(n.map { v(it) })
    private val titre = Block.Heading(level = 2, nodes = listOf(Inline.Text("Un intertitre")))

    @Test
    fun `le premier bloc visible donne son premier verset`() {
        val blocs = listOf(versets(1, 2), versets(3, 4), versets(5))
        assertEquals(3, blocs.versetEnTete(premierBlocVisible = 1))
    }

    /**
     * Le cas qui compte : un intertitre en haut de l'écran ne doit pas effacer
     * la position — il doit laisser parler ce qui suit.
     */
    @Test
    fun `un intertitre en tête laisse parler le bloc suivant`() {
        val blocs = listOf(versets(1), titre, versets(2, 3))
        assertEquals(2, blocs.versetEnTete(premierBlocVisible = 1))
    }

    @Test
    fun `la fin d'un chapitre sans verset ne rend rien`() {
        val blocs = listOf(versets(1), titre)
        assertNull(blocs.versetEnTete(premierBlocVisible = 1))
    }

    /** Un index hors bornes ne doit pas lever — le défilement peut devancer. */
    @Test
    fun `un index aberrant ne lève pas`() {
        val blocs = listOf(versets(1))
        assertNull(blocs.versetEnTete(premierBlocVisible = 99))
        assertEquals(1, blocs.versetEnTete(premierBlocVisible = -3))
    }
}

/**
 * Le verset atteint dans un bloc fondu, au prorata des signes.
 *
 * En prose continue — le mode par défaut — tout un chapitre tient en un seul
 * bloc : le rang de l'item ne bouge jamais, et la position restait le premier
 * verset quel que soit l'endroit où l'on lisait.
 */
class VersetAuProrataTest {

    private fun long(n: Int, signes: Int) = com.labibleont.ont.kit.corpus.Verse(
        n = n,
        nodes = listOf(com.labibleont.ont.kit.corpus.Inline.Text("x".repeat(signes))),
    )

    /** Trois versets de même poids : chaque tiers en désigne un. */
    private val egaux = com.labibleont.ont.kit.corpus.Block.Verses(
        listOf(long(1, 100), long(2, 100), long(3, 100)),
    )

    @Test
    fun `le haut du bloc désigne le premier verset`() {
        assertEquals(1, egaux.versetAuProrata(0f))
    }

    @Test
    fun `le milieu désigne celui du milieu`() {
        assertEquals(2, egaux.versetAuProrata(0.5f))
    }

    @Test
    fun `le bas désigne le dernier`() {
        assertEquals(3, egaux.versetAuProrata(1f))
    }

    /**
     * Le poids compte, pas le rang : un verset qui occupe la moitié du bloc
     * occupe la moitié du parcours.
     */
    @Test
    fun `un verset long tient plus de place qu'un court`() {
        val inegaux = com.labibleont.ont.kit.corpus.Block.Verses(
            listOf(long(1, 900), long(2, 50), long(3, 50)),
        )
        assertEquals("aux neuf dixièmes on est encore dans le premier", 1, inegaux.versetAuProrata(0.85f))
        assertEquals(2, inegaux.versetAuProrata(0.93f))
    }

    /** Le défilement élastique peut déborder — ça ne doit pas lever. */
    @Test
    fun `une fraction hors bornes ne lève pas`() {
        assertEquals(1, egaux.versetAuProrata(-0.4f))
        assertEquals(3, egaux.versetAuProrata(1.7f))
    }

    @Test
    fun `un bloc vide ne rend rien`() {
        assertNull(com.labibleont.ont.kit.corpus.Block.Verses(emptyList()).versetAuProrata(0.5f))
    }
}
