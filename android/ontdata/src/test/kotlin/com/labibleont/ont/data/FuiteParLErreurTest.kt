package com.labibleont.ont.data

import com.labibleont.ont.kit.ports.ErreurSansContenu
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * La note d'un lecteur ne sort pas par un message d'erreur.
 *
 * ## Le défaut, reproduit avant d'être corrigé
 *
 * Une erreur de décodage porte le fichier qu'elle n'a pas su lire :
 *
 *     Unexpected JSON token at offset 61: Trailing comma …
 *     JSON input: {"highlights":[{"note":"ce passage m'a bouleversé hier soir"},]}
 *
 * Le magasin remontait cette erreur telle quelle, et le filtre de la remontée
 * n'expurgeait que le *message* de l'événement — pour une exception, il posait
 * une étiquette et laissait passer la valeur.
 *
 * Les annotations d'un lecteur de Bible relèvent de l'article 9 du RGPD. Elles
 * sortaient par le canal écrit pour les protéger.
 *
 * ## Ce que ce test garde
 *
 * Que ce qu'on remonte ne porte **jamais** le contenu. Il vérifie les deux
 * moitiés : que la fuite est réelle sur l'erreur d'origine — sinon il ne
 * mesurerait rien —, et qu'elle a disparu de ce qu'on transmet.
 */
class FuiteParLErreurTest {

    @Serializable
    private data class Marque(val note: String)

    @Serializable
    private data class Etat(val highlights: List<Marque> = emptyList())

    private val note = "ce passage m'a bouleversé hier soir"

    private fun echecDeDecodage(): Throwable = try {
        Json { ignoreUnknownKeys = true }
            .decodeFromString<Etat>("""{"highlights":[{"note":"$note"},]}""")
        error("le JSON abîmé aurait dû échouer")
    } catch (e: Exception) {
        e
    }

    /**
     * **Le témoin.** Sans lui, le test suivant passerait aussi le jour où la
     * bibliothèque cesserait de citer l'entrée — et il ne mesurerait plus rien.
     */
    @Test
    fun `l'erreur d'origine porte bien la note — sinon ce test ne mesure rien`() {
        assertTrue(
            "kotlinx ne cite plus l'entrée : ce test est devenu aveugle, le relire",
            echecDeDecodage().message.orEmpty().contains(note),
        )
    }

    @Test
    fun `ce qu'on remonte ne porte pas la note`() {
        val remontee = ErreurSansContenu(echecDeDecodage())

        assertFalse(
            "la note est sortie : ${remontee.message}",
            remontee.message.orEmpty().contains("bouleversé"),
        )
        assertFalse(remontee.message.orEmpty().contains("note"))
    }

    /**
     * Le type et la pile restent : ils disent **où** et **quoi** sans rien dire
     * du contenu. Les retirer aussi rendrait la remontée inutile.
     */
    @Test
    fun `le type et la pile survivent`() {
        val origine = echecDeDecodage()
        val remontee = ErreurSansContenu(origine)

        assertTrue(
            "le type doit rester lisible : ${remontee.message}",
            remontee.message.orEmpty().contains(origine::class.simpleName!!),
        )
        assertTrue("la pile doit survivre", remontee.stackTrace.isNotEmpty())
    }
}
