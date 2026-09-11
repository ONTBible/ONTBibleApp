package com.labibleont.ont.data

import com.labibleont.ont.data.remote.CorpusUpdater
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Ce que le manifeste désigne, et qu'Android descend réellement.
 *
 * ## Pourquoi cette épreuve existe
 *
 * `Manifeste.tout` traduit les noms du manifeste en noms locaux, et **ignore en
 * silence** ce qu'il ne connaît pas. Le silence est voulu : une version future
 * publiera des fichiers que celle-ci ne saurait pas lire, et les écrire sans les
 * comprendre ne ferait qu'occuper le disque.
 *
 * Mais il ne distingue pas « pas encore connu » de « oublié ». `recherche`
 * manquait à la table depuis le portage, donc `search.json` n'était **jamais**
 * téléchargé — sans une ligne de journal, sans un test qui rougisse. Après une
 * mise à jour du corpus, la recherche répondait sur l'index embarqué à la
 * compilation pendant que les livres et le lexique étaient neufs.
 *
 * iOS le descend depuis toujours — `CorpusUpdater.swift`, entrée
 * `"recherche": "search.json"`. L'écart ne se voyait d'aucun des deux côtés :
 * chaque plateforme était cohérente avec elle-même.
 *
 * ## Ce que l'épreuve garde, et ce qu'elle ne garde pas
 *
 * Elle garde la **table des noms**, qui est du Kotlin pur. Elle ne garde pas le
 * lecteur de disque — `DiskSearchIndex` exige un `Context`, et ce module n'a ni
 * Robolectric ni instrumentation. C'est la moitié testable de deux moitiés qui
 * se protégeaient l'une l'autre : sans téléchargement, un lecteur ne voit rien ;
 * sans lecteur, un téléchargement ne sert à rien. Aucune des deux ne se
 * remarquait seule.
 */
class CorpusActifTest {

    private fun entree(chemin: String) =
        CorpusUpdater.Manifeste.Entree(chemin = chemin, empreinte = "0".repeat(12), octets = 1)

    /** Le manifeste tel que le pipeline l'écrit, réduit à ses noms. */
    private val manifesteDuPipeline = CorpusUpdater.Manifeste(
        schema = CorpusUpdater.SCHEMA,
        genere = "2026-09-11T08:00:00Z",
        fichiers = mapOf(
            "plan" to entree("c.aaaaaaaaaaaa.json"),
            "quotidien" to entree("q.bbbbbbbbbbbb.json"),
            "glossaire" to entree("g.cccccccccccc.json"),
            "occurrences" to entree("o.dddddddddddd.json"),
            "recherche" to entree("s.eeeeeeeeeeee.json"),
            "shemot" to entree("h.ffffffffffff.json"),
        ),
    )

    private val locaux get() = manifesteDuPipeline.tout.map { it.first }.toSet()

    /**
     * Le cas du défaut. Rougit contre la table d'avant, où `recherche`
     * n'existait pas : `mapNotNull` le laissait tomber sans rien dire.
     */
    @Test
    fun `l'index de recherche est descendu comme le reste du corpus`() {
        assertTrue(
            "le manifeste désigne `recherche`, et Android ne le descendait pas — " +
                "la recherche restait sur l'index du bundle après chaque mise à jour",
            "search.json" in locaux,
        )
    }

    /**
     * Le compte plutôt que la présence, parce qu'une table se vide aussi bien
     * qu'elle s'oublie. Six noms au manifeste, six fichiers descendus.
     */
    @Test
    fun `chaque nom connu du manifeste donne exactement un fichier local`() {
        assertEquals(
            "un nom du manifeste s'est perdu en chemin",
            manifesteDuPipeline.fichiers.size,
            manifesteDuPipeline.tout.size,
        )
        assertEquals(
            setOf(
                "corpus.json", "daily.json", "glossary.json",
                "occurrences.json", "search.json", "shemot.json",
            ),
            locaux,
        )
    }

    /**
     * Le silence reste voulu, et il doit le rester : c'est ce qui permettra à
     * une version future de publier sans casser celle-ci. On éprouve donc que le
     * mécanisme d'oubli fonctionne encore — sinon le correctif ci-dessus aurait
     * pu le supprimer sans qu'on le voie.
     */
    @Test
    fun `un nom que cette version ne connait pas est ignore, pas ecrit`() {
        val futur = manifesteDuPipeline.copy(
            fichiers = manifesteDuPipeline.fichiers + ("chuqqot" to entree("k.111111111111.json")),
        )
        assertEquals(
            "un nom inconnu a été descendu — il occuperait le disque sans lecteur",
            manifesteDuPipeline.tout.size,
            futur.tout.size,
        )
    }
}
