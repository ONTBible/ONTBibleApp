package com.labibleont.ont.kit

import com.labibleont.ont.kit.reader.Highlight
import com.labibleont.ont.kit.reader.HighlightColor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Une couleur qu'on ne connaît pas se garde, elle ne se remplace pas.
 *
 * ## L'arbitrage, et ce qu'il écarte
 *
 * `color` est une chaîne libre côté backend : aucune liste n'est validée, et
 * chaque client tient la sienne. Une clé inconnue vient donc d'une version plus
 * récente d'une autre plateforme — **pas d'une donnée corrompue**.
 *
 * Les trois clients faisaient trois choses :
 *
 *     iOS       ignore la ligne
 *     le site   la passe telle quelle
 *     Android   la ramenait à l'or, PUIS LA RÉÉCRIVAIT
 *
 * Android était le seul à détruire, et il synchronise depuis le 3 septembre :
 * chaque passage écrasait un peu plus, pour tous les appareils et toutes les
 * plateformes.
 *
 * iOS a tranché le 8 septembre : **préserver, comme le site**. Une substitution
 * silencieuse est le pire des trois comportements — ni rejet visible, ni
 * abstention, mais une valeur plausible qui a remplacé la vraie.
 *
 * L'or reste pour **afficher** : perdre la marque du lecteur serait pire que la
 * montrer d'une autre teinte. Ce qui change, c'est que la lecture ne réécrit
 * plus ce qu'elle n'a pas compris.
 */
class CouleurPreserveeTest {

    private fun marque(cle: String) = Highlight(
        id = "h",
        bookId = "bereshit",
        chapterId = "bereshit-1",
        verse = 1,
        color = HighlightColor.depuis(cle),
        cleDOrigine = cle.takeIf { c -> HighlightColor.entries.none { it.cle == c } },
    )

    @Test
    fun `une teinte connue ne garde aucune cle d'origine`() {
        val m = marque("violet")
        assertEquals(HighlightColor.VIOLET, m.color)
        assertNull("rien de redondant ne se garde", m.cleDOrigine)
    }

    /**
     * **Le cas du client plus récent.** La marque reste visible en or, et la
     * clé qu'on n'a pas comprise voyage intacte.
     */
    @Test
    fun `une teinte inconnue s'affiche en or et garde sa cle`() {
        val m = marque("turquoise")
        assertEquals("l'affichage retombe sur l'or", HighlightColor.GOLD, m.color)
        assertEquals("la clé reçue est gardée", "turquoise", m.cleDOrigine)
    }

    /**
     * Ce qui repart doit être ce qui est arrivé. C'est la ligne qui empêchait
     * Android d'écraser pour tous ce que le site préserve.
     */
    @Test
    fun `ce qui repart est ce qui est arrive`() {
        assertEquals("turquoise", marque("turquoise").let { it.cleDOrigine ?: it.color.cle })
        assertEquals("violet", marque("violet").let { it.cleDOrigine ?: it.color.cle })
    }

    /**
     * L'or reçu explicitement n'est pas une clé inconnue : il ne doit rien
     * laisser derrière lui, sinon chaque marque ordinaire porterait un champ
     * inutile et le champ cesserait de signaler quoi que ce soit.
     */
    @Test
    fun `l'or recu explicitement reste de l'or, sans trace`() {
        val m = marque("gold")
        assertEquals(HighlightColor.GOLD, m.color)
        assertNull(m.cleDOrigine)
    }
}
