package com.labibleont.ont.data

import com.labibleont.ont.data.bundle.versDomaine
import com.labibleont.ont.kit.corpus.CibleDuNiveauTrois
import com.labibleont.ont.kit.corpus.Inline
import com.labibleont.ont.data.schema.ontJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import com.labibleont.ont.data.schema.Inline as DtoInline

/**
 * La translittération de niveau 3 porte sa destination jusqu'au domaine.
 *
 * ## Ce qui se mesure, et pourquoi le JSON et pas l'objet
 *
 * Le contrat n'est pas la classe Kotlin, c'est le **fichier** : le pipeline
 * écrit `cible` quand elle existe et **l'escamote** sinon — 1257 nœuds sur 2086
 * n'en portent pas. Un décodeur qui exigerait la clé rendrait le corpus entier
 * illisible, et c'est exactement le défaut trouvé côté Swift, où la variante
 * d'enum écrivait `decode` au lieu de `decodeIfPresent`.
 *
 * L'épreuve part donc du JSON tel qu'il est livré.
 */
class NiveauTroisTouchableTest {

    /// **`ontJson` et non une instance à soi.** Le discriminant vaut `"t"`, et
    /// il est déclaré là-bas précisément pour qu'aucun appelant ne monte son
    /// propre `Json` par mégarde. Une épreuve qui le referait mesurerait sa
    /// propre configuration, pas celle de la liseuse.
    private fun noeud(texte: String): Inline =
        ontJson.decodeFromString(DtoInline.serializer(), texte).versDomaine()

    @Test
    fun `une translitteration sans cible se decode et reste inerte`() {
        val n = noeud("""{"t":"translit","translit":"vayiven","hebrew":"וַיִּבֶן"}""")
        assertNull((n as Inline.Translit).cible)
    }

    @Test
    fun `une cible de terme traverse jusqu'au domaine`() {
        val n = noeud(
            """{"t":"translit","translit":"chesed","hebrew":"חֶסֶד",""" +
                """"cible":{"t":"term","lemma":"chesed"}}""",
        )
        assertEquals(
            CibleDuNiveauTrois.Term("chesed"),
            (n as Inline.Translit).cible,
        )
    }

    /**
     * **Les deux destinations ne se confondent pas.** Une fiche de Shem vit
     * dans `shemot.json`, pas dans le glossaire : confondre les deux enverrait
     * chercher un nom propre là où il n'est pas, et le lecteur toucherait sans
     * rien obtenir.
     */
    @Test
    fun `une cible de Shem traverse jusqu'au domaine`() {
        val n = noeud(
            """{"t":"translit","translit":"Noach","hebrew":"נֹחַ",""" +
                """"cible":{"t":"shem","lemma":"noach"}}""",
        )
        assertEquals(
            CibleDuNiveauTrois.Shem("noach"),
            (n as Inline.Translit).cible,
        )
    }
}
