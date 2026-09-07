package com.labibleont.ont.data.remote

import android.content.Context
import com.labibleont.ont.data.bundle.AssetCorpusRepository
import com.labibleont.ont.data.bundle.AssetGlossaryRepository
import com.labibleont.ont.data.bundle.AssetShemotRepository
import com.labibleont.ont.data.bundle.versDomaine
import com.labibleont.ont.data.schema.Book as DtoBook
import com.labibleont.ont.data.schema.CorpusFile
import com.labibleont.ont.data.schema.GlossaryFile
import com.labibleont.ont.data.schema.ShemotFile
import com.labibleont.ont.kit.corpus.Book
import com.labibleont.ont.kit.corpus.Corpus
import com.labibleont.ont.kit.corpus.ShemEntry
import com.labibleont.ont.kit.glossary.GlossaryEntry
import com.labibleont.ont.kit.glossary.Occurrence
import com.labibleont.ont.kit.ports.CorpusRepository
import com.labibleont.ont.kit.ports.GlossaryRepository
import com.labibleont.ont.kit.ports.ShemotRepository
import java.io.File
import kotlinx.serialization.json.Json

/**
 * Le corpus, lu du disque quand il y est, du bundle sinon.
 *
 * ## Le bundle n'est pas un repli, c'est le socle
 *
 * L'app embarque un corpus complet : elle fonctionne au premier lancement, sans
 * réseau, et fonctionnera toujours. **Le disque ne fait que le recouvrir,
 * fichier par fichier.**
 *
 * Un livre téléchargé recouvre son homologue ; les autres continuent de venir du
 * bundle. Un téléchargement raté ne laisse donc aucun trou — il laisse ce qui
 * était là.
 *
 * ## Le recouvrement est par fichier, pas par lot
 *
 * Recouvrir en bloc — « tout le disque ou tout le bundle » — obligerait à
 * décider quoi faire quand sept livres sur huit sont arrivés. Fichier par
 * fichier, la question ne se pose pas : chaque morceau est le plus récent dont
 * on dispose.
 *
 * ## Et le disque ne gagne pas toujours
 *
 * C'est la leçon qui a coûté le plus cher. Le disque l'emportait sans condition,
 * si bien qu'une build neuve se faisait écraser au premier lancement par le
 * corpus publié — plus ancien tant que le site n'avait pas republié. Une build
 * portant 1 913 noms propres en affichait 217.
 *
 * L'arbitrage vit dans [CorpusUpdater.plusRecentQueLeBundle] : le disque n'est
 * rempli que par un manifeste dont on a **prouvé** qu'il est plus récent. Ici,
 * on lit ce qui s'y trouve sans avoir à se reposer la question.
 */
public class DiskCorpusRepository(
    private val context: Context,
    private val dossier: File = CorpusUpdater.dossierParDefaut(context),
) : CorpusRepository {

    private val bundle = AssetCorpusRepository(context)
    private val json = Json { ignoreUnknownKeys = true }

    override fun corpora(): kotlin.collections.List<Corpus> =
        lire<CorpusFile>("corpus.json")?.corpora?.map { it.versDomaine() } ?: bundle.corpora()

    override fun book(id: String): Book =
        lire<DtoBook>("books/$id.json")?.versDomaine() ?: bundle.book(id)

    private inline fun <reified T> lire(nom: String): T? = runCatching {
        val f = File(dossier, nom)
        if (!f.exists()) null else json.decodeFromString<T>(f.readText())
    }.getOrNull()
}

/** Le lexique, disque par-dessus bundle. */
public class DiskGlossaryRepository(
    private val context: Context,
    private val dossier: File = CorpusUpdater.dossierParDefaut(context),
) : GlossaryRepository {

    private val bundle = AssetGlossaryRepository(context)
    private val json = Json { ignoreUnknownKeys = true }

    override fun entries(): kotlin.collections.List<GlossaryEntry> = runCatching {
        val f = File(dossier, "glossary.json")
        if (!f.exists()) null
        else json.decodeFromString<GlossaryFile>(f.readText()).entries.map { it.versDomaine() }
    }.getOrNull() ?: bundle.entries()

    // Les occurrences restent au bundle tant qu'aucune version téléchargée n'a
    // été lue : le fichier fait un demi-mégaoctet, et la liste du lexique n'en a
    // pas besoin.
    override fun occurrences(lemma: String): kotlin.collections.List<Occurrence> =
        bundle.occurrences(lemma)
}

/** Les fiches des noms propres, disque par-dessus bundle. */
public class DiskShemotRepository(
    private val context: Context,
    private val dossier: File = CorpusUpdater.dossierParDefaut(context),
) : ShemotRepository {

    private val bundle = AssetShemotRepository(context)
    private val json = Json { ignoreUnknownKeys = true }

    private val duDisque: Map<String, ShemEntry>? by lazy {
        runCatching {
            val f = File(dossier, "shemot.json")
            if (!f.exists()) null
            else json.decodeFromString<ShemotFile>(f.readText())
                .entries.associate { it.lemma to it.versDomaine() }
        }.getOrNull()
    }

    override fun fiche(lemma: String): ShemEntry? =
        duDisque?.get(lemma) ?: bundle.fiche(lemma)
}
