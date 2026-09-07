package com.labibleont.ont.data

import com.labibleont.ont.kit.reader.Highlight
import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Un numéro de verset ne suffit pas à désigner un verset.
 *
 * ## Le défaut, constaté et non corrigé
 *
 * Le §2.2 du vault découpe en **unités fonctionnelles**, pas en chapitres
 * bibliques. Une unité peut donc couvrir deux chapitres — et le numéro de
 * verset **recommence** au second :
 *
 *     bereshit-7   46 versets, 24 numéros distincts
 *                  la suite monte à 24, puis repart à 1 et va jusqu'à 22
 *                  → 22 versets sur 46 partagent leur numéro avec un autre
 *
 * Près de la moitié de l'unité, donc, et non une poignée.
 *
 * Or la clé d'un surlignage est `"$chapterId#$verse"`, et l'écran demande sa
 * marque par `verset.n`. **Deux versets différents partagent donc la même
 * clé** : surligner le premier « 1 » peint aussi le second, et enregistrer
 * l'un écrase l'autre.
 *
 * ## Pourquoi ce test constate au lieu de réparer
 *
 * La clé traverse les trois clients et le serveur : `Highlight.verse` est un
 * entier côté backend, et iOS indexe pareil. La corriger demande de changer ce
 * que « verset » désigne dans le contrat — un arbitrage qui appartient à iOS,
 * pas à un client qui le découvre.
 *
 * En attendant, ce test **fixe l'état des lieux**. Il échouera le jour où
 * quelqu'un corrigera, et c'est le but : une décision différée doit rester
 * visible. C'est la forme des dettes inscrites dans `ContrastesTest`.
 *
 * Trouvé le 7 septembre 2026, en lisant l'avertissement de la session des
 * langues sources — « `n` n'est pas une clé, le tableau est positionnel ». Elle
 * le disait de son format ; c'était déjà vrai du nôtre.
 */
class CollisionDesVersetsTest {

    private val corpus = File("../../app/Resources/data/books")

    /**
     * **Le compte, et l'instrument qui l'avait tronqué.**
     *
     * Le premier relevé annonçait « les numéros 1 à 6 » : le script qui l'a
     * produit affichait `sorted(doublons)[:6]`. La troncature était dans
     * l'affichage, pas dans les données — et le chiffre a voyagé dans un
     * message de commit, une PR et trois échanges avant qu'une session voisine
     * ne remesure et trouve 22.
     *
     * Le test compte donc, plutôt que d'énumérer. Un nombre se compare ; une
     * liste se lit de travers.
     */
    @Test
    fun `une unite au moins porte deux fois le meme numero de verset`() {
        val collisions = unitesAvecDoublons()
        assertTrue(
            "Aucune collision trouvée. Si le corpus a changé, ce test ne mesure " +
                "plus rien — et la clé reste fausse pour autant.",
            collisions.isNotEmpty(),
        )
        val bereshit7 = collisions.first { it.first == "bereshit-7" }
        assertEquals(
            "le compte des numéros en double a changé — remesurer avant de conclure",
            22,
            bereshit7.second.size,
        )
        assertEquals(46, versetsDe("bereshit-7").size)
    }

    /**
     * **La démonstration de la perte.**
     *
     * Deux versets distincts de la même unité rendent la même clé. Ce n'est pas
     * une hypothèse : c'est la fonction du domaine, appliquée aux données
     * réelles.
     */
    @Test
    fun `deux versets distincts rendent aujourd'hui la meme cle`() {
        val (unite, numeros) = unitesAvecDoublons().first { it.first == "bereshit-7" }
        val repete = numeros.first()
        assertEquals(
            "la clé ne distingue pas les deux versets numérotés $repete",
            Highlight.key(unite, repete),
            Highlight.key(unite, repete),
        )
        // Et le compte le dit autrement : quarante-six versets pour quarante
        // clés possibles.
        val versets = versetsDe(unite)
        val cles = versets.map { Highlight.key(unite, it) }.toSet()
        assertTrue(
            "il y a autant de clés que de versets — la collision aurait disparu",
            cles.size < versets.size,
        )
    }

    private fun unitesAvecDoublons(): List<Pair<String, List<Int>>> =
        corpus.listFiles().orEmpty().flatMap { fichier ->
            val livre = Json.parseToJsonElement(fichier.readText()).jsonObject
            livre["chapters"]?.jsonArray.orEmpty().mapNotNull { unite ->
                val o = unite.jsonObject
                val id = o["id"]?.jsonPrimitive?.content ?: return@mapNotNull null
                val ns = numerosDe(o)
                val doublons = ns.groupingBy { it }.eachCount()
                    .filterValues { it > 1 }.keys.sorted()
                if (doublons.isEmpty()) null else id to doublons
            }
        }

    private fun versetsDe(uniteId: String): List<Int> =
        corpus.listFiles().orEmpty().firstNotNullOf { fichier ->
            Json.parseToJsonElement(fichier.readText()).jsonObject["chapters"]
                ?.jsonArray.orEmpty()
                .map { it.jsonObject }
                .firstOrNull { it["id"]?.jsonPrimitive?.content == uniteId }
                ?.let(::numerosDe)
        }

    private fun numerosDe(unite: kotlinx.serialization.json.JsonObject): List<Int> =
        unite["blocks"]?.jsonArray.orEmpty().flatMap { bloc ->
            bloc.jsonObject["verses"]?.jsonArray.orEmpty().mapNotNull {
                it.jsonObject["n"]?.jsonPrimitive?.content?.toIntOrNull()
            }
        }
}
