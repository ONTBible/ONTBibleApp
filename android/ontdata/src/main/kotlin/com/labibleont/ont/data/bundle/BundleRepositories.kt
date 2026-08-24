package com.labibleont.ont.data.bundle

import android.content.Context
import com.labibleont.ont.data.schema.CorpusFile
import com.labibleont.ont.data.schema.DailyFile
import com.labibleont.ont.data.schema.GlossaryFile
import com.labibleont.ont.data.schema.OccurrencesFile
import com.labibleont.ont.data.schema.SearchFile
import com.labibleont.ont.data.schema.ontJson
import com.labibleont.ont.data.schema.Book as DtoBook
import com.labibleont.ont.kit.corpus.Book
import com.labibleont.ont.kit.corpus.Corpus
import com.labibleont.ont.kit.glossary.GlossaryEntry
import com.labibleont.ont.kit.glossary.Occurrence
import com.labibleont.ont.kit.ports.CorpusRepository
import com.labibleont.ont.kit.ports.DailyVerseRepository
import com.labibleont.ont.kit.ports.GlossaryRepository
import com.labibleont.ont.kit.ports.SearchIndex
import com.labibleont.ont.kit.reader.DailyVerse
import com.labibleont.ont.kit.search.SearchRecord
import kotlinx.serialization.decodeFromString

/**
 * Le chargement des données produites par le pipeline.
 *
 * Toute la connaissance du format — nom des fichiers, sous-dossiers, schéma
 * JSON — est enfermée ici. Si le pipeline change sa sortie, c'est le seul
 * endroit à toucher.
 *
 * ## Le découpage du chargement est délibéré
 *
 * L'arborescence des 70 slots et le lexique arrivent au lancement (20 Ko +
 * 384 Ko), le contenu d'un livre seulement quand on l'ouvre — *Bereshit* fait
 * 750 Ko à lui seul — et l'index de recherche à la première requête (640 Ko).
 *
 * Tout charger au lancement tiendrait en mémoire sur un téléphone récent et
 * ferait attendre une seconde sur un téléphone d'entrée de gamme, qui est
 * précisément celui d'une bonne part du parc Android.
 */
internal object AssetLoader {

    class Introuvable(nom: String) : Exception(
        // Sans guillemets, délibérément : le filet d'expurgation de Sentry
        // masque tout texte cité de plus de douze caractères — c'est ainsi
        // qu'une note de lecteur serait interceptée. Un nom de ressource ne
        // doit pas ressembler à une note, sinon le diagnostic part expurgé et
        // ne dit plus rien.
        "Ressource introuvable dans les assets : $nom",
    )

    inline fun <reified T> decode(context: Context, chemin: String): T {
        val texte = try {
            context.assets.open(chemin).bufferedReader().use { it.readText() }
        } catch (e: java.io.IOException) {
            throw Introuvable(chemin)
        }
        return ontJson.decodeFromString<T>(texte)
    }
}

/**
 * Une valeur chargée une seule fois, sûre entre fils d'exécution.
 *
 * `lazy` avec verrou par défaut : le corpus peut être demandé par l'interface
 * et par le widget au même instant, et décoder deux fois 640 Ko serait payé
 * deux fois pour rien.
 */
private class Cache<T>(private val charger: () -> T) {
    private val valeur: T by lazy(LazyThreadSafetyMode.SYNCHRONIZED) { charger() }
    fun get(): T = valeur
}

/** Le corpus, lu des assets de l'app. */
public class AssetCorpusRepository(private val context: Context) : CorpusRepository {

    private val arborescence = Cache {
        AssetLoader.decode<CorpusFile>(context, "data/corpus.json")
            .corpora.map { it.versDomaine() }
    }

    // Un livre ouvert reste chargé : on y revient — chapitre suivant, retour
    // depuis une fiche de lexique — et le relire coûterait 750 Ko à chaque fois.
    private val livres = java.util.concurrent.ConcurrentHashMap<String, Book>()

    override fun corpora(): kotlin.collections.List<Corpus> = arborescence.get()

    override fun book(id: String): Book = livres.getOrPut(id) {
        AssetLoader.decode<DtoBook>(context, "data/books/$id.json").versDomaine()
    }
}

/** Le lexique des intraduisibles. */
public class AssetGlossaryRepository(private val context: Context) : GlossaryRepository {

    private val entrees = Cache {
        AssetLoader.decode<GlossaryFile>(context, "data/glossary.json")
            .entries.map { it.versDomaine() }
    }

    // Les occurrences vivent dans leur propre fichier, et il fait 492 Ko. On ne
    // le charge qu'à la première fiche ouverte : la liste du lexique n'en a pas
    // besoin, elle affiche des compteurs que l'entrée porte déjà.
    private val parLemme = Cache {
        AssetLoader.decode<OccurrencesFile>(context, "data/occurrences.json")
            .byLemma.mapValues { (_, v) -> v.map { it.versDomaine() } }
    }

    override fun entries(): kotlin.collections.List<GlossaryEntry> = entrees.get()

    override fun occurrences(lemma: String): kotlin.collections.List<Occurrence> =
        parLemme.get()[lemma].orEmpty()
}

/** L'index de recherche. */
public class AssetSearchIndex(private val context: Context) : SearchIndex {

    private val entrees = Cache {
        AssetLoader.decode<SearchFile>(context, "data/search.json")
            .records.map { it.versDomaine() }
    }

    override fun records(): kotlin.collections.List<SearchRecord> = entrees.get()
}

/**
 * Le vivier du verset du jour.
 *
 * Son propre fichier, et son propre port. Le widget n'a que celui-ci à charger
 * — 60 Ko contre les 750 Ko d'un livre. Sur Android, un widget qui dépasse son
 * budget mémoire n'affiche pas une erreur : il affiche du vide.
 */
public class AssetDailyVerseRepository(private val context: Context) : DailyVerseRepository {

    private val vivier = Cache {
        AssetLoader.decode<DailyFile>(context, "data/daily.json")
            .verses.map { it.versDomaine() }
    }

    override fun pool(): kotlin.collections.List<DailyVerse> = vivier.get()
}
