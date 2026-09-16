package com.labibleont.ont.data

import com.labibleont.ont.data.bundle.versDomaine
import com.labibleont.ont.data.schema.PrononciationFile
import com.labibleont.ont.data.schema.ontJson
import com.labibleont.ont.kit.corpus.Block
import com.labibleont.ont.kit.corpus.plainText
import java.io.File
import kotlinx.serialization.decodeFromString
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * La feuille de prononciation, décodée depuis le fichier que le pipeline écrit.
 *
 * ## Le défaut que ça ferme — #263
 *
 * `dist/prononciation.json` existe depuis le 8 septembre 2026. iOS le lit dans
 * sept fichiers ; **Android ne l'ouvrait nulle part**, et le fichier était exclu
 * de la copie vers les ressources faute de lecteur.
 *
 * L'écart avait été *déclaré* — un commentaire disait « écart de parité, pas
 * décision » — et `prononciation.json` figurait même dans `connusDuCorpus`. Or
 * inscrire un nom à cette liste **déclare qu'un lecteur existe** : la
 * déclaration était fausse pendant quatre jours, et la garde ne pouvait pas le
 * voir. Elle vérifie qu'un fichier est connu, jamais qu'il est lu.
 *
 * ## Ce que ce test garde, et ce qu'il ne garde pas
 *
 * Il garde le **décodage** et la **traduction vers le domaine** — la chaîne
 * `schema.rs` → `Schema.kt` → `Block`. Il ne garde pas le rendu : les
 * composables exigent un `Context` et une composition, que ce module n'a pas.
 *
 * Comme [CorpusReelTest], il s'abstient quand le corpus n'est pas là. Un test
 * rouge doit vouloir dire « le code est faux », jamais « il manque un fichier ».
 */
class PrononciationLueTest {

    private val donnees = File("../../app/Resources/data")
    private val fichier = File(donnees, "prononciation.json")
    private fun present() = fichier.isFile

    private fun lire(): PrononciationFile =
        ontJson.decodeFromString<PrononciationFile>(fichier.readText())

    /**
     * Le cas du défaut : le fichier se décode. Avant ce travail, aucun type
     * Kotlin ne le nommait — `PrononciationFile` n'existait pas dans `Schema.kt`
     * tant que le générateur ne l'y mettait pas, et rien ne l'aurait réclamé.
     */
    @Test
    fun `la feuille se decode et porte un titre`() {
        if (!present()) return
        val f = lire()
        assertTrue("la feuille n'a pas de titre", f.title.isNotBlank())
        assertTrue("la feuille n'a aucun bloc", f.blocks.isNotEmpty())
    }

    /**
     * Le compte plutôt que la présence.
     *
     * Un fichier vide et un fichier absent ne se distinguent pas, et l'un des
     * deux est une panne — le vault a vu une table passer de 67 entrées à 0 sous
     * une construction verte. On éprouve donc qu'il reste du texte après la
     * traduction vers le domaine, pas seulement que des blocs existent.
     */
    @Test
    fun `les blocs portent du texte apres traduction vers le domaine`() {
        if (!present()) return
        val blocs = lire().blocks.map { it.versDomaine() }
        assertEquals("des blocs se sont perdus en chemin", lire().blocks.size, blocs.size)

        val signes = blocs.sumOf { bloc ->
            when (bloc) {
                is Block.Heading -> bloc.nodes.plainText().length
                is Block.Paragraph -> bloc.nodes.plainText().length
                else -> 0
            }
        }
        assertTrue("la feuille est structurellement là mais vide de texte", signes > 200)
    }

    /**
     * Les deux formes que l'écran rend, et rien d'autre.
     *
     * `PrononciationSheet` traite `Heading` et `Paragraph`, et **ignore le
     * reste**. Ce test dit à quelle condition cette décision reste vraie : si le
     * vault pose un jour une liste ou une citation dans cette feuille, elle
     * disparaîtrait de l'écran sans un mot. Le test rougit alors, et c'est le
     * seul moment où quelqu'un pourrait s'en apercevoir.
     */
    @Test
    fun `la feuille ne contient que des titres et des paragraphes`() {
        if (!present()) return
        val inattendus = lire().blocks.map { it.versDomaine() }
            .filterNot { it is Block.Heading || it is Block.Paragraph }
            .map { it::class.simpleName }
            .toSet()
        assertEquals(
            "des blocs que l'écran n'affiche pas : $inattendus — " +
                "les ajouter à `PrononciationSheet` ou justifier leur absence",
            emptySet<String?>(),
            inattendus,
        )
    }
}
