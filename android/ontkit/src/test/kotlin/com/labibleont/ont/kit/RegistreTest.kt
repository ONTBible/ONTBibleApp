package com.labibleont.ont.kit

import com.labibleont.ont.kit.corpus.BookOutline
import com.labibleont.ont.kit.corpus.Registre
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Les quatre cas de la règle, et la recherche sur les deux registres. */
public class RegistreTest {

    @Test
    public fun `francais recu allume, on montre le francais`() {
        assertEquals(
            "Actes des Apôtres",
            Registre.second("Actes des Apôtres", "les gevurot de YHWH", francaisRecu = true),
        )
    }

    @Test
    public fun `francais recu eteint, on montre la glose`() {
        assertEquals(
            "les gevurot de YHWH",
            Registre.second("Actes des Apôtres", "les gevurot de YHWH", francaisRecu = false),
        )
    }

    @Test
    public fun `sans glose, le francais tient dans les deux registres`() {
        // Un livre sans glose n'a pas à disparaître parce qu'on a changé de
        // registre.
        assertEquals("Genèse", Registre.second("Genèse", null, francaisRecu = false))
        assertEquals("Genèse", Registre.second("Genèse", null, francaisRecu = true))
    }

    @Test
    public fun `une ligne vide ne s'affiche pas`() {
        assertNull(Registre.second("", null, francaisRecu = true))
        assertNull(Registre.second(null, null, francaisRecu = false))
    }

    @Test
    public fun `on cherche dans les deux registres a la fois`() {
        val livre = BookOutline(
            id = "gevurot",
            slot = 48,
            title = "Gevurot ha-Neviim",
            french = "Actes des Apôtres",
            glose = "les gevurot de YHWH par ses neviim",
            hebrew = null,
            groupId = null,
            empty = false,
            intro = null,
            chapters = emptyList(),
        )
        val cherchable = Registre.cherchable(livre)
        assertTrue("le nom ONT", cherchable.contains("Gevurot ha-Neviim"))
        assertTrue("le français reçu", cherchable.contains("Actes"))
        assertTrue("la glose", cherchable.contains("neviim"))
    }
}
