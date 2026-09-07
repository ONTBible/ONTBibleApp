package com.labibleont.ont

import com.labibleont.ont.observabilite.Observabilite.expurger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Ce qui ne doit jamais quitter l'appareil, et ce qui doit rester lisible.
 *
 * Les deux moitiés comptent autant. Une expurgation trop large rend des
 * messages qui ne diagnostiquent plus rien — iOS l'a payé : « ressource
 * introuvable : data/corpus.json » devenait « … : <chemin> », et le seul
 * renseignement utile disparaissait avec le risque.
 */
class ExpurgationTest {

    @Test
    fun `un chemin absolu disparait`() {
        val sortie = expurger("échec sur /data/user/0/com.labibleont.ont/files/corpus/x.json")
        assertTrue(sortie.contains("<chemin>"))
        assertFalse(sortie.contains("com.labibleont.ont/files"))
    }

    /**
     * **La nuance qu'iOS a payée.** Un chemin relatif nomme une ressource de
     * notre propre paquet : il ne révèle rien du lecteur, et c'est souvent la
     * seule information utile du message.
     */
    @Test
    fun `un chemin relatif reste, parce qu'il est le diagnostic`() {
        assertEquals(
            "ressource introuvable : data/corpus.json",
            expurger("ressource introuvable : data/corpus.json"),
        )
    }

    @Test
    fun `un identifiant de conteneur disparait`() {
        val sortie = expurger("dossier 3b687dd2-d5be-7e30-a257-74cdb38a39b6 illisible")
        assertTrue(sortie.contains("<chemin>"))
        assertFalse(sortie.contains("3b687dd2"))
    }

    /**
     * Le cœur du refus : une note de lecteur révèle des convictions
     * religieuses, catégorie particulière au sens de l'article 9.
     */
    @Test
    fun `une note citee disparait`() {
        val sortie = expurger("échec en écrivant « ce passage m'a bouleversé hier soir »")
        assertTrue(sortie.contains("<texte>"))
        assertFalse(sortie.contains("bouleversé"))
    }

    /**
     * Le critère est la **prose**, pas la longueur : douze signes et une
     * espace. Un lemme cité n'en est pas.
     */
    @Test
    fun `un lemme cite reste`() {
        assertEquals("lemme « chesed » inconnu", expurger("lemme « chesed » inconnu"))
    }

    @Test
    fun `une cle citee sans espace reste, meme longue`() {
        val message = "clé « bereshit-1-verset-30 » absente"
        assertEquals(message, expurger(message))
    }

    @Test
    fun `un message ordinaire traverse intact`() {
        val message = "manifeste refusé : schéma 3 au lieu de 2"
        assertEquals(message, expurger(message))
    }
}
