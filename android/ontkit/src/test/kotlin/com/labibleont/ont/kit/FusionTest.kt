package com.labibleont.ont.kit

import com.labibleont.ont.kit.account.Fusion
import com.labibleont.ont.kit.reader.Highlight
import com.labibleont.ont.kit.reader.HighlightColor
import com.labibleont.ont.kit.reader.ReadingPosition
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * L'arbitrage entre deux appareils, éprouvé sur les cas qui coûtent.
 *
 * Chacun de ces tests décrit une perte possible pour le lecteur : une marque
 * qui ressuscite, une suppression qui ne prend pas, une reprise effacée par un
 * appareil neuf.
 */
class FusionTest {

    private fun marque(
        id: String,
        seconde: Long,
        couleur: HighlightColor = HighlightColor.GOLD,
        supprimee: Boolean = false,
    ) = Highlight(
        id = id,
        bookId = "bereshit",
        chapterId = "bereshit-1",
        verse = 1,
        color = couleur,
        updatedAt = Instant.ofEpochSecond(seconde),
        deleted = supprimee,
    )

    @Test
    fun `le plus recent gagne`() {
        val fusion = Fusion.marques(
            locales = listOf(marque("a", 100, HighlightColor.GOLD)),
            distantes = listOf(marque("a", 200, HighlightColor.SKY)),
        )
        assertEquals(1, fusion.size)
        assertEquals(HighlightColor.SKY, fusion.first().color)
    }

    @Test
    fun `l'ancien distant ne remplace pas le recent local`() {
        val fusion = Fusion.marques(
            locales = listOf(marque("a", 200, HighlightColor.GOLD)),
            distantes = listOf(marque("a", 100, HighlightColor.SKY)),
        )
        assertEquals(HighlightColor.GOLD, fusion.first().color)
    }

    /**
     * **Le défaut que la pierre tombale existe pour fermer.** Sans elle, la
     * suppression faite ici ne serait qu'une absence là-bas, et l'autre
     * appareil renverrait la marque au prochain échange.
     */
    @Test
    fun `une suppression recente efface une marque ancienne`() {
        val fusion = Fusion.marques(
            locales = listOf(marque("a", 100)),
            distantes = listOf(marque("a", 200, supprimee = true)),
        )
        assertTrue(fusion.first().deleted)
    }

    /**
     * L'inverse est vrai aussi, et c'est correct : le lecteur a reposé la
     * marque après l'avoir effacée.
     */
    @Test
    fun `une marque reposee apres coup ressuscite`() {
        val fusion = Fusion.marques(
            locales = listOf(marque("a", 300)),
            distantes = listOf(marque("a", 200, supprimee = true)),
        )
        assertTrue(!fusion.first().deleted)
    }

    /**
     * **L'égalité va au distant, et c'est ce qui fait converger.** Si chacun
     * gardait la sienne, deux appareils à la même milliseconde resteraient
     * différents pour toujours, chacun se croyant à jour.
     */
    @Test
    fun `a date egale, le distant l'emporte`() {
        val fusion = Fusion.marques(
            locales = listOf(marque("a", 100, HighlightColor.GOLD)),
            distantes = listOf(marque("a", 100, HighlightColor.ROSE)),
        )
        assertEquals(HighlightColor.ROSE, fusion.first().color)
    }

    @Test
    fun `ce que l'un a et l'autre pas se garde des deux cotes`() {
        val fusion = Fusion.marques(
            locales = listOf(marque("a", 100)),
            distantes = listOf(marque("b", 100)),
        )
        assertEquals(listOf("a", "b"), fusion.map { it.id })
    }

    /** Deux appels sur les mêmes données rendent la même liste. */
    @Test
    fun `l'ordre de sortie est stable`() {
        val locales = listOf(marque("c", 1), marque("a", 1))
        val distantes = listOf(marque("b", 1))
        assertEquals(
            Fusion.marques(locales, distantes).map { it.id },
            Fusion.marques(locales, distantes).map { it.id },
        )
        assertEquals(listOf("a", "b", "c"), Fusion.marques(locales, distantes).map { it.id })
    }

    private fun position(seconde: Long, unite: String) = ReadingPosition(
        bookId = "bereshit",
        chapterId = unite,
        chapterTitle = unite,
        verse = 1,
        date = Instant.ofEpochSecond(seconde),
    )

    /**
     * **`null` veut dire « je n'en ai pas », jamais « efface ».** Un appareil
     * qu'on vient d'installer n'a aucune position ; laisser son absence
     * l'emporter effacerait la reprise de l'autre.
     */
    @Test
    fun `une absence n'efface pas la position de l'autre`() {
        assertEquals(position(100, "x"), Fusion.position(null, position(100, "x")))
        assertEquals(position(100, "x"), Fusion.position(position(100, "x"), null))
        assertNull(Fusion.position(null, null))
    }

    @Test
    fun `la position la plus recente gagne`() {
        val fusionnee = Fusion.position(position(100, "vieux"), position(200, "neuf"))
        assertEquals("neuf", fusionnee?.chapterId)
    }
}
