package com.labibleont.ont.data

import com.labibleont.ont.data.bundle.versDomaine
import com.labibleont.ont.data.schema.Book
import com.labibleont.ont.data.schema.CorpusFile
import com.labibleont.ont.data.schema.DailyFile
import com.labibleont.ont.data.schema.GlossaryFile
import com.labibleont.ont.data.schema.OccurrencesFile
import com.labibleont.ont.data.schema.SearchFile
import com.labibleont.ont.data.schema.ontJson
import com.labibleont.ont.kit.corpus.lemmas
import com.labibleont.ont.kit.corpus.plainText
import java.io.File
import kotlinx.serialization.decodeFromString
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Le test qui éprouve toute la chaîne d'un coup.
 *
 * `schema.rs` → `codegen/kotlin.rs` → `Schema.kt` → décodage du **vrai**
 * corpus. Chaque maillon est déjà couvert de son côté ; celui-ci vérifie que
 * mis bout à bout ils lisent les fichiers que le pipeline écrit vraiment.
 *
 * Il lit les fichiers sur le disque plutôt que les assets, pour tourner sur la
 * JVM en quelques millisecondes plutôt que sur un émulateur en une minute. Ce
 * sont les mêmes octets : la tâche `copierLesDonnees` ne fait que les recopier.
 *
 * Si le corpus n'est pas là — dépôt fraîchement cloné, pipeline jamais lancé —
 * les tests ne **échouent** pas : ils n'ont rien à éprouver. Un test rouge doit
 * vouloir dire « le code est faux », jamais « il manque un fichier ».
 */
class CorpusReelTest {

    private val donnees = File("../../app/Resources/data")
    private fun present() = donnees.isDirectory

    private inline fun <reified T> lire(chemin: String): T =
        ontJson.decodeFromString<T>(File(donnees, chemin).readText())

    @Test
    fun `l'arborescence des soixante-dix slots se decode`() {
        if (!present()) return
        val fichier = lire<CorpusFile>("corpus.json")
        val corpora = fichier.corpora.map { it.versDomaine() }

        val livres = corpora.flatMap { it.modes.flatMap { m -> m.books } }
        assertEquals("le corpus compte soixante-dix slots", 70, livres.size)
        // Les numéros de slot sont continus de 1 à 70, sans trou ni doublon.
        assertEquals((1..70).toSet(), livres.map { it.slot }.toSet())
    }

    @Test
    fun `chaque livre redige se decode entierement`() {
        if (!present()) return
        val fichier = lire<CorpusFile>("corpus.json")
        val rediges = fichier.corpora
            .flatMap { it.modes.flatMap { m -> m.books } }
            .filterNot { it.empty }

        assertTrue("au moins un livre rédigé", rediges.isNotEmpty())

        for (outline in rediges) {
            val livre = lire<Book>("books/${outline.id}.json").versDomaine()
            assertEquals(outline.id, livre.id)
            // Le texte doit vraiment être là — un décodage qui rend des
            // structures vides passerait tous les tests de forme.
            // Un livre non vide n'a pas forcément de chapitres : *Chazon
            // Avraham* n'a que sa feuille d'introduction, et c'est un état
            // légitime du corpus — le slot est ouvert, le texte vient.
            val fragments = livre.chapters.flatMap { it.verses }.map { it.nodes } +
                listOfNotNull(livre.intro).flatMap { intro ->
                    intro.blocks.map { bloc ->
                        when (bloc) {
                            is com.labibleont.ont.kit.corpus.Block.Paragraph -> bloc.nodes
                            is com.labibleont.ont.kit.corpus.Block.Heading -> bloc.nodes
                            else -> emptyList()
                        }
                    }
                }
            assertTrue(
                "${livre.id} ne rend aucun texte",
                fragments.any { it.plainText().isNotBlank() },
            )
        }
    }

    @Test
    fun `un intraduisible sans fiche ne casse pas la lecture`() {
        if (!present()) return
        // ## Ce que ce test dit, et ce qu'il ne dit pas
        //
        // Vingt lemmes de *Bereshit* n'ont pas d'entrée au glossaire — `ishto`,
        // `neshei`, `eshet`, `leolam`, `ad-olam`… Ce sont des formes dérivées
        // de termes qui, eux, en ont une : *ishah*, *olam*, *ish*.
        //
        // Ce n'est **pas** un défaut, et la première version de ce test avait
        // tort de l'affirmer. La liseuse iOS prévoit l'état et le nomme —
        // « Terme non documenté : balisé dans le texte mais n'a pas encore
        // d'entrée dans le glossaire ». Un slot ouvert dont le texte vient plus
        // tard, comme le reste du corpus.
        //
        // Ce qu'on éprouve ici est donc la vraie propriété : le texte se lit
        // entièrement, et un lemme absent se résout à « rien » sans lever.
        val glossaire = lire<GlossaryFile>("glossary.json").entries.associateBy { it.lemma }
        val fichier = lire<CorpusFile>("corpus.json")

        var touches = 0
        for (outline in fichier.corpora.flatMap { it.modes.flatMap { m -> m.books } }
            .filterNot { it.empty }) {
            val livre = lire<Book>("books/${outline.id}.json").versDomaine()
            for (chapitre in livre.chapters) {
                for (bloc in chapitre.blocks) {
                    if (bloc !is com.labibleont.ont.kit.corpus.Block.Verses) continue
                    for (lemme in bloc.verses.flatMap { it.nodes.lemmas }) {
                        // Nul est une réponse, pas une erreur.
                        glossaire[lemme]
                        touches += 1
                    }
                }
            }
        }
        assertTrue("aucun intraduisible relevé — le décodage rend du vide", touches > 0)
    }

    @Test
    fun `le lexique, les occurrences, la recherche et le vivier se decodent`() {
        if (!present()) return
        assertTrue(lire<GlossaryFile>("glossary.json").entries.isNotEmpty())
        assertTrue(lire<OccurrencesFile>("occurrences.json").byLemma.isNotEmpty())
        assertTrue(lire<SearchFile>("search.json").records.isNotEmpty())
        assertTrue(lire<DailyFile>("daily.json").verses.isNotEmpty())
    }

    @Test
    fun `les quatre fichiers portent le meme numero de schema`() {
        if (!present()) return
        // Deux numéros différents voudraient dire deux builds mélangés, donc un
        // corpus dont une moitié ne correspond pas à l'autre.
        val numeros = setOf(
            lire<CorpusFile>("corpus.json").schema,
            lire<GlossaryFile>("glossary.json").schema,
            lire<SearchFile>("search.json").schema,
            lire<DailyFile>("daily.json").schema,
        )
        assertEquals("numéros de schéma mêlés : $numeros", 1, numeros.size)
    }
}
