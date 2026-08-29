package com.labibleont.ont.kit

import com.labibleont.ont.kit.reader.LienProfond
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Ce qu'une adresse reçue doit ouvrir.
 *
 * Les cas tordus sont ici parce qu'ils arrivent : une messagerie encode les
 * virgules, quelqu'un retape un lien de travers, un partage ancien ne porte pas
 * le paramètre qui n'existait pas encore.
 */
public class LienProfondTest {

    @Test
    public fun `l'unite entiere, comme les liens d'avant`() {
        assertEquals(
            LienProfond.Unite("bereshit", "bereshit-1"),
            LienProfond.lire("ont://read/bereshit/bereshit-1"),
        )
    }

    @Test
    public fun `un verset seul`() {
        assertEquals(
            LienProfond.Unite("bereshit", "bereshit-1", setOf(7)),
            LienProfond.lire("ont://read/bereshit/bereshit-1?v=7"),
        )
    }

    @Test
    public fun `une plage`() {
        assertEquals(
            LienProfond.Unite("bereshit", "bereshit-1", setOf(7, 8, 9)),
            LienProfond.lire("ont://read/bereshit/bereshit-1?v=7-9"),
        )
    }

    @Test
    public fun `une selection disjointe, la grammaire du renvoi affiche`() {
        assertEquals(
            LienProfond.Unite("bereshit", "bereshit-1", setOf(1, 2, 3, 7)),
            LienProfond.lire("ont://read/bereshit/bereshit-1?v=1-3,7"),
        )
    }

    @Test
    public fun `une virgule encodee par une messagerie`() {
        assertEquals(
            setOf(1, 2, 3, 7),
            (LienProfond.lire("ont://read/bereshit/bereshit-1?v=1-3%2C7")
                as LienProfond.Unite).versets,
        )
    }

    @Test
    public fun `le livre seul, et la liseuse seule`() {
        assertEquals(LienProfond.Livre("bereshit"), LienProfond.lire("ont://read/bereshit"))
        assertEquals(LienProfond.Lecture, LienProfond.lire("ont://read"))
        assertEquals(LienProfond.Lecture, LienProfond.lire("ont://read/"))
    }

    @Test
    public fun `ce qui ne s'ouvre pas rend null, jamais une erreur`() {
        assertNull(LienProfond.lire("https://ontbible.com/bereshit"))
        assertNull(LienProfond.lire("ont://inconnu/x"))
        assertNull(LienProfond.lire(""))
        assertNull(LienProfond.lire("n'importe quoi"))
    }

    @Test
    public fun `un verset illisible n'emporte pas le lien`() {
        // Le passage s'ouvre quand même, à son début : un lien à moitié
        // compris vaut mieux qu'un lien mort.
        assertEquals(
            LienProfond.Unite("bereshit", "bereshit-1", emptySet()),
            LienProfond.lire("ont://read/bereshit/bereshit-1?v=abc"),
        )
    }

    @Test
    public fun `ecrire puis lire rend le meme passage`() {
        for (versets in listOf(emptySet(), setOf(7), setOf(7, 8, 9), setOf(1, 2, 3, 7))) {
            val adresse = LienProfond.ecrire("bereshit", "bereshit-1", versets)
            assertEquals(
                "aller-retour de $versets",
                LienProfond.Unite("bereshit", "bereshit-1", versets),
                LienProfond.lire(adresse),
            )
        }
    }

    @Test
    public fun `l'adresse ecrite ne porte pas d'espace`() {
        // « 1-3, 7 » s'affiche avec une espace ; l'adresse ne doit pas, sinon
        // elle s'encode en %20 et devient illisible dans une conversation.
        val adresse = LienProfond.ecrire("bereshit", "bereshit-1", setOf(1, 2, 3, 7))
        assertEquals("ont://read/bereshit/bereshit-1?v=1-3,7", adresse)
    }

    // ── Le lien public, celui qui circule vraiment ───────────────────────

    @Test
    public fun `le lien du site ouvre le meme passage`() {
        assertEquals(
            LienProfond.Unite("bereshit", "bereshit-1", setOf(1, 2, 3)),
            LienProfond.lire("https://ontbible.com/fr/lire/bereshit/bereshit-1?v=1-3"),
        )
    }

    @Test
    public fun `la langue du lien ne compte pas`() {
        // Le segment existe pour épargner une migration le jour d'une édition
        // anglaise. Un lien d'une autre langue doit ouvrir le passage plutôt
        // que de ne rien faire.
        val attendu = LienProfond.Unite("bereshit", "bereshit-1", setOf(7))
        assertEquals(attendu, LienProfond.lire("https://ontbible.com/fr/lire/bereshit/bereshit-1?v=7"))
        assertEquals(attendu, LienProfond.lire("https://ontbible.com/en/read/bereshit/bereshit-1?v=7"))
        assertEquals(attendu, LienProfond.lire("https://www.ontbible.com/fr/lire/bereshit/bereshit-1?v=7"))
    }

    @Test
    public fun `un autre site n'est pas le notre`() {
        assertNull(LienProfond.lire("https://exemple.com/fr/lire/bereshit/bereshit-1"))
        assertNull(LienProfond.lire("https://ontbible.com.attaquant.net/fr/lire/bereshit/bereshit-1"))
    }

    @Test
    public fun `une page du site qui n'est pas une lecture`() {
        assertNull(LienProfond.lire("https://ontbible.com/fr/le-pourquoi"))
    }

    // ── Le retour du partage ─────────────────────────────────────────────

    @Test
    public fun `share ouvre le passage et leve la feuille`() {
        val lien = LienProfond.lire("ont://share/bereshit/bereshit-1?v=7-9")
        assertEquals(
            LienProfond.Unite("bereshit", "bereshit-1", setOf(7, 8, 9), partager = true),
            lien,
        )
    }

    @Test
    public fun `read n'ouvre pas la feuille`() {
        val lien = LienProfond.lire("ont://read/bereshit/bereshit-1?v=7") as LienProfond.Unite
        assertEquals(false, lien.partager)
    }
}
