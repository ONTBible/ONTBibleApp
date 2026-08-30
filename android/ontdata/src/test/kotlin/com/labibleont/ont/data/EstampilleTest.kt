package com.labibleont.ont.data

import com.labibleont.ont.data.remote.CorpusUpdater
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
}
