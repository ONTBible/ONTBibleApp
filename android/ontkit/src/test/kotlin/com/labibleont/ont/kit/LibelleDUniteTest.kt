package com.labibleont.ont.kit

import com.labibleont.ont.kit.corpus.ChapterStub
import com.labibleont.ont.kit.corpus.LibelleDUnite
import com.labibleont.ont.kit.corpus.Status
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Le registre décide du mot, et le mot ne vit qu'à un endroit.
 *
 * ## Ce que ce fichier garde
 *
 * Android n'avait pas ce calcul. Pas « recopié dans trois vues » comme iOS
 * l'avait été — **pas du tout** : le réglage du français reçu annonçait
 * « Parashah 7 » dans son propre texte d'aide, et aucun écran ne le produisait.
 * Le sélecteur affichait « Bereshit 2 » dans les deux registres, la barre de
 * lecture ne disait que « Bereshit », et la sortie courte du sélecteur
 * proposait « Toute l'unité » — un troisième mot, hors des deux registres.
 *
 * Une déclaration sans la chose : le même défaut que la fiche du Play Store,
 * qui annonçait la mise à jour du corpus avant qu'Android sache la faire.
 *
 * ## Les cas viennent d'iOS
 *
 * Ceux de `RegistreDesUnitesTests`, portés un pour un. C'est délibéré : deux
 * plateformes qui éprouvent la même règle avec des cas différents finissent par
 * diverger sur ce qu'aucune des deux ne mesure.
 */
class LibelleDUniteTest {

    private fun unite(n: Int, titre: String = "Bereshit 2") = ChapterStub(
        id = "bereshit-2",
        n = n,
        title = titre,
        status = Status.LOCKED,
        verseCount = 21,
        reference = "2:4-25",
    )

    @Test
    fun `le registre decide du mot, pas la vue`() {
        assertEquals("Chapitre 2", unite(2).label(francaisRecu = true))
        assertEquals("Parashah 2", unite(2).label(francaisRecu = false))
    }

    /**
     * Une introduction n'a pas de rang : elle garde son titre. Sans ce cas, le
     * sélecteur annoncerait « Chapitre 0 ».
     */
    @Test
    fun `une introduction garde son titre dans les deux registres`() {
        val intro = unite(0, titre = "TOLEDOT ADAM VE-CHAVAH")
        assertEquals("TOLEDOT ADAM VE-CHAVAH", intro.label(francaisRecu = true))
        assertEquals("TOLEDOT ADAM VE-CHAVAH", intro.label(francaisRecu = false))
    }

    /**
     * Le genre grammatical voyage avec le mot, sinon le point d'appel doit
     * l'accorder lui-même — et il l'oubliera.
     */
    @Test
    fun `le genre suit le mot`() {
        assertEquals("Tout le chapitre", LibelleDUnite.toutLe(francaisRecu = true))
        assertEquals("Toute la parashah", LibelleDUnite.toutLe(francaisRecu = false))
    }

    /**
     * **Le pluriel de *parashah* n'est pas français.**
     *
     * Il prend la marque hébraïque `-ot`, que le §2.5 du vault fixe. Écrire
     * « parashahs » franciserait un intraduisible — exactement ce que le
     * réglage cherche à défaire. C'est le genre de détail qu'un point d'appel
     * pressé règle avec un `+ "s"`.
     */
    @Test
    fun `le pluriel garde la marque hebraique`() {
        assertEquals("chapitres", LibelleDUnite.noms(francaisRecu = true))
        assertEquals("parashiot", LibelleDUnite.noms(francaisRecu = false))
        assertEquals("parashah", LibelleDUnite.nom(francaisRecu = false))
        assertEquals("chapitre", LibelleDUnite.nom(francaisRecu = true))
    }

    /**
     * Le livre **et** le rang, pour le seul écran qui n'a pas d'autre repère.
     */
    @Test
    fun `la barre situe autant qu'elle nomme`() {
        assertEquals(
            "Bereshit · Chapitre 6",
            LibelleDUnite.situe("Bereshit", 6, francaisRecu = true),
        )
        assertEquals(
            "Bereshit · Parashah 6",
            LibelleDUnite.situe("Bereshit", 6, francaisRecu = false),
        )
    }

    /**
     * Le séparateur est un point médian entouré d'espaces insécables — non un
     * tiret, non un deux-points.
     *
     * Il vient d'iOS, et le mesurer ici est la seule façon de garder les deux
     * barres identiques : un tiret passerait la revue humaine des deux côtés
     * sans que personne remarque qu'elles ne disent plus la même chose.
     */
    @Test
    fun `le separateur est celui d'iOS`() {
        assertEquals(
            "Bereshit · Chapitre 6",
            LibelleDUnite.situe("Bereshit", 6, francaisRecu = true),
        )
    }
}
