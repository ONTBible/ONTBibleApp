package com.labibleont.ont.features.qahal

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.labibleont.ont.kit.corpus.Chapter
import com.labibleont.ont.kit.corpus.Verse
import com.labibleont.ont.kit.ports.CorpusRepository
import com.labibleont.ont.kit.ports.DailyVerseRepository
import com.labibleont.ont.kit.reader.DailySelection
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Le verset du jour, dans sa forme complète.
 *
 * ## Deux dépôts pour un seul verset, et ce n'est pas un doublon
 *
 * [DailyVerseRepository] dit **lequel** — il porte le vivier plat, 60 Ko, celui
 * que le widget peut se permettre de charger. [CorpusRepository] dit **comment
 * il se compose** — l'arbre d'inline avec ses intraduisibles, ses gloses, son
 * hébreu.
 *
 * Le Qahal a les deux à sa disposition, donc il rend le verset comme il se lit
 * dans le chapitre, en or. Le widget n'a que le premier, et rend du texte plat.
 * C'est la même sélection dans les deux cas — `DailySelection` est une fonction
 * pure de la date — mais pas le même rendu, parce que les contraintes ne sont
 * pas les mêmes.
 */
public class QahalModel(
    private val vivier: DailyVerseRepository,
    private val corpus: CorpusRepository,
) : ViewModel() {

    public var chapitre: Chapter? by mutableStateOf(null)
        private set

    public var verset: Verse? by mutableStateOf(null)
        private set

    public fun choisir() {
        if (verset != null) return
        viewModelScope.launch {
            val trouve = withContext(Dispatchers.IO) {
                val plat = DailySelection.verse(Instant.now(), vivier.pool())
                    ?: return@withContext null
                val unite = corpus.chapter(plat.bookId, plat.chapterId)
                    ?: return@withContext null
                unite to unite.verses.firstOrNull { it.n == plat.verse }
            }
            chapitre = trouve?.first
            verset = trouve?.second
        }
    }
}
