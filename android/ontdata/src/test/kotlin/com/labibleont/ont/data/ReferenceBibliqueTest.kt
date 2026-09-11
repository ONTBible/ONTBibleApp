package com.labibleont.ont.data

import com.labibleont.ont.data.bundle.versDomaine
import com.labibleont.ont.data.schema.ontJson
import com.labibleont.ont.kit.corpus.CibleDeLaReference
import com.labibleont.ont.kit.corpus.Inline
import com.labibleont.ont.kit.corpus.PorteeDeLaReference
import com.labibleont.ont.kit.corpus.plainText
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import com.labibleont.ont.data.schema.Inline as DtoInline

/**
 * La **référence biblique** traverse le fichier jusqu'au domaine.
 *
 * ## Ce qui se mesure, et pourquoi le JSON plutôt que l'objet
 *
 * Le contrat n'est pas la classe Kotlin, c'est le **fichier**. Le pipeline
 * écrit `cible` quand il a su résoudre, et **l'escamote** sinon : 208 des 915
 * références du corpus visent des livres que personne n'a traduits. Un décodeur
 * qui exigerait la clé rendrait le corpus entier illisible — c'est le défaut
 * déjà trouvé côté Swift, où une variante écrivait `decode` là où il fallait
 * `decodeIfPresent`, et c'est le même piège que `Subtitle.reference` documente.
 *
 * L'épreuve part donc du JSON tel qu'il est livré.
 *
 * ## Et pourquoi elle regarde la portée séparément
 *
 * `Genèse 3` et `Genèse 3:1` ne se distinguaient autrefois que par la nullité
 * d'un champ. Le type somme supprime le cas d'exception au lieu de le signaler :
 * une portée de plus au pipeline casse la compilation de `SchemaMapping` plutôt
 * que de se replier en silence sur « le chapitre entier ».
 */
class ReferenceBibliqueTest {

    /**
     * `ontJson` et non une instance à soi : le discriminant vaut `"t"`, et il
     * est déclaré là-bas pour qu'aucun appelant ne monte le sien par mégarde.
     */
    private fun noeud(texte: String): Inline =
        ontJson.decodeFromString(DtoInline.serializer(), texte).versDomaine()

    @Test
    fun `une reference vers un livre non traduit se decode et n'a pas de cible`() {
        val n = noeud(
            """{"t":"reference","v":"*Ésaïe* 7:14","livre":"Ésaïe","systeme":"recu",""" +
                """"chapitre":7,"portee":{"t":"verset","n":14}}""",
        )
        val reference = n as Inline.Reference
        // La clé est **absente**, pas nulle : c'est l'état ordinaire du corpus,
        // et l'exiger ferait lever le décodeur sur 208 nœuds.
        assertNull(reference.cible)
        // Elle garde tout de même de quoi se rendre et se nommer — c'est ce qui
        // permet au message de dire *quel* livre manque.
        assertEquals("Ésaïe", reference.livre)
        assertEquals("*Ésaïe* 7:14", reference.value)
    }

    @Test
    fun `une reference resolue porte son unite et son verset`() {
        val n = noeud(
            """{"t":"reference","v":"*Genèse* 7:11","livre":"Genèse","systeme":"recu",""" +
                """"chapitre":7,"portee":{"t":"verset","n":11},""" +
                """"cible":{"livre":"bereshit","unite":"bereshit-7","verset":4}}""",
        )
        assertEquals(
            CibleDeLaReference(livre = "bereshit", unite = "bereshit-7", verset = 4),
            (n as Inline.Reference).cible,
        )
    }

    /**
     * **Le nom du livre dit la numérotation**, et les deux systèmes ne se
     * résolvent pas pareil : « Genèse 7:11 » demande la table des plages,
     * « *Bereshit* 17 » nomme l'unité elle-même. La liseuse n'arbitre pas —
     * elle lit `systeme` et suit la `cible` que le pipeline a posée.
     */
    @Test
    fun `une reference au systeme ONT vise l'unite entiere sans verset`() {
        val n = noeud(
            """{"t":"reference","v":"*Bereshit* 17","livre":"Bereshit","systeme":"ont",""" +
                """"chapitre":17,"portee":{"t":"chapitre"},""" +
                """"cible":{"livre":"bereshit","unite":"bereshit-17"}}""",
        )
        val reference = n as Inline.Reference
        assertEquals("ont", reference.systeme)
        assertEquals(PorteeDeLaReference.Chapitre, reference.portee)
        // Aucun verset à rejoindre : on ouvre l'unité et on s'arrête là. Mieux
        // vaut la bonne unité sans rien viser qu'un verset faux.
        assertNull(reference.cible?.verset)
    }

    @Test
    fun `une plage traverse ses deux bornes`() {
        val n = noeud(
            """{"t":"reference","v":"*Genèse* 1:11-12","livre":"Genèse","systeme":"recu",""" +
                """"chapitre":1,"portee":{"t":"plage","premier":11,"dernier":12}}""",
        )
        assertEquals(
            PorteeDeLaReference.Plage(premier = 11, dernier = 12),
            (n as Inline.Reference).portee,
        )
    }

    /**
     * **La référence est du corps de texte.** « comme en *Genèse* 4:25 » perd
     * son sens si le syntagme disparaît d'un extrait de recherche ou d'une
     * carte de partage — au contraire de l'appareil critique, qu'on retire sans
     * rien perdre à la phrase.
     */
    @Test
    fun `le texte nu garde la reference`() {
        val n = noeud(
            """{"t":"reference","v":"*Genèse* 4:25","livre":"Genèse","systeme":"recu",""" +
                """"chapitre":4,"portee":{"t":"verset","n":25}}""",
        )
        assertEquals(
            "comme en *Genèse* 4:25",
            listOf(Inline.Text("comme en "), n).plainText(),
        )
    }
}
