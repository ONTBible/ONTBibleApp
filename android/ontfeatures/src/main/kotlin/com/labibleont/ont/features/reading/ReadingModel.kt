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
import com.labibleont.ont.kit.ports.PreferencesRepository
import com.labibleont.ont.kit.reader.ReadingPreferences
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
    }
}
