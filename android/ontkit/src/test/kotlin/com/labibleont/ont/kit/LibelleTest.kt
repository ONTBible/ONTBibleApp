package com.labibleont.ont.kit

import com.labibleont.ont.kit.corpus.ChapterStub
import com.labibleont.ont.kit.corpus.Status
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Le libellé d'une unité, dans les deux registres.
 *
 * Cette règle vit dans le **domaine** et non dans un écran parce que trois
 * endroits doivent dire le même mot : le sommaire, le sélecteur de renvoi et le
 * titre de lecture. iOS l'a gardée privée à une seule vue, et le sélecteur a
 * continué à dire « Bereshit 2 » pendant que le sommaire disait « Parashah 2 ».
 */
class LibelleTest {

    private fun unite(n: Int, titre: String = "Bereshit $n") = ChapterStub(
        id = "bereshit-$n",
        n = n,
        title = titre,
        status = Status.BROUILLON,
        verseCount = 31,
        reference = null,
    )

    @Test
    fun `le français reçu numérote des chapitres`() {
        assertEquals("Chapitre 2", unite(2).libelle(francaisRecu = true))
    }

    @Test
    fun `éteint, l'unité reprend le mot hébreu`() {
        assertEquals("Parashah 2", unite(2).libelle(francaisRecu = false))
    }

    /**
     * Une introduction n'a pas de rang, donc pas de numéro à traduire — elle
     * garde son titre dans les deux registres.
     */
    @Test
    fun `une introduction garde son titre dans les deux registres`() {
        val intro = unite(0, titre = "Ouverture")
        assertEquals("Ouverture", intro.libelle(francaisRecu = true))
        assertEquals("Ouverture", intro.libelle(francaisRecu = false))
    }
}
