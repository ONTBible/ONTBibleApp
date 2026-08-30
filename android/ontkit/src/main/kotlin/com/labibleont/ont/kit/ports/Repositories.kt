package com.labibleont.ont.kit.ports

import com.labibleont.ont.kit.corpus.Book
import com.labibleont.ont.kit.corpus.BookOutline
import com.labibleont.ont.kit.corpus.Chapter
import com.labibleont.ont.kit.corpus.ShemEntry
import com.labibleont.ont.kit.corpus.Corpus
import com.labibleont.ont.kit.glossary.GlossaryEntry
import com.labibleont.ont.kit.glossary.Occurrence
import com.labibleont.ont.kit.reader.DailyVerse
import com.labibleont.ont.kit.reader.Highlight
import com.labibleont.ont.kit.reader.ReadingPosition
import com.labibleont.ont.kit.reader.ReadingPreferences
import com.labibleont.ont.kit.search.SearchRecord

/*
 * Les ports — ce que le domaine attend du monde extérieur.
 *
 * Une interface par responsabilité, et non un gros objet qui saurait tout
 * faire. C'est la ségrégation des interfaces, et ce qu'elle achète est concret :
 * un écran déclare exactement ce dont il a besoin, et un test fournit une
 * doublure de trois lignes plutôt qu'un corpus complet.
 *
 * Aucune de ces interfaces ne mentionne un fichier, une URL, une base ou un
 * `Context`. Le module ne peut d'ailleurs pas : il est en JVM pure, le SDK
 * Android n'y est pas.
 */

/** L'accès au texte. */
public interface CorpusRepository {
    /** L'arborescence des 70 slots — assez légère pour le lancement. */
    public fun corpora(): kotlin.collections.List<Corpus>

    /** Le contenu complet d'un livre, chargé à la demande. */
    public fun book(id: String): Book

    /** Tous les livres, dans l'ordre canonique des slots. */
    public fun allBooks(): kotlin.collections.List<BookOutline> =
        runCatching { corpora() }.getOrDefault(emptyList())
            .flatMap { corpus -> corpus.modes.sortedBy { it.order }.flatMap { it.books } }

    /** Les seuls livres qui portent du texte aujourd'hui. */
    public fun writtenBooks(): kotlin.collections.List<BookOutline> =
        allBooks().filterNot { it.empty }

    /** Une unité précise, introduction comprise. */
    public fun chapter(bookId: String, chapterId: String): Chapter? {
        val livre = runCatching { book(bookId) }.getOrNull() ?: return null
        if (livre.intro?.id == chapterId) return livre.intro
        return livre.chapters.firstOrNull { it.id == chapterId }
    }
}

/** L'accès au glossaire des intraduisibles. */
public interface GlossaryRepository {
    public fun entries(): kotlin.collections.List<GlossaryEntry>

    /** Les passages où un lemme paraît. */
    public fun occurrences(lemma: String): kotlin.collections.List<Occurrence>
}

/**
 * L'accès aux fiches des noms propres.
 *
 * Un port distinct du glossaire, comme le fichier est distinct : les Shemot ne
 * sont pas des intraduisibles, et les mêler ferait promettre une fiche de
 * concept là où il y a un porteur.
 */
public interface ShemotRepository {
    public fun fiche(lemma: String): ShemEntry?
}

/** L'index de recherche. */
public interface SearchIndex {
    public fun records(): kotlin.collections.List<SearchRecord>
}

/** Les surlignages et les notes. */
public interface HighlightRepository {
    /** Ce qui se **montre** — les pierres tombales en sont exclues. */
    public fun all(): kotlin.collections.List<Highlight>

    /**
     * Ce qui se **synchronise** — pierres tombales comprises.
     *
     * Deux méthodes et non une, parce que les deux besoins sont opposés : une
     * liste d'annotations ne doit pas afficher ce qui est supprimé, et un envoi
     * qui omettrait les suppressions les perdrait.
     */
    public fun allForSync(): kotlin.collections.List<Highlight>

    public fun highlight(chapterId: String, verse: Int): Highlight?
    public fun save(highlight: Highlight)
    public fun remove(highlight: Highlight)
}

/** La position de lecture. */
public interface PositionRepository {
    public val position: ReadingPosition?
    public fun remember(position: ReadingPosition)
}

/** Les réglages de lecture. */
public interface PreferencesRepository {
    public var preferences: ReadingPreferences
}

/**
 * Le vivier du verset du jour.
 *
 * Un port à part et non une méthode de [CorpusRepository] : le widget n'a
 * besoin que de celui-ci, et lui donner accès au corpus entier l'obligerait à
 * charger un arbre de 750 Ko pour afficher trois lignes. Sur Android la
 * contrainte est encore plus rude qu'ailleurs — un widget qui dépasse son
 * budget mémoire n'affiche pas une erreur, il affiche du vide.
 */
public interface DailyVerseRepository {
    public fun pool(): kotlin.collections.List<DailyVerse>
}
