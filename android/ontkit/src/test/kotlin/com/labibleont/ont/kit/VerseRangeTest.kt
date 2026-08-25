package com.labibleont.ont.kit

import com.labibleont.ont.kit.reader.VerseRange
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class VerseRangeTest {

    @Test
    fun `les versets consecutifs se replient`() {
        assertEquals("1-3, 7", VerseRange.label(setOf(1, 2, 3, 7)))
        assertEquals("1-3", VerseRange.label(setOf(3, 1, 2)))
        assertEquals("5", VerseRange.label(setOf(5)))
    }

    @Test
    fun `une selection vide rend une chaine vide`() {
        // Le cas qui a fermé l'app côté iOS : la barre d'actions sortante était
        // réévaluée avec une sélection déjà vide. Ici il s'éprouve en une ligne.
        assertEquals("", VerseRange.label(emptySet()))
    }

    @Test
    fun `le renvoi complet tombe sur le titre quand rien n'est choisi`() {
        assertEquals("Bereshit 1", VerseRange.reference(emptySet(), "Bereshit 1"))
        assertEquals("Bereshit 1:1-3", VerseRange.reference(setOf(1, 2, 3), "Bereshit 1"))
    }

    @Test
    fun `un aller-retour rend la meme selection`() {
        val depart = setOf(1, 2, 3, 7, 12, 13)
        assertEquals(depart, VerseRange.parse(VerseRange.label(depart)))
    }

    @Test
    fun `un intervalle a l'envers se lit a l'endroit`() {
        // Ça vient d'une URL, donc de l'extérieur : mieux vaut comprendre que
        // refuser.
        assertEquals(setOf(1, 2, 3), VerseRange.parse("3-1"))
    }

    @Test
    fun `un morceau illisible n'emporte pas tout le lien`() {
        assertEquals(setOf(1, 5), VerseRange.parse("1, bricolé, 5"))
    }

    @Test
    fun `un intervalle absurde est ecarte`() {
        // `?v=1-99999999` ne doit pas allouer des millions d'entiers parce que
        // quelqu'un a bricolé l'adresse.
        assertTrue(VerseRange.parse("1-99999999").isEmpty())
    }

    @Test
    fun `les versets nuls ou negatifs disparaissent`() {
        assertEquals(setOf(2), VerseRange.parse("0, 2"))
    }
}
