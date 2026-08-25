package com.labibleont.ont.kit

import com.labibleont.ont.kit.corpus.Block
import com.labibleont.ont.kit.corpus.Inline
import com.labibleont.ont.kit.corpus.Verse
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
