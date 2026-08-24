package com.labibleont.ont.features.reading

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.labibleont.ont.kit.corpus.Book
import com.labibleont.ont.kit.corpus.Chapter
import com.labibleont.ont.kit.corpus.Corpus
import com.labibleont.ont.kit.ports.CorpusRepository
import com.labibleont.ont.kit.ports.HighlightRepository
import com.labibleont.ont.kit.ports.PositionRepository
import com.labibleont.ont.kit.ports.PreferencesRepository
import com.labibleont.ont.kit.reader.Highlight
import com.labibleont.ont.kit.reader.HighlightColor
import com.labibleont.ont.kit.reader.ReadingPosition
import com.labibleont.ont.kit.reader.ReadingPreferences
import com.labibleont.ont.kit.reader.VerseRange
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * L'état de la lecture.
 *
 * ## Il ne connaît que des ports
 *
 * `CorpusRepository`, `PreferencesRepository` — des interfaces, jamais une
 * implémentation. Ce module n'a d'ailleurs pas `ontdata` sur son chemin de
 * classes : l'appeler ne compilerait pas. C'est `app` qui décide, au moment de
 * câbler, que derrière le port il y a des assets.
 *
 * Ce que ça achète : ce modèle se teste sans émulateur, avec une doublure de
 * trois lignes.
 *
 * ## Le chargement va sur un autre fil
 *
 * *Bereshit* fait 750 Ko de JSON. Le décoder sur le fil principal ferait sauter
 * l'animation d'ouverture — visiblement, et sur tout téléphone d'entrée de
 * gamme. On charge donc en arrière-plan et on publie l'état ensuite.
 */
public class ReadingModel(
    private val corpusRepository: CorpusRepository,
    private val preferencesRepository: PreferencesRepository,
    private val highlightRepository: HighlightRepository,
    private val positionRepository: PositionRepository,
) : ViewModel() {

    public var corpora: kotlin.collections.List<Corpus> by mutableStateOf(emptyList())
        private set

    public var livre: Book? by mutableStateOf(null)
        private set

    public var chapitre: Chapter? by mutableStateOf(null)
        private set

    public var chargement: Boolean by mutableStateOf(false)
        private set

    /** L'échec du chargement, à montrer plutôt qu'à taire. */
    public var echec: String? by mutableStateOf(null)
        private set

    public var preferences: ReadingPreferences
        get() = preferencesRepository.preferences
        set(value) {
            preferencesRepository.preferences = value
            // Une préférence change le rendu de tout le texte : on force la
            // recomposition en republiant le chapitre courant.
            chapitre = chapitre
        }

    public fun chargerLArborescence() {
        if (corpora.isNotEmpty()) return
        viewModelScope.launch {
            runCatching { withContext(Dispatchers.IO) { corpusRepository.corpora() } }
                .onSuccess { corpora = it }
                .onFailure { echec = it.message }
        }
    }

    public fun ouvrir(bookId: String, chapterId: String? = null) {
        chargement = true
        echec = null
        viewModelScope.launch {
            runCatching { withContext(Dispatchers.IO) { corpusRepository.book(bookId) } }
                .onSuccess { ouvert ->
                    livre = ouvert
                    chapitre = when {
                        chapterId != null ->
                            ouvert.chapters.firstOrNull { it.id == chapterId }
                                ?: ouvert.intro.takeIf { it?.id == chapterId }
                        // Sans unité désignée, on ouvre l'introduction quand il
                        // y en a une : c'est elle qui dit comment lire le livre.
                        else -> ouvert.intro ?: ouvert.chapters.firstOrNull()
                    }
                }
                .onFailure { echec = it.message }
            chargement = false
        }
    }

    /** L'unité suivante dans le livre ouvert, s'il y en a une. */
    public fun suivante(): Chapter? {
        val ouvert = livre ?: return null
        val courante = chapitre ?: return ouvert.chapters.firstOrNull()
        if (courante.id == ouvert.intro?.id) return ouvert.chapters.firstOrNull()
        val i = ouvert.chapters.indexOfFirst { it.id == courante.id }
        return ouvert.chapters.getOrNull(i + 1)
    }

    /** L'unité précédente, l'introduction comprise. */
    public fun precedente(): Chapter? {
        val ouvert = livre ?: return null
        val courante = chapitre ?: return null
        val i = ouvert.chapters.indexOfFirst { it.id == courante.id }
        if (i <= 0) return ouvert.intro.takeIf { courante.id != it?.id }
        return ouvert.chapters.getOrNull(i - 1)
    }

    public fun aller(vers: Chapter) {
        chapitre = vers
        selection = emptySet()
    }

    // ── La sélection ────────────────────────────────────────────────────

    /**
     * Les versets désignés.
     *
     * Un ensemble et non un seul verset : on cite « 1-3, 7 », on surligne un
     * passage. C'est aussi ce qui justifie que `VerseRange` vive dans le
     * domaine — la forme est lue **et** écrite, par l'écran et par le routeur.
     */
    public var selection: Set<Int> by mutableStateOf(emptySet())
        private set

    public fun basculer(verset: Int) {
        selection = if (verset in selection) selection - verset else selection + verset
    }

    public fun deselectionner() {
        selection = emptySet()
    }

    /** Le renvoi de la sélection — « Bereshit 1:1-3, 7 ». */
    public fun renvoi(): String =
        VerseRange.reference(selection, chapitre?.title.orEmpty())

    // ── Les surlignages ─────────────────────────────────────────────────

    /**
     * Un compteur qui ne sert qu'à faire recomposer.
     *
     * Le dépôt de surlignages n'est pas observable — c'est un port, et un port
     * qui rendrait un flux imposerait la coroutine à toutes ses
     * implémentations, y compris aux doublures de test. On publie donc un
     * jeton que l'écran lit : il change à chaque écriture, la recomposition
     * suit, et le port reste une interface de trois méthodes.
     */
    public var revisionDesMarques: Int by mutableStateOf(0)
        private set

    public fun surlignage(verset: Int): Highlight? {
        val id = chapitre?.id ?: return null
        return highlightRepository.highlight(id, verset)
    }

    public fun surligner(couleur: HighlightColor) {
        val unite = chapitre ?: return
        for (verset in selection) {
            val existant = highlightRepository.highlight(unite.id, verset)
            highlightRepository.save(
                Highlight(
                    // On réemploie l'identité quand elle existe : changer la
                    // couleur d'un surlignage n'en crée pas un second, sinon la
                    // synchronisation en verrait deux pour un même verset.
                    id = existant?.id ?: java.util.UUID.randomUUID().toString(),
                    bookId = unite.bookId,
                    chapterId = unite.id,
                    verse = verset,
                    color = couleur,
                    note = existant?.note,
                ),
            )
        }
        revisionDesMarques += 1
        selection = emptySet()
    }

    public fun effacerLesMarques() {
        val unite = chapitre ?: return
        for (verset in selection) {
            highlightRepository.highlight(unite.id, verset)?.let(highlightRepository::remove)
        }
        revisionDesMarques += 1
        selection = emptySet()
    }

    /** Vrai si au moins un verset désigné porte déjà une marque. */
    public fun selectionEstMarquee(): Boolean {
        val unite = chapitre ?: return false
        return selection.any { highlightRepository.highlight(unite.id, it) != null }
    }

    // ── La position ─────────────────────────────────────────────────────

    /**
     * Retenir où l'on en est.
     *
     * Le dépôt n'écrit que si la position a réellement bougé — ce fichier est
     * touché à chaque défilement.
     */
    public fun retenir(verset: Int) {
        val unite = chapitre ?: return
        positionRepository.remember(
            ReadingPosition(
                bookId = unite.bookId,
                chapterId = unite.id,
                chapterTitle = unite.title,
                verse = verset,
            ),
        )
    }

    public fun reprendre(): ReadingPosition? = positionRepository.position

    // ── L'état du corpus ────────────────────────────────────────────────

    /**
     * Ce que l'onglet Vous affiche du corpus.
     *
     * Calculé depuis l'arborescence déjà chargée, et non lu d'un fichier de
     * rapport : `dist/manifest.json` existe, mais c'est un rapport de **build**
     * — il dit ce que le pipeline a produit, pas ce que cette app porte. Les
     * deux coïncident aujourd'hui et n'ont aucune raison de le rester quand
     * l'app téléchargera ses mises à jour de corpus.
     */
    public val slotsTotal: Int
        get() = corpora.sumOf { c -> c.modes.sumOf { it.books.size } }

    public val slotsRediges: Int
        get() = corpora.sumOf { c -> c.modes.sumOf { m -> m.books.count { !it.empty } } }

    public val versets: Int
        get() = corpora.sumOf { c -> c.modes.sumOf { m -> m.books.sumOf { it.verseCount } } }
}
