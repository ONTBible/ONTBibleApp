package com.labibleont.ont.data.store

import android.content.Context
import com.labibleont.ont.kit.ports.HighlightRepository
import com.labibleont.ont.kit.ports.PositionRepository
import com.labibleont.ont.kit.ports.PreferencesRepository
import com.labibleont.ont.kit.reader.DailyVerseSchedule
import com.labibleont.ont.kit.reader.Highlight
import com.labibleont.ont.kit.reader.HighlightColor
import com.labibleont.ont.kit.reader.ReadingFont
import com.labibleont.ont.kit.reader.ReadingPosition
import com.labibleont.ont.kit.reader.ReadingPreferences
import com.labibleont.ont.kit.reader.ReadingTheme
import java.io.File
import java.time.Instant
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Ce que le lecteur produit, persisté en JSON dans le conteneur de l'app.
 *
 * ## Pourquoi un fichier JSON explicite, et pas Room
 *
 * La synchronisation visée passe par **notre** backend, pas par un service de
 * la plateforme. Ce fichier *est* déjà le corps de la future requête
 * `PUT /sync` — le jour où le compte existe, il n'y a rien à convertir.
 *
 * Room apporterait des requêtes et des migrations pour un objet qu'on lit en
 * entier et qu'on écrit en entier. C'est le même raisonnement que côté iOS, où
 * SwiftData a été écarté pour la même raison.
 *
 * ## Un type, trois ports
 *
 * Surlignages, position et réglages partagent le même fichier et la même
 * écriture. Les **consommateurs**, eux, ne dépendent que du port qui les
 * concerne : un écran de lecture déclare `HighlightRepository` et ne voit rien
 * du reste. C'est la ségrégation des interfaces — une classe peut en
 * implémenter trois, un appelant ne doit pas en connaître trois.
 *
 * ## Tout est lu à la construction
 *
 * L'état vit en mémoire ; les lectures sont donc synchrones, ce qui compte : le
 * rendu d'un chapitre demande le surlignage de chaque verset pendant la
 * composition. Un flux asynchrone rendrait un état vide le temps d'une image, et
 * le lecteur verrait ses marques clignoter à chaque ouverture.
 */
public class FileReaderStore(
    context: Context,
    nom: String = "lecteur.json",
) : HighlightRepository, PositionRepository, PreferencesRepository {

    private val fichier = File(context.filesDir, nom)
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private var etat: Etat

    /**
     * Index par verset.
     *
     * Pour que le rendu d'un chapitre ne balaie pas la liste complète à chaque
     * ligne — à quarante versets et quelques centaines de surlignages, la
     * différence se voit au défilement.
     */
    private var parVerset: MutableMap<String, Highlight> = mutableMapOf()

    init {
        etat = runCatching {
            if (fichier.exists()) json.decodeFromString<Etat>(fichier.readText()) else Etat()
        }.getOrElse { Etat() }
        purgerLesPierresTombales()
        reindexer()
    }

    // ── Surlignages ─────────────────────────────────────────────────────

    /**
     * Ce qui se **montre**. Les pierres tombales restent sur le disque et dans
     * l'envoi, jamais dans une liste que le lecteur regarde.
     */
    override fun all(): kotlin.collections.List<Highlight> =
        etat.highlights.filterNot { it.deleted }.map { it.versDomaine() }

    /** Ce qui part au serveur — suppressions comprises. */
    override fun allForSync(): kotlin.collections.List<Highlight> =
        etat.highlights.map { it.versDomaine() }

    override fun highlight(chapterId: String, verse: Int): Highlight? =
        parVerset[Highlight.key(chapterId, verse)]

    override fun save(highlight: Highlight) {
        val ligne = highlight.versFichier()
        val i = etat.highlights.indexOfFirst { it.id == highlight.id }
            .takeIf { it >= 0 }
            ?: etat.highlights.indexOfFirst { cle(it) == highlight.key }
        if (i >= 0) etat.highlights[i] = ligne else etat.highlights.add(ligne)
        parVerset[highlight.key] = highlight
        ecrire()
    }

    /**
     * Marque, ne détruit pas.
     *
     * La ligne reste, avec `deleted` et un horodatage frais : c'est ce qui
     * permet à la suppression de voyager. Sans elle, l'appareil qui efface n'a
     * plus rien à envoyer, et le prochain échange ressuscite le surlignage
     * depuis un autre appareil — ou depuis le serveur lui-même.
     *
     * La note part avec : une pierre tombale ne conserve rien de ce qu'elle
     * remplace, elle dit seulement que ça a existé et que c'est fini.
     */
    override fun remove(highlight: Highlight) {
        val i = etat.highlights.indexOfFirst { it.id == highlight.id }
            .takeIf { it >= 0 }
            ?: etat.highlights.indexOfFirst { cle(it) == highlight.key }
        if (i < 0) return

        etat.highlights[i] = etat.highlights[i].copy(
            deleted = true,
            note = null,
            updatedAt = Instant.now().toEpochMilli(),
        )
        parVerset.remove(highlight.key)
        ecrire()
    }

    // ── Position ────────────────────────────────────────────────────────

    override val position: ReadingPosition?
        get() = etat.position?.let {
            ReadingPosition(
                bookId = it.bookId,
                chapterId = it.chapterId,
                chapterTitle = it.chapterTitle,
                verse = it.verse,
                date = Instant.ofEpochMilli(it.date),
            )
        }

    override fun remember(position: ReadingPosition) {
        // Ce fichier est touché à chaque défilement : ne réécrire que si la
        // position a réellement bougé.
        if (etat.position?.chapterId == position.chapterId &&
            etat.position?.verse == position.verse
        ) {
            return
        }
        etat.position = PositionFichier(
            bookId = position.bookId,
            chapterId = position.chapterId,
            chapterTitle = position.chapterTitle,
            verse = position.verse,
            date = position.date.toEpochMilli(),
        )
        ecrire()
    }

    // ── Réglages ────────────────────────────────────────────────────────

    override var preferences: ReadingPreferences
        get() = etat.preferences.versDomaine()
        set(value) {
            if (value == etat.preferences.versDomaine()) return
            etat.preferences = value.versFichier()
            ecrire()
        }

    // ── Persistance ─────────────────────────────────────────────────────

    private fun reindexer() {
        parVerset = etat.highlights
            .filterNot { it.deleted }
            .associateBy({ cle(it) }, { it.versDomaine() })
            .toMutableMap()
    }

    /**
     * Les pierres tombales ne s'accumulent pas indéfiniment.
     *
     * Quatre-vingt-dix jours : bien au-delà du temps qu'un appareil peut rester
     * hors ligne sans être réinstallé, et assez court pour que le fichier ne
     * grossisse pas d'une ligne par suppression pendant des années. Passé ce
     * délai, un appareil qui referait surface avec une vieille copie pourrait
     * ressusciter un surlignage — c'est le compromis connu de toute
     * synchronisation par pierres tombales, et personne n'en a trouvé de
     * meilleur.
     */
    private fun purgerLesPierresTombales() {
        val limite = Instant.now().minusSeconds(90L * 24 * 60 * 60).toEpochMilli()
        val avant = etat.highlights.size
        etat.highlights.removeAll { it.deleted && it.updatedAt < limite }
        if (etat.highlights.size != avant) ecrire()
    }

    /**
     * Écriture **atomique**.
     *
     * On écrit à côté puis on renomme : un renommage sur le même système de
     * fichiers est atomique, une écriture directe ne l'est pas. Sans ça, une
     * app tuée en plein `write` laisse un JSON tronqué — et le lecteur perd
     * tous ses surlignages d'un coup, sans rien avoir fait.
     */
    private fun ecrire() {
        runCatching {
            val provisoire = File(fichier.parentFile, "${fichier.name}.tmp")
            provisoire.writeText(json.encodeToString(etat))
            provisoire.renameTo(fichier)
        }
    }

    private fun cle(h: HighlightFichier) = Highlight.key(h.chapterId, h.verse)
}

/*
 * La forme du fichier.
 *
 * Séparée des types du domaine, exactement comme `schema.Inline` l'est de
 * `corpus.Inline` : ce sont deux choses différentes qui se ressemblent
 * aujourd'hui. Le jour où le domaine gagne un champ calculé, il n'a pas à
 * atterrir sur le disque ; le jour où le serveur en ajoute un, le domaine n'a
 * pas à le connaître.
 *
 * Les dates voyagent en millisecondes depuis 1970 — un entier, que le backend
 * Rust lit sans négocier de format.
 */

@Serializable
private data class Etat(
    val highlights: MutableList<HighlightFichier> = mutableListOf(),
    var position: PositionFichier? = null,
    var preferences: PreferencesFichier = PreferencesFichier(),
)

@Serializable
private data class HighlightFichier(
    val id: String,
    val bookId: String,
    val chapterId: String,
    val verse: Int,
    val color: String,
    val note: String? = null,
    val updatedAt: Long,
    val deleted: Boolean = false,
)

@Serializable
private data class PositionFichier(
    val bookId: String,
    val chapterId: String,
    val chapterTitle: String,
    val verse: Int,
    val date: Long,
)

@Serializable
private data class PreferencesFichier(
    val showGloss: Boolean = true,
    val showLevel3: Boolean = true,
    val textSize: Double = 19.0,
    val lineSpacing: Double = 0.5,
    val theme: String = "parchment",
    val bodyFont: String = "literata",
    val continuous: Boolean = true,
    val dailyEnabled: Boolean = false,
    val dailyHour: Int = 7,
    val dailyMinute: Int = 30,
)

private fun HighlightFichier.versDomaine() = Highlight(
    id = id,
    bookId = bookId,
    chapterId = chapterId,
    verse = verse,
    color = HighlightColor.depuis(color),
    note = note,
    updatedAt = Instant.ofEpochMilli(updatedAt),
    deleted = deleted,
)

private fun Highlight.versFichier() = HighlightFichier(
    id = id,
    bookId = bookId,
    chapterId = chapterId,
    verse = verse,
    color = color.cle,
    note = note,
    updatedAt = updatedAt.toEpochMilli(),
    deleted = deleted,
)

private fun PreferencesFichier.versDomaine() = ReadingPreferences(
    showGloss = showGloss,
    showLevel3 = showLevel3,
    textSize = textSize,
    lineSpacing = lineSpacing,
    theme = ReadingTheme.depuis(theme),
    bodyFont = ReadingFont.depuis(bodyFont),
    continuous = continuous,
    daily = DailyVerseSchedule.borne(dailyEnabled, dailyHour, dailyMinute),
)

private fun ReadingPreferences.versFichier() = PreferencesFichier(
    showGloss = showGloss,
    showLevel3 = showLevel3,
    textSize = textSize,
    lineSpacing = lineSpacing,
    theme = theme.cle,
    bodyFont = bodyFont.cle,
    continuous = continuous,
    dailyEnabled = daily.enabled,
    dailyHour = daily.hour,
    dailyMinute = daily.minute,
)
