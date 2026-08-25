package com.labibleont.ont.kit

import com.labibleont.ont.kit.corpus.Block
import com.labibleont.ont.kit.corpus.Inline
import com.labibleont.ont.kit.corpus.Verse
import com.labibleont.ont.kit.corpus.fusingConsecutiveVerses
import com.labibleont.ont.kit.corpus.lemmas
import com.labibleont.ont.kit.corpus.plainText
import org.junit.Assert.assertEquals
import org.junit.Test

class CorpusTest {

    private fun verset(n: Int, texte: String) =
        Block.Verses(listOf(Verse(n, listOf(Inline.Text(texte)))))

    @Test
    fun `les versets consecutifs se reunissent en un bloc`() {
        val fondus = listOf(verset(1, "a"), verset(2, "b"), verset(3, "c"))
            .fusingConsecutiveVerses()
        assertEquals(1, fondus.size)
        assertEquals(3, (fondus.first() as Block.Verses).verses.size)
    }

    @Test
    fun `un titre coupe la prose`() {
        // « Les toledot de Shem » ouvre une section : la prose ne doit pas
        // l'enjamber.
        val titre = Block.Heading(2, listOf(Inline.Text("Les toledot")))
        val fondus = listOf(verset(1, "a"), titre, verset(2, "b")).fusingConsecutiveVerses()
        assertEquals(3, fondus.size)
        assertEquals(titre, fondus[1])
    }

    @Test
    fun `le texte nu ne rend que le corps par defaut`() {
        // C'est la voix du texte, sans l'appareil : les gloses de l'ONT font
        // parfois quarante mots et noieraient un titre ou un extrait.
        val nodes = listOf(
            Inline.Text("Au commencement "),
            Inline.Term("Elohim", "elohim"),
            Inline.Gloss(listOf(Inline.Text(" — les puissances"))),
            Inline.Translit("bereshit", "בְּרֵאשִׁית"),
        )
        assertEquals("Au commencement Elohim", nodes.plainText())
    }

    @Test
    fun `les niveaux deux et trois s'allument a la demande`() {
        val nodes = listOf(
            Inline.Term("Elohim", "elohim"),
            Inline.Gloss(listOf(Inline.Text(" — les puissances"))),
            Inline.Translit("bereshit", "בְּרֵאשִׁית"),
        )
        assertEquals("Elohim — les puissances", nodes.plainText(gloss = true))
        assertEquals("Elohim(bereshit / בְּרֵאשִׁית)", nodes.plainText(level3 = true))
    }

    @Test
    fun `les lemmes se recoltent jusque dans une glose`() {
        // Un nom propre balisé à l'intérieur d'une glose reste un intraduisible :
        // il doit ouvrir sa fiche comme ailleurs.
        val nodes = listOf(
            Inline.Term("YHWH", "yhwh"),
            Inline.Gloss(listOf(Inline.Term("Elohim", "elohim"))),
        )
        assertEquals(listOf("yhwh", "elohim"), nodes.lemmas)
    }
}
