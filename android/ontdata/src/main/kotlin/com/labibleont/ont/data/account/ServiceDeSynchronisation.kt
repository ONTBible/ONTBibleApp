package com.labibleont.ont.data.account

import com.labibleont.ont.kit.account.Fusion
import com.labibleont.ont.kit.ports.HighlightRepository
import com.labibleont.ont.kit.ports.PositionRepository
import com.labibleont.ont.kit.ports.Reporter
import com.labibleont.ont.kit.ports.SilentReporter
import com.labibleont.ont.kit.reader.Highlight
import com.labibleont.ont.kit.reader.HighlightColor
import com.labibleont.ont.kit.reader.ReadingPosition
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
internal data class MarqueDto(
    val id: String,
    @SerialName("book_id") val bookId: String,
    @SerialName("chapter_id") val chapterId: String,
    val verse: Int,
    val color: String,
    val note: String? = null,
    @SerialName("updated_at") val updatedAt: Long,
    val deleted: Boolean = false,
)

@Serializable
internal data class PositionDto(
    @SerialName("book_id") val bookId: String,
    @SerialName("chapter_id") val chapterId: String,
    @SerialName("chapter_title") val chapterTitle: String,
    val verse: Int,
    @SerialName("updated_at") val updatedAt: Long,
)

@Serializable
internal data class Envoi(
    val highlights: kotlin.collections.List<MarqueDto> = emptyList(),
    val position: PositionDto? = null,
)

@Serializable
internal data class Reception(
    val highlights: kotlin.collections.List<MarqueDto> = emptyList(),
    val position: PositionDto? = null,
    @SerialName("server_time") val serverTime: Long = 0,
)

/**
 * La synchronisation, contre `/sync`.
 *
 * ## Ce qui monte, et ce qui ne monte jamais
 *
 * Une référence — livre, unité, verset — et jamais le texte. Le corpus est déjà
 * dans l'app des deux côtés ; l'envoyer ne servirait qu'à ranger sur un serveur
 * ce que le lecteur a souligné, en clair, avec son identité. Le domaine du
 * backend l'écrit en tête de `sync.rs`, au titre de l'article 9 du RGPD.
 *
 * La note, elle, monte : c'est le lecteur qui l'a écrite et il veut la
 * retrouver ailleurs. C'est aussi la donnée la plus sensible du lot, et c'est
 * pourquoi la connexion reste **facultative** — l'app entière marche sans.
 *
 * ## L'ordre : tirer, fusionner, pousser
 *
 * Pousser d'abord ferait monter un état qui ignore ce que l'autre appareil a
 * fait, et le serveur trancherait sur des dates sans avoir vu la fusion. On
 * tire, on fusionne ici — où la règle est éprouvée —, puis on pousse le
 * résultat.
 */
public class ServiceDeSynchronisation(
    private val racine: String,
    private val compte: ServiceDeCompte,
    private val marques: HighlightRepository,
    private val positions: PositionRepository,
    private val rapporteur: Reporter = SilentReporter,
) {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    /**
     * Un aller-retour complet. Rend le nombre de marques après fusion, ou
     * `null` si rien n'a pu se faire.
     *
     * Une panne de réseau n'est pas une erreur : l'app garde ce qu'elle a et
     * réessaiera au prochain lancement. Ce qui remonte au rapporteur, ce sont
     * les réponses qu'on a reçues et qu'on n'a pas su traiter.
     */
    public suspend fun synchroniser(): Int? {
        val jeton = jetonValide() ?: return null

        val recu = runCatching { tirer(jeton) }.onFailure {
            rapporteur.report(it, "lecture de /sync")
        }.getOrNull() ?: return null

        val fusionnees = Fusion.marques(
            locales = marques.allForSync(),
            distantes = recu.highlights.map { it.versDomaine() },
        )
        val position = Fusion.position(
            locale = positions.position,
            distante = recu.position?.versDomaine(),
        )

        fusionnees.forEach(marques::save)
        position?.let(positions::remember)

        runCatching { pousser(jeton, fusionnees, position) }.onFailure {
            rapporteur.report(it, "envoi vers /sync")
        }
        return fusionnees.size
    }

    /**
     * Le jeton d'accès, rafraîchi s'il le faut.
     *
     * On ne tente pas la requête pour voir : un 401 coûte un aller-retour, et
     * le rafraîchissement devrait se faire quand même. Autant regarder la date
     * qu'on a déjà.
     */
    private suspend fun jetonValide(): String? {
        val session = compte.session() ?: return null
        if (session.valide(System.currentTimeMillis())) return session.jetonDAcces
        return compte.rafraichir()?.jetonDAcces
    }

    private fun tirer(jeton: String): Reception? {
        val connexion = (URL("$racine/sync").openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 15_000
            readTimeout = 30_000
            setRequestProperty("Authorization", "Bearer $jeton")
        }
        return try {
            if (connexion.responseCode != 200) null
            else json.decodeFromString<Reception>(
                connexion.inputStream.use { it.readBytes().decodeToString() },
            )
        } finally {
            connexion.disconnect()
        }
    }

    private fun pousser(
        jeton: String,
        marques: kotlin.collections.List<Highlight>,
        position: ReadingPosition?,
    ) {
        val corps = json.encodeToString(
            Envoi(marques.map { it.versDto() }, position?.versDto()),
        )
        val connexion = (URL("$racine/sync").openConnection() as HttpURLConnection).apply {
            requestMethod = "PUT"
            connectTimeout = 15_000
            readTimeout = 30_000
            doOutput = true
            setRequestProperty("Authorization", "Bearer $jeton")
            setRequestProperty("Content-Type", "application/json")
        }
        try {
            connexion.outputStream.use { it.write(corps.toByteArray()) }
            connexion.responseCode
        } finally {
            connexion.disconnect()
        }
    }
}

internal fun MarqueDto.versDomaine(): Highlight = Highlight(
    id = id,
    bookId = bookId,
    chapterId = chapterId,
    verse = verse,
    // La couleur inconnue retombe sur l'or, et **le disque la réécrira** :
    // voir `HighlightColor.depuis`. Tant que la synchronisation n'a pas tranché
    // la question, ce chemin-ci est celui par lequel le rétrécissement
    // atteindrait le serveur.
    color = HighlightColor.depuis(color),
    note = note,
    updatedAt = Instant.ofEpochMilli(updatedAt),
    deleted = deleted,
)

internal fun Highlight.versDto(): MarqueDto = MarqueDto(
    id = id,
    bookId = bookId,
    chapterId = chapterId,
    verse = verse,
    color = color.cle,
    note = note,
    updatedAt = updatedAt.toEpochMilli(),
    deleted = deleted,
)

internal fun PositionDto.versDomaine(): ReadingPosition = ReadingPosition(
    bookId = bookId,
    chapterId = chapterId,
    chapterTitle = chapterTitle,
    verse = verse,
    date = Instant.ofEpochMilli(updatedAt),
)

internal fun ReadingPosition.versDto(): PositionDto = PositionDto(
    bookId = bookId,
    chapterId = chapterId,
    chapterTitle = chapterTitle,
    verse = verse,
    updatedAt = date.toEpochMilli(),
)
