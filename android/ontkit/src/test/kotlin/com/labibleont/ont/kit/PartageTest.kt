package com.labibleont.ont.kit

import com.labibleont.ont.kit.reader.Partage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * La forme d'un partage, mesurée à un seul endroit.
 *
 * Elle était écrite dans deux vues, et elle avait divergé : le verset du jour
 * partait sans le lien que la lecture y mettait. Aucun test ne pouvait
 * l'attraper — on ne compare pas deux chaînes construites à deux endroits.
 */
class PartageTest {

    @Test
    fun `la forme complete, lien compris`() {
        assertEquals(
            "Au commencement.\n\n— Bereshit 1:1, La Bible ONT\n" +
                "https://ontbible.com/fr/lire/bereshit/bereshit-1?v=1",
            Partage.texte(
                "Au commencement.",
                "Bereshit 1:1",
                "https://ontbible.com/fr/lire/bereshit/bereshit-1?v=1",
            ),
        )
    }

    @Test
    fun `sans lien, aucune ligne vide ne traine`() {
        val t = Partage.texte("Au commencement.", "Bereshit 1:1")
        assertEquals("Au commencement.\n\n— Bereshit 1:1, La Bible ONT", t)
        assertFalse("le message ne doit pas finir par un blanc", t.endsWith("\n"))
    }

    /**
     * Un lien vide n'est pas un lien. Le distinguer de `null` obligerait chaque
     * point d'appel à faire le tri, et l'un d'eux l'oublierait.
     */
    @Test
    fun `un lien vide vaut pas de lien`() {
        assertEquals(
            Partage.texte("Au commencement.", "Bereshit 1:1"),
            Partage.texte("Au commencement.", "Bereshit 1:1", "   "),
        )
    }

    /**
     * **Le retour à la ligne appartient au traducteur.**
     *
     * `replier`, dans `Inline.kt`, le préserve délibérément — « la seconde ligne
     * d'un parallélisme, l'ouverture d'un discours ». Une première version de
     * `Partage` les fondait en espaces au nom d'une normalisation, et effaçait
     * donc ce que le texte dit de sa propre forme.
     *
     * Ce test est là pour que la normalisation ne revienne pas par la fenêtre.
     */
    @Test
    fun `les retours a la ligne du traducteur sont gardes`() {
        assertEquals(
            "Que la lumière soit\net la lumière fut.\n\n— Bereshit 1:3, La Bible ONT",
            Partage.texte("Que la lumière soit\net la lumière fut.", "Bereshit 1:3"),
        )
    }

    @Test
    fun `les bords sont rognes`() {
        assertTrue(
            Partage.texte("  Au commencement.\n ", "Bereshit 1:1")
                .startsWith("Au commencement.\n\n—"),
        )
    }

    /**
     * **Le défaut que la capture a montré et qu'aucune lecture du code n'aurait
     * trouvé.**
     *
     * Le corpus **ouvre des citations que le verset ne ferme pas** : Bereshit
     * 6:13 porte un chevron ouvrant et aucun fermant, parce que le discours
     * d'Elohim continue au verset suivant. L'enveloppe de chevrons qu'Android
     * ajoutait rendait donc deux ouvertures pour une fermeture — et son chevron
     * final fermait un propos que le traducteur avait laissé courir.
     *
     * Il fallait un verset qui cite quelqu'un, et il fallait regarder la feuille
     * de partage sur l'appareil.
     */
    @Test
    fun `le partage ne ferme pas une citation que le verset laisse ouverte`() {
        val ouvert = "Elohim dit à Noach : « La fin de toute chair est venue."
        val t = Partage.texte(ouvert, "Bereshit 6:13")
        assertEquals(
            "l'enveloppe n'ajoute aucun chevron",
            ouvert.count { it == '»' },
            t.count { it == '»' },
        )
        assertEquals(
            ouvert.count { it == '«' },
            t.count { it == '«' },
        )
    }
}
