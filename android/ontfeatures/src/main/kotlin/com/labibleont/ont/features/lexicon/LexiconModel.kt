package com.labibleont.ont.features.lexicon

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.labibleont.ont.kit.glossary.GlossaryEntry
import com.labibleont.ont.kit.glossary.Occurrence
import com.labibleont.ont.kit.glossary.OccurrenceLevel
import com.labibleont.ont.kit.ports.GlossaryRepository
import com.labibleont.ont.kit.search.SearchEngine
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Le lexique des intraduisibles.
 *
 * C'est l'équivalent ONT d'un numéro Strong, à ceci près qu'il n'a pas fallu
 * l'inventer : le glossaire du `CLAUDE.md` §2.5 *est* le lexique, et le pipeline
 * le dérive à chaque build.
 */
public class LexiconModel(
    private val glossaire: GlossaryRepository,
) : ViewModel() {

    public var entrees: kotlin.collections.List<GlossaryEntry> by mutableStateOf(emptyList())
        private set

    public var requete: String by mutableStateOf("")

    /**
     * Ce que la liste montre.
     *
     * La recherche plie la requête **et** ce qu'elle compare, avec le même
     * `fold` que le pipeline : taper « chesed » doit trouver *Chesed*, et
     * « elohim » doit trouver *Élohîm*. Un `contains` nu ne le ferait pas, et
     * l'absence de résultat ressemblerait à « ce terme n'existe pas ».
     */
    public val visibles: kotlin.collections.List<GlossaryEntry>
        get() {
            val q = SearchEngine.fold(requete.trim())
            if (q.length < 2) return entrees
            return entrees.filter { entree ->
                SearchEngine.fold(entree.title).contains(q) ||
                    SearchEngine.fold(entree.lemma).contains(q) ||
                    entree.forms.any { SearchEngine.fold(it).contains(q) } ||
                    entree.hebrew?.let { SearchEngine.stripHebrew(it).contains(requete.trim()) } == true
            }
        }

    public fun charger() {
        if (entrees.isNotEmpty()) return
        viewModelScope.launch {
            entrees = withContext(Dispatchers.IO) {
                // Triées sur la forme pliée : sans ça, « Élohîm » se rangerait
                // après « Zohar » dans l'ordre des codes de caractères.
                glossaire.entries().sortedBy { SearchEngine.fold(it.title) }
            }
        }
    }

    public fun entree(lemme: String): GlossaryEntry? = entrees.firstOrNull { it.lemma == lemme }

    /**
     * Les passages où un lemme paraît.
     *
     * [corpsSeulement] sépare « où le texte dit ce mot » de « où on l'explique ».
     * Ce ne sont pas deux filtres du même besoin mais deux questions distinctes
     * (§2.1), et l'une ne doit pas noyer l'autre : `YHWH` paraît 150 fois dans
     * le corps et 313 fois dans les gloses.
     */
    public fun occurrences(
        lemme: String,
        corpsSeulement: Boolean,
    ): kotlin.collections.List<Occurrence> {
        val toutes = glossaire.occurrences(lemme)
        return if (corpsSeulement) toutes.filter { it.level == OccurrenceLevel.BODY } else toutes
    }
}
