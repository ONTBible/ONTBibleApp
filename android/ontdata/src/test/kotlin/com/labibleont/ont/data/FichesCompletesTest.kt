package com.labibleont.ont.data

import com.labibleont.ont.data.bundle.versDomaine
import com.labibleont.ont.data.schema.GlossaryFile
import com.labibleont.ont.data.schema.ShemotFile
import com.labibleont.ont.data.schema.ontJson
import com.labibleont.ont.kit.corpus.Block
import java.io.File
import kotlinx.serialization.decodeFromString
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Ce que les fiches portent, et que les écrans doivent rendre.
 *
 * ## Le défaut que ça ferme
 *
 * `TermSheet` ne rendait que `Block.Paragraph`. Mesuré sur le corpus du
 * 16 septembre 2026 : **1 727 titres perdus sur 378 fiches**, jetés sans un
 * mot. Une fiche porte trois mouvements — la racine, le porteur, les renvois —
 * et sans leurs titres ils arrivaient collés en un seul flot.
 *
 * Le vault avait autorisé les titres le 30 août, et la règle d'avant disait
 * « des paragraphes et rien d'autre » **parce que la feuille laissait tomber le
 * reste sans rien dire**. La contrainte est tombée quand iOS a su les rendre ;
 * Android ne l'a jamais su.
 *
 * ## Ce que ce test garde
 *
 * Le **compte**, pas la présence : un fichier de fiches structurellement là
 * mais sans titre serait le même défaut, silencieux autrement.
 *
 * Il ne garde pas le rendu — les composables exigent un `Context`. C'est
 * `BlocDeFiche` qui rend, et son `when` exhaustif est ce qui casse à l'ajout
 * d'un cas au domaine.
 */
class FichesCompletesTest {

    private val donnees = File("../../app/Resources/data")
    private fun present() = donnees.isDirectory

    private inline fun <reified T> lire(nom: String): T =
        ontJson.decodeFromString<T>(File(donnees, nom).readText())

    private fun blocsDesFiches(): kotlin.collections.List<Block> {
        val g = lire<GlossaryFile>("glossary.json").entries
            .flatMap { (it.definition.orEmpty()) + (it.taggingNote.orEmpty()) }
        val s = lire<ShemotFile>("shemot.json").entries.flatMap { it.definition }
        return (g + s).map { it.versDomaine() }
    }

    /**
     * Le cas du défaut. Il rougit contre le code d'hier — non pas en échouant à
     * décoder, mais en nommant le nombre exact de blocs qu'un écran limité aux
     * paragraphes laissait tomber.
     */
    @Test
    fun `les fiches portent des titres, que les ecrans doivent rendre`() {
        if (!present()) return
        val blocs = blocsDesFiches()
        val titres = blocs.count { it is Block.Heading }
        assertTrue(
            "aucun titre dans les fiches — soit le corpus a changé, soit la " +
                "mesure est fausse ; dans les deux cas `BlocDeFiche` est à relire",
            titres > 0,
        )
        // Le compte, pas la présence : un corpus qui perdrait ses titres en
        // route passerait un simple `isNotEmpty`.
        assertTrue("trop peu de titres pour être vrai : $titres", titres > 500)
    }

    /**
     * La limite de `BlocDeFiche`, éprouvée plutôt qu'affirmée.
     *
     * Il ne rend ni `Verses` ni `Table`. `Verses` ne peut pas arriver — la prose
     * de fiche n'en porte pas. `Table` est écrit dans les chuqqot du vault, mais
     * n'arrive pas jusqu'ici : `blocs_de_prose`, côté pipeline, ne rend que
     * `Para` et `Heading`. **Le trou est en amont.**
     *
     * Ce test dit à quelle condition cette décision reste vraie. S'il rougit, le
     * pipeline a changé et l'écran doit suivre — sans lui, une table arriverait
     * et disparaîtrait en silence.
     */
    @Test
    fun `aucune fiche ne porte de verset ni de tableau`() {
        if (!present()) return
        val nonRendus = blocsDesFiches()
            .filter { it is Block.Verses || it is Block.Table }
            .map { it::class.simpleName }
            .toSet()
        assertEquals(
            "des blocs que `BlocDeFiche` ne rend pas sont arrivés : $nonRendus — " +
                "le pipeline a changé, l'écran doit suivre",
            emptySet<String?>(),
            nonRendus,
        )
    }
}
