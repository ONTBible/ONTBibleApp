package com.labibleont.ont.data

import com.labibleont.ont.data.account.DemandeDeConnexion
import com.labibleont.ont.data.account.SessionDto
import com.labibleont.ont.data.account.versDomaine
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Le contrat avec le backend, écrit dans un test parce qu'aucun compilateur ne
 * le voit.
 *
 * ## Ce qu'il garde
 *
 * Le backend écrit en `snake_case` **littéral**, sans aucun `rename` : un
 * `@SerialName` oublié ne casse ni sa compilation ni ses tests, et rend au
 * client une réponse qu'il lit comme « pas de compte ». Le `CLAUDE.md` de la
 * racine le signale comme le piège du partage à trois clients.
 *
 * iOS s'en remet à `convertFromSnakeCase` sur son décodeur : le contrat n'y est
 * donc écrit dans aucun type. Ces épreuves-ci sont le seul endroit des deux
 * plateformes où il est constaté.
 *
 * Les charges sont copiées de la forme réelle du backend — `SessionDto` de
 * `application/mod.rs`, `SignInBody` de `interface/mod.rs` — et non de ce que
 * notre Kotlin produit. Un test qui relirait notre propre écriture mesurerait
 * la cohérence, jamais la justesse.
 */
class ContratDeCompteTest {

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    @Test
    fun `la reponse du backend se lit telle qu'il l'ecrit`() {
        val duBackend = """
            {"access_token":"a.b.c","refresh_token":"long","expires_in":3600,"created":true}
        """.trimIndent()

        val dto = json.decodeFromString<SessionDto>(duBackend)

        assertEquals("a.b.c", dto.accessToken)
        assertEquals("long", dto.refreshToken)
        assertEquals(3600L, dto.expiresIn)
        assertTrue(dto.created)
    }

    /**
     * `created` manque quand le backend ne le pose pas. Sans valeur par défaut,
     * la lecture lèverait — et la connexion échouerait sur un champ qui ne dit
     * rien d'essentiel.
     */
    @Test
    fun `une reponse sans created se lit quand meme`() {
        val dto = json.decodeFromString<SessionDto>(
            """{"access_token":"a","refresh_token":"b","expires_in":60}""",
        )
        assertFalse(dto.created)
    }

    @Test
    fun `la demande part dans les noms que le backend attend`() {
        val ecrit = json.encodeToString(
            DemandeDeConnexion(code = "c", redirectUri = "https://x/cb", codeVerifier = "v"),
        )
        assertTrue("redirect_uri absent : $ecrit", ecrit.contains("\"redirect_uri\""))
        assertTrue("code_verifier absent : $ecrit", ecrit.contains("\"code_verifier\""))
        assertFalse("un nom Kotlin a fui : $ecrit", ecrit.contains("redirectUri"))
        assertFalse("un nom Kotlin a fui : $ecrit", ecrit.contains("codeVerifier"))
    }

    /**
     * **Le facteur mille.**
     *
     * Le backend compte l'expiration en secondes ; tout le reste du projet en
     * millisecondes. Se tromper ici rendrait un jeton expiré à la seconde, ou
     * valide pour un an — et les deux se présentent comme des déconnexions
     * inexplicables.
     */
    @Test
    fun `expires_in est en secondes, l'expiration en millisecondes`() {
        val dto = SessionDto("a", "b", expiresIn = 3600, created = false)
        val session = dto.versDomaine(maintenant = 1_000_000L)
        assertEquals(1_000_000L + 3_600_000L, session.expiration)
    }

    /**
     * La marge de validité n'est pas du confort : une requête part avec un
     * jeton valide et arrive après son expiration si l'on vise l'instant pile.
     */
    @Test
    fun `un jeton qui expire dans trente secondes est deja tenu pour mort`() {
        val session = SessionDto("a", "b", 30, false).versDomaine(0L)
        assertFalse(session.valide(maintenant = 0L))
        assertTrue(session.valide(maintenant = 0L, marge = 0L))
    }
}
