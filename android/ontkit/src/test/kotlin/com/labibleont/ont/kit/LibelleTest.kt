package com.labibleont.ont.kit

import com.labibleont.ont.kit.corpus.ChapterStub
import com.labibleont.ont.kit.corpus.Status
import org.junit.Assert.assertEquals
import com.labibleont.ont.kit.reader.versetDans
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

/**
 * Le verset à marquer dans une unité — et surtout, quand ne pas le marquer.
 *
 * La position mémorisée est celle du **lecteur**, pas celle de l'écran ouvert.
 * Un repère faux est pire qu'aucun repère, parce qu'on s'y fie.
 */
class VersetDansTest {

    private val ou = com.labibleont.ont.kit.reader.ReadingPosition(
        bookId = "bereshit",
        chapterId = "bereshit-18",
        chapterTitle = "Parashah 18",
        verse = 12,
    )

    @Test
    fun `l'unité qu'on lit porte son verset`() {
        assertEquals(12, ou.versetDans("bereshit-18"))
    }

    /** Le cas qui compte : ouvrir Bereshit 2 pendant qu'on lit Bereshit 18. */
    @Test
    fun `une autre unité n'en porte aucun`() {
        assertEquals(null, ou.versetDans("bereshit-2"))
    }

    @Test
    fun `sans position, rien à marquer`() {
        val aucune: com.labibleont.ont.kit.reader.ReadingPosition? = null
        assertEquals(null, aucune.versetDans("bereshit-18"))
    }
}
