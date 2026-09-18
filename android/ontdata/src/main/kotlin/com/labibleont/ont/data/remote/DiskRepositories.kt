package com.labibleont.ont.data.remote

import android.content.Context
import com.labibleont.ont.data.bundle.AssetCorpusRepository
import com.labibleont.ont.data.bundle.AssetGlossaryRepository
import com.labibleont.ont.data.bundle.AssetLoader
import com.labibleont.ont.data.bundle.AssetSearchIndex
import com.labibleont.ont.data.bundle.AssetShemotRepository
import com.labibleont.ont.data.bundle.versDomaine
import com.labibleont.ont.data.schema.Book as DtoBook
import com.labibleont.ont.data.schema.CorpusFile
import com.labibleont.ont.data.schema.GlossaryFile
import com.labibleont.ont.data.schema.OccurrencesFile
import com.labibleont.ont.data.schema.PrononciationFile
import com.labibleont.ont.data.schema.SearchFile
import com.labibleont.ont.data.schema.ShemotFile
import com.labibleont.ont.kit.corpus.Book
import com.labibleont.ont.kit.corpus.Corpus
import com.labibleont.ont.kit.corpus.ShemEntry
import com.labibleont.ont.kit.glossary.GlossaryEntry
import com.labibleont.ont.kit.glossary.Occurrence
import com.labibleont.ont.kit.ports.FeuilleDePrononciation
import com.labibleont.ont.kit.ports.CorpusRepository
import com.labibleont.ont.kit.ports.GlossaryRepository
import com.labibleont.ont.kit.ports.PrononciationRepository
import com.labibleont.ont.kit.ports.SearchIndex
import com.labibleont.ont.kit.ports.ShemotRepository
import com.labibleont.ont.kit.search.SearchRecord
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

    // ## Le demi-mégaoctet était un bon argument, et la paresse le règle
    //
    // Ce bloc disait : « les occurrences restent au bundle tant qu'aucune
    // version téléchargée n'a été lue ». La phrase se contredisait — rien
    // n'allait jamais en lire une. Le fichier fait 492 Ko et la liste du lexique
    // n'en a pas besoin : c'est vrai, et c'est pour ça qu'on ne le charge qu'à
    // la première fiche ouverte, pas pour ça qu'on renonce au corpus à jour.
    //
    // iOS lit du disque depuis toujours, paresseusement lui aussi. Après une
    // mise à jour du corpus, Android servait donc des occurrences périmées
    // pendant que le lexique, lui, était neuf.
    private val duDisque: Map<String, kotlin.collections.List<Occurrence>>? by lazy {
        runCatching {
            val f = File(dossier, "occurrences.json")
            if (!f.exists()) null
            else json.decodeFromString<OccurrencesFile>(f.readText())
                .byLemma.mapValues { (_, v) -> v.map { it.versDomaine() } }
        }.getOrNull()
    }

    override fun occurrences(lemma: String): kotlin.collections.List<Occurrence> =
        duDisque?.get(lemma) ?: bundle.occurrences(lemma)
}

/**
 * L'index de recherche, disque par-dessus bundle.
 *
 * ## Il n'existait pas, et rien ne le disait
 *
 * `AssetSearchIndex` était branché directement dans `MainActivity`, sans pendant
 * disque — seul port du corpus dans ce cas. La recherche restait donc sur
 * l'index embarqué à la compilation, quelle que soit la fraîcheur du reste.
 *
 * Le défaut se doublait en amont : `CorpusUpdater` ne déclarait pas
 * `"recherche"`, donc le fichier n'était même pas téléchargé. Réparer un seul
 * des deux n'aurait rien donné — d'où les deux dans le même changement.
 *
 * Chargement paresseux : `search.json` fait 640 Ko, et l'ouverture de l'app n'en
 * a pas besoin.
 */
public class DiskSearchIndex(
    private val context: Context,
    private val dossier: File = CorpusUpdater.dossierParDefaut(context),
) : SearchIndex {

    private val bundle = AssetSearchIndex(context)
    private val json = Json { ignoreUnknownKeys = true }

    private val duDisque: kotlin.collections.List<SearchRecord>? by lazy {
        runCatching {
            val f = File(dossier, "search.json")
            if (!f.exists()) null
            else json.decodeFromString<SearchFile>(f.readText())
                .records.map { it.versDomaine() }
        }.getOrNull()
    }

    override fun records(): kotlin.collections.List<SearchRecord> =
        duDisque ?: bundle.records()
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

/**
 * La feuille de prononciation, du disque quand elle y est, du bundle sinon.
 *
 * ## Le défaut que ça ferme — #263
 *
 * Le pipeline émet `dist/prononciation.json`, iOS le lit dans sept fichiers, et
 * **Android ne l'ouvrait nulle part**. Le fichier était donc *exclu de la copie*
 * vers les ressources, avec un commentaire disant que c'était un écart de parité
 * et non une décision. Cette classe est ce qui permet de retirer l'exclusion.
 *
 * ## Pourquoi une seule classe et non deux
 *
 * Les autres ports d'ici ont un dépôt bundle et un dépôt disque qui l'enveloppe.
 * Celui-ci suit iOS, où `DiskPrononciationRepository` fait les deux : la feuille
 * est **un seul document**, sans clé ni index, donc il n'y a rien à composer
 * entre les deux sources. Le disque gagne s'il porte le fichier, le bundle
 * répond sinon.
 *
 * ## L'absence est un état, pas un échec
 *
 * `null` quand ni le disque ni le bundle ne portent la feuille : le pipeline
 * n'écrit rien quand le vault ne la porte pas. C'est à l'écran de dire ce qu'il
 * attend, pas à ce lecteur de fabriquer un titre vide — ce qui ferait croire à
 * une panne.
 *
 * `by lazy` mémorise aussi l'absence, et c'est voulu : sans ça, chaque ouverture
 * de l'onglet retenterait deux lectures de fichier pour rien.
 *
 * ## Ce qui reste ouvert, et qui n'est pas d'ici
 *
 * iOS porte un `oublier()` qui vide le cache après une mise à jour du corpus.
 * **Aucun dépôt disque d'Android n'en a** — `DiskGlossaryRepository`,
 * `DiskShemotRepository` et `DiskSearchIndex` mémorisent tous par `by lazy` sans
 * invalidation. Une feuille corrigée n'apparaît donc qu'au prochain lancement.
 * Ajouter l'invalidation ici seulement rendrait ce port incohérent avec ses
 * quatre voisins ; c'est un chantier à part, et il se décide en une fois.
 */
public class DiskPrononciationRepository(
    private val context: Context,
    private val dossier: File = CorpusUpdater.dossierParDefaut(context),
) : PrononciationRepository {

    private val json = Json { ignoreUnknownKeys = true }

    private val feuille: FeuilleDePrononciation? by lazy {
        val dto = duDisque() ?: duBundle()
        dto?.let { FeuilleDePrononciation(titre = it.title, blocs = it.blocks.map { b -> b.versDomaine() }) }
    }

    private fun duDisque(): PrononciationFile? = runCatching {
        val f = File(dossier, "prononciation.json")
        if (!f.exists()) null else json.decodeFromString<PrononciationFile>(f.readText())
    }.getOrNull()

    private fun duBundle(): PrononciationFile? = runCatching {
        AssetLoader.decode<PrononciationFile>(context, "data/prononciation.json")
    }.getOrNull()

    override fun feuille(): FeuilleDePrononciation? = feuille
}
