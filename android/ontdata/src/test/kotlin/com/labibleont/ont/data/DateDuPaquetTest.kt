package com.labibleont.ont.data

import com.labibleont.ont.data.remote.CorpusUpdater
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * La date du paquet, lue **du vrai fichier**.
 *
 * ## Pourquoi celui-ci et pas une chaîne injectée
 *
 * `EstampilleTest` éprouve l'arbitrage en lui donnant les deux dates. Il est
 * juste, il passe, et **il n'a rien vu** : le défaut était en amont de son point
 * d'entrée — dans la lecture du fichier, pas dans la comparaison.
 *
 * Le manifeste du paquet porte `generatedAt`, celui du site `genere`, et
 * `dateDuBundle` décodait le premier avec le type du second. Le champ absent
 * ayant une valeur par défaut, la lecture **réussissait** et rendait `""` — ce
 * que l'arbitrage traite, à raison, comme « le paquet ne peut rien opposer ».
 *
 * Deux décisions justes qui, ensemble, annulaient la garde.
 *
 * D'où ce test : il part du fichier que le pipeline produit réellement, celui-là
 * même que `copierLesDonnees` embarque. Si le pipeline renomme son champ, c'est
 * ici que ça rougit — et non le jour où un corpus plus ancien écrasera un plus
 * neuf chez un lecteur.
 */
class DateDuPaquetTest {

    /** Le fichier que la tâche Gradle recopie dans les assets. */
    private val manifeste = File("../../app/Resources/data/manifest.json")

    @Test
    fun `le manifeste du paquet porte une date, et on sait la lire`() {
        assertTrue("le manifeste du pipeline est introuvable", manifeste.exists())

        // **Par la fonction que la liseuse emploie**, et non par un décodage
        // refait ici. Un décodage refait dans l'épreuve mesurerait le type
        // qu'elle a choisi, pas celui que la liseuse emploie — c'est exactement
        // la confusion qui a produit le défaut : deux manifestes, deux clés, et
        // une lecture qui réussissait en rendant du vide.
        val lue = CorpusUpdater.dateDuManifesteEmbarque(manifeste.readText())

        assertFalse(
            "la date du paquet est vide — le champ a dû être renommé, et la " +
                "garde anti-rétrogradation ne garde plus rien",
            lue.isBlank(),
        )
        assertEquals("une date d'estampille fait vingt signes : $lue", 20, lue.length)
        assertTrue("elle doit finir par Z : $lue", lue.endsWith("Z"))
    }

    /**
     * **Le défaut, reproduit.**
     *
     * Avec la date du paquet vide, l'arbitrage accepte n'importe quelle date
     * publiée bien formée — y compris plus ancienne que le paquet. Ce test dit
     * ce que coûtait le champ mal nommé.
     */
    @Test
    fun `une date de paquet vide fait accepter un corpus plus ancien`() {
        val publieeAncienne = "2020-01-01T00:00:00Z"
        assertTrue(
            "sans date de paquet, l'arbitrage accepte tout",
            CorpusUpdater.plusRecent(publieeAncienne, ""),
        )
        assertFalse(
            "avec la vraie date, il refuse",
            CorpusUpdater.plusRecent(publieeAncienne, "2026-08-30T02:05:02Z"),
        )
    }
}
