package com.labibleont.ont.features.search

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.labibleont.ont.kit.ports.GlossaryRepository
import com.labibleont.ont.kit.ports.SearchIndex
import com.labibleont.ont.kit.search.SearchEngine
import com.labibleont.ont.kit.search.SearchHit
import com.labibleont.ont.kit.search.SearchScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * La recherche dans le corpus.
 *
 * ## Chargé à la première requête, pas au lancement
 *
 * `search.json` fait 640 Ko. Le décoder au démarrage retarderait l'ouverture
 * pour une fonction qu'on n'emploie pas à chaque session.
 *
 * ## Le délai avant de chercher n'est pas un confort
 *
 * Sans lui, taper « chesed » lance six balayages du corpus, dont cinq dont on
 * jette le résultat. À l'échelle actuelle chacun prend quelques millisecondes ;
 * à soixante-dix livres rédigés, ils se verront. Le poser maintenant coûte
 * quatre lignes, le poser plus tard demandera de comprendre pourquoi la saisie
 * saccade.
 */
public class SearchModel(
    private val index: SearchIndex,
    private val glossaire: GlossaryRepository,
) : ViewModel() {

    public var requete: String by mutableStateOf("")
        private set

    public var portee: SearchScope by mutableStateOf(SearchScope.ALL)
        private set

    public var resultats: kotlin.collections.List<SearchHit> by mutableStateOf(emptyList())
        private set

    public var cherche: Boolean by mutableStateOf(false)
        private set

    private var lemmes: Set<String> = emptySet()
    private var enCours: Job? = null

    public fun saisir(texte: String) {
        requete = texte
        relancer()
    }

    public fun changerPortee(nouvelle: SearchScope) {
        portee = nouvelle
        relancer()
    }

    private fun relancer() {
        enCours?.cancel()
        val q = requete.trim()
        if (q.length < 2) {
            resultats = emptyList()
            cherche = false
            return
        }
        cherche = true
        enCours = viewModelScope.launch {
            delay(220)
            val trouves = withContext(Dispatchers.IO) {
                if (lemmes.isEmpty()) {
                    // Les lemmes rattrapent les passages où le terme ne paraît
                    // qu'en hébreu : taper « chesed » doit les trouver aussi.
                    lemmes = glossaire.entries().map { it.lemma }.toSet()
                }
                SearchEngine.search(q, index.records(), portee, lemmes)
            }
            resultats = trouves
            cherche = false
        }
    }
}
