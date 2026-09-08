package com.labibleont.ont.data

import com.labibleont.ont.data.account.Envoi
import com.labibleont.ont.data.account.MarqueDto
import com.labibleont.ont.data.account.Reception
import com.labibleont.ont.data.account.versDomaine
import com.labibleont.ont.data.account.versDto
import com.labibleont.ont.kit.reader.HighlightColor
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Le contrat de `/sync`, constaté sur les formes réelles du backend.
 *
 * Les charges sont copiées de `domain/sync.rs` — `Highlight`, `Position`,
 * `PullResponse` — et non de ce que notre Kotlin produit. Un test qui relirait
 * notre propre écriture mesurerait la cohérence, jamais la justesse.
 */
class ContratDeSynchronisationTest {

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    @Test
    fun `la reponse de pull se lit telle que le backend l'ecrit`() {
        val duBackend = """
            {"highlights":[{"id":"h1","book_id":"bereshit","chapter_id":"bereshit-1",
            "verse":3,"color":"sky","note":"une note","updated_at":1700000000000,
            "deleted":false}],
            "position":{"book_id":"bereshit","chapter_id":"bereshit-1",
            "chapter_title":"Bereshit 1","verse":3,"updated_at":1700000000000},
            "server_time":1700000000001}
        """.trimIndent().replace("\n", "")

        val recu = json.decodeFromString<Reception>(duBackend)

        assertEquals(1, recu.highlights.size)
        assertEquals("bereshit-1", recu.highlights.first().chapterId)
        assertEquals("une note", recu.highlights.first().note)
        assertEquals("Bereshit 1", recu.position?.chapterTitle)
        assertEquals(1_700_000_000_001L, recu.serverTime)
    }

    /**
     * Une réponse vide est le cas d'un compte neuf. Sans valeurs par défaut,
     * elle lèverait — et la première synchronisation d'un lecteur échouerait
     * précisément parce qu'il n'a rien.
     */
    @Test
    fun `une reponse vide se lit sans lever`() {
        val recu = json.decodeFromString<Reception>("""{"server_time":1}""")
        assertTrue(recu.highlights.isEmpty())
        assertEquals(null, recu.position)
    }

    @Test
    fun `l'envoi part dans les noms que le backend attend`() {
        val ecrit = json.encodeToString(
            Envoi(listOf(MarqueDto("h", "b", "c", 1, "gold", null, 42, false))),
        )
        for (attendu in listOf("book_id", "chapter_id", "updated_at")) {
            assertTrue("« $attendu » absent : $ecrit", ecrit.contains("\"$attendu\""))
        }
        for (interdit in listOf("bookId", "chapterId", "updatedAt")) {
            assertFalse("un nom Kotlin a fui : $ecrit", ecrit.contains(interdit))
        }
    }

    /**
     * L'aller-retour ne doit rien perdre. La couleur passe par son nom, la date
     * par des millisecondes, et la pierre tombale par son drapeau.
     */
    @Test
    fun `un aller-retour conserve la marque`() {
        val depart = MarqueDto("h1", "bereshit", "bereshit-1", 3, "violet", "n", 1_700_000L, true)
        val revenu = depart.versDomaine().versDto()
        assertEquals(depart, revenu)
    }

    /**
     * **Ce que la synchronisation fait d'une couleur qu'elle ne connaît pas.**
     *
     * Elle la garde. C'est l'arbitrage rendu par iOS le 8 septembre 2026 —
     * *préserver, comme le site* — et il remplace le comportement que ce
     * fichier décrivait la veille : ramener à l'or **et réécrire**.
     *
     * La version précédente de ce test disait ce que le code faisait alors, en
     * annonçant qu'elle échouerait le jour de la décision. Elle a rougi à cet
     * instant précis, ce qui était tout son objet : une décision différée doit
     * rester visible, et sa mise en œuvre faire du bruit plutôt que passer.
     *
     * L'or demeure pour l'affichage. Ce qui a changé, c'est que la lecture ne
     * réécrit plus ce qu'elle n'a pas compris.
     */
    @Test
    fun `une couleur inconnue s'affiche en or et repart intacte`() {
        val inconnue = MarqueDto("h", "b", "c", 1, "turquoise", null, 1, false)
        val domaine = inconnue.versDomaine()

        assertEquals("l'affichage retombe sur l'or", HighlightColor.GOLD, domaine.color)
        assertEquals("la clé reçue est gardée", "turquoise", domaine.cleDOrigine)
        assertEquals(
            "et c'est elle qui repart vers le serveur, jamais « gold »",
            "turquoise",
            domaine.versDto().color,
        )
    }

    /** Une teinte connue ne laisse aucune trace redondante derrière elle. */
    @Test
    fun `une couleur connue repart telle quelle, sans cle d'origine`() {
        val connue = MarqueDto("h", "b", "c", 1, "violet", null, 1, false)
        val domaine = connue.versDomaine()
        assertEquals(HighlightColor.VIOLET, domaine.color)
        assertEquals(null, domaine.cleDOrigine)
        assertEquals("violet", domaine.versDto().color)
    }
}
