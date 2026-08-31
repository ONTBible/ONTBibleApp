package com.labibleont.ont.data

import com.labibleont.ont.data.remote.CorpusUpdater
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * La garde qui décide si le corpus publié remplace celui du bundle.
 *
 * ## Le défaut qu'elle ferme
 *
 * Le disque l'emportait **toujours**. Une build neuve, embarquant un corpus
 * neuf, se faisait donc écraser au premier lancement par le corpus publié — plus
 * ancien tant que le site n'avait pas republié.
 *
 * Mesuré sur iOS : une build portant 1 913 noms propres en affichait 217. La
 * fonctionnalité arrivait **invisible**, et aucun test ne pouvait l'attraper —
 * ils mesurent tous le corpus du bundle, que personne ne lit.
 *
 * ## Ce qu'on compare, et ce qu'on ne consulte jamais
 *
 * Deux valeurs de la même chaîne : la date publiée contre la date embarquée.
 * **Jamais l'horloge de l'appareil.** Un téléphone qui se croit en 2019 — et il
 * y en a, le lecteur règle sa date lui-même — refuserait tout corpus comme
 * « venant du futur », et le texte se figerait sans que personne comprenne
 * pourquoi. L'abstention vient d'iOS, qui a posé la même.
 */
class EstampilleTest {

    /**
     * Un manifeste réduit à ce que la garde regarde.
     *
     * `plusRecentQueLeBundle` ne lit que `genere` ; le reste du manifeste ne
     * l'intéresse pas. Le construire entier ferait croire que les fichiers
     * comptent.
     */
    private fun manifeste(genere: String) =
        CorpusUpdater.Manifeste(schema = CorpusUpdater.SCHEMA, genere = genere)

    // On n'instancie pas l'`updater` avec un vrai contexte : ces tests portent
    // sur l'arbitrage, pas sur le réseau ni sur les assets. La date du bundle
    // est donc injectée.
    private fun arbitre(publiee: String, embarquee: String): Boolean =
        CorpusUpdater.plusRecent(publiee = publiee, embarquee = embarquee)

    @Test
    fun `un corpus publie plus recent remplace le bundle`() {
        assertTrue(arbitre("2026-08-30T22:45:48Z", "2026-08-29T22:45:48Z"))
    }

    @Test
    fun `un corpus publie plus ancien ne remplace rien`() {
        // Le cas exact du défaut : une build neuve, un site pas encore republié.
        assertFalse(arbitre("2026-08-27T10:00:00Z", "2026-08-30T22:45:48Z"))
    }

    @Test
    fun `deux corpus du meme instant ne se remplacent pas`() {
        // Strictement plus récent, pas « au moins aussi récent » : réécrire un
        // corpus identique coûterait le téléchargement pour rien.
        val d = "2026-08-30T22:45:48Z"
        assertFalse(arbitre(d, d))
    }

    @Test
    fun `un manifeste sans date est refuse`() {
        // On ne peut pas prouver qu'il est plus récent, et se tromper dans ce
        // sens-là est exactement ce qui a produit le défaut. Un corpus figé se
        // voit et se répare ; un corpus silencieusement remplacé par du plus
        // ancien ne se voit pas.
        assertFalse(arbitre("", "2026-08-30T22:45:48Z"))
    }

    @Test
    fun `un bundle sans date ne peut rien opposer`() {
        // Une app plus ancienne que l'estampille elle-même. La refuser
        // priverait ses lecteurs de toute mise à jour, pour toujours.
        assertTrue(arbitre("2026-08-30T22:45:48Z", ""))
    }

    @Test
    fun `une date mal formee vaut une date absente`() {
        // Les huit formes que le pipeline refuse déjà. Elles ne devraient jamais
        // arriver ici — mais la garde d'amont vit dans un autre dépôt que celui
        // qui publie, et une chaîne se rompt là où on ne la surveille pas.
        for (cas in listOf(
            "2026-08-30T22:45:48+02:00",
            "2026-08-30T22:45:48.123Z",
            "2026-08-30T22:45Z",
            "2026-08-30 22:45:48Z",
            "2026-08-30T22:45:48",
            "26-08-30T22:45:48Z",
            "2026-08-30T22:45:48z",
        )) {
            assertFalse(
                "« $cas » aurait dû être traitée comme absente",
                arbitre(cas, "2020-01-01T00:00:00Z"),
            )
        }
    }

    @Test
    fun `l'offset ne peut pas gagner par comparaison de chaines`() {
        // Le piège que la forme stricte ferme. « 02:14:00+02:00 » et
        // « 00:14:00Z » sont le même instant, mais la première se classe après
        // la seconde : sans le refus des offsets, l'app garderait le plus ancien
        // en croyant garder le plus récent.
        assertFalse(arbitre("2026-08-30T02:14:00+02:00", "2026-08-30T00:14:00Z"))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // La purge — l'effet que la garde ci-dessus laissait derrière elle
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Refuser un corpus publié trop vieux empêche d'en **poser** un mauvais.
     * Ça ne fait rien à celui qui est **déjà là**, et le disque recouvre le
     * bundle sans condition.
     *
     * Android portait la garde de `synchroniser` sans celle-ci : il avait donc
     * hérité de la moitié du remède. Sur iOS, cette moitié manquante s'était vue
     * en vrai — la 1.0.5 embarquait les Shemot et n'affichait aucun nom, parce
     * que le disque de l'avant-veille répondait à sa place.
     */
    private fun purge(surDisque: String, embarquee: String) =
        CorpusUpdater.doitPurger(surDisque = surDisque, embarquee = embarquee)

    @Test
    fun `un disque plus vieux que le bundle est ecarte`() {
        assertTrue(purge("2026-08-28T10:00:00Z", "2026-08-30T10:00:00Z"))
    }

    @Test
    fun `un disque plus recent que le bundle reste`() {
        assertFalse(purge("2026-08-31T10:00:00Z", "2026-08-30T10:00:00Z"))
    }

    /**
     * **Le cas ordinaire**, et celui qui coûterait le plus cher à rater.
     *
     * À égalité, le disque porte exactement le corpus du bundle. Le purger
     * quand même retéléchargerait tout à chaque lancement pour reposer les mêmes
     * octets — vingt méga par ouverture d'app, sur le forfait du lecteur.
     *
     * C'est ce qu'un `!plusRecent(...)` aurait produit : cette fonction est
     * stricte, et l'égalité n'y est pas « plus récent ».
     */
    @Test
    fun `a date egale le disque est garde`() {
        assertFalse(purge("2026-08-30T10:00:00Z", "2026-08-30T10:00:00Z"))
    }

    /**
     * Le cas de **toutes les installations existantes** : un corpus sur le
     * disque et aucune estampille, puisque personne n'en écrivait avant cette
     * version.
     *
     * Les traiter comme périmées est exact — ce corpus date forcément d'avant —
     * et c'est ce qui rend la réparation automatique au premier lancement, sans
     * que le lecteur ait rien à faire.
     */
    @Test
    fun `un disque sans estampille est ecarte`() {
        assertTrue(purge("", "2026-08-30T10:00:00Z"))
    }

    /**
     * Une estampille de forme voisine ne s'ordonne pas contre la forme stricte.
     * La traiter comme absente est le même choix que pour le manifeste publié :
     * se tromper dans ce sens-là est ce qui a produit le défaut.
     */
    @Test
    fun `une estampille mal formee vaut une absence`() {
        assertTrue(purge("2026-08-30", "2026-08-30T10:00:00Z"))
        assertTrue(purge("2026-08-31T12:14:00+02:00", "2026-08-30T10:00:00Z"))
    }

    /**
     * **Un bundle indatable ne peut rien opposer.**
     *
     * Purger sur cette base jetterait un corpus peut-être bon — et le
     * retéléchargerait aussitôt, sans avoir rien prouvé. On ne touche à rien.
     */
    @Test
    fun `un bundle sans estampille ne purge rien`() {
        assertFalse(purge("2026-08-28T10:00:00Z", ""))
        assertFalse(purge("", ""))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Le décodage — là où la garde tombait sans que rien ne le dise
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * **Un vrai manifeste du pipeline**, avec ses clés à lui.
     *
     * `generatedAt`, `vault`, `stats` : ce n'est pas le manifeste publié, qui
     * porte `genere`, `fichiers` et `livres`. Les deux étaient décodés par la
     * même classe. Sur celui-ci, kotlinx cherchait `genere`, ne le trouvait pas,
     * et rendait la valeur par défaut — la chaîne vide.
     *
     * Rien ne le signalait. Ça compilait, et les épreuves ci-dessus restaient
     * vertes : elles nourrissaient la date *déjà décodée*, jamais le document.
     */
    private val manifesteDuPipeline = """
        {"schema":1,
         "generatedAt":"2026-08-30T17:59:01Z",
         "vault":"/quelque/part/ONTBibleTranslation",
         "stats":{"books":44,"verses":864}}
    """.trimIndent()

    @Test
    fun `la date du bundle se lit dans un manifeste du pipeline`() {
        assertEquals(
            "2026-08-30T17:59:01Z",
            CorpusUpdater.dateDuManifesteEmbarque(manifesteDuPipeline),
        )
    }

    /**
     * Et la conséquence, qui est **tout le sujet** : une date vide fait tomber
     * la garde entière.
     *
     * `plusRecent` traite un bundle indatable comme n'ayant rien à opposer — à
     * raison, sinon ses lecteurs n'auraient plus jamais de mise à jour. Mais
     * cela veut dire qu'un décodage muet ne dégrade pas la garde : **il
     * l'annule**. Elle accepte alors tout, exactement comme avant qu'elle
     * n'existe.
     */
    @Test
    fun `une date de bundle vide ferait tout accepter`() {
        assertTrue(arbitre("2026-08-28T10:00:00Z", ""))
        // Avec la vraie date lue du manifeste, le corpus plus vieux est refusé.
        assertFalse(
            arbitre(
                "2026-08-28T10:00:00Z",
                CorpusUpdater.dateDuManifesteEmbarque(manifesteDuPipeline),
            ),
        )
    }

    /** Un manifeste illisible ne date rien, et ne prétend pas le contraire. */
    @Test
    fun `un manifeste illisible ne date rien`() {
        assertEquals("", CorpusUpdater.dateDuManifesteEmbarque("pas du json"))
        assertEquals("", CorpusUpdater.dateDuManifesteEmbarque("{}"))
    }
}
