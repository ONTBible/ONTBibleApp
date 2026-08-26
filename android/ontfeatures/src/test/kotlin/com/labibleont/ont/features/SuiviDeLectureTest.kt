package com.labibleont.ont.features

import com.labibleont.ont.features.reading.SuiviDeLecture
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Le suivi de lecture — ce qui décide du verset où l'on reprend.
 *
 * Les trois défauts qu'on a réellement rencontrés ont chacun leur test : la
 * garde d'ouverture, les bornes qui restent figées dans la fenêtre quand un
 * verset quitte l'écran, et le verset à peine entamé qu'on retenait au lieu de
 * celui qu'on lit.
 */
class SuiviDeLectureTest {

    /** Une fenêtre de mille points, comme un écran. */
    private val haut = 0f
    private val bas = 1000f

    @Test
    fun `sans defilement, rien n'est retenu`() {
        val suivi = SuiviDeLecture()
        suivi.situer(4, 100f, 300f)

        // Ouvrir une unité, la lire sans bouger et la quitter ne doit pas
        // déplacer la reprise : elle reste où la restauration l'avait posée.
        assertNull(suivi.aRetenir(haut, bas))
    }

    @Test
    fun `apres defilement, le plus petit verset a moitie visible est retenu`() {
        val suivi = SuiviDeLecture()
        suivi.defile()
        suivi.situer(7, 200f, 400f)
        suivi.situer(8, 400f, 700f)

        assertEquals(7, suivi.aRetenir(haut, bas)?.toInt())
    }

    @Test
    fun `un verset a peine entame n'est pas celui qu'on lit`() {
        val suivi = SuiviDeLecture()
        suivi.defile()
        // Le 11 dépasse du bord haut et n'en montre qu'un cinquième : c'est
        // celui qu'on vient de quitter, pas celui qu'on lit.
        suivi.situer(11, -800f, 200f)
        suivi.situer(12, 200f, 900f)

        assertEquals(12, suivi.aRetenir(haut, bas)?.toInt())
    }

    @Test
    fun `la moitie pile suffit`() {
        val suivi = SuiviDeLecture()
        suivi.defile()
        suivi.situer(3, -100f, 100f)

        assertEquals(3, suivi.aRetenir(haut, bas)?.toInt())
    }

    @Test
    fun `un verset oublie ne gagne plus`() {
        val suivi = SuiviDeLecture()
        suivi.defile()
        suivi.situer(1, 0f, 500f)
        suivi.situer(9, 100f, 800f)
        assertEquals(1, suivi.aRetenir(haut, bas)?.toInt())

        // Le 1 quitte l'écran : la liste met son bloc au rebut. Sans cet oubli
        // ses bornes resteraient figées **dans** la fenêtre, et comme on retient
        // le plus petit numéro, il gagnerait à jamais.
        suivi.oublier(listOf(1))

        assertEquals(9, suivi.aRetenir(haut, bas)?.toInt())
    }

    @Test
    fun `changer d'unite remet la garde`() {
        val suivi = SuiviDeLecture()
        suivi.defile()
        suivi.situer(5, 100f, 400f)
        assertEquals(5, suivi.aRetenir(haut, bas)?.toInt())

        suivi.recommence()

        assertNull(suivi.aRetenir(haut, bas))
    }

    @Test
    fun `un verset entierement hors champ ne compte pas`() {
        val suivi = SuiviDeLecture()
        suivi.defile()
        suivi.situer(2, -3000f, -2000f)
        suivi.situer(6, 300f, 600f)

        assertEquals(6, suivi.aRetenir(haut, bas)?.toInt())
    }

    @Test
    fun `une borne vide est ecartee`() {
        val suivi = SuiviDeLecture()
        suivi.defile()
        // Une mise en page pas encore faite rend une hauteur nulle : elle ne
        // doit ni gagner ni faire tomber le calcul.
        suivi.situer(1, 500f, 500f)
        suivi.situer(4, 200f, 500f)

        assertEquals(4, suivi.aRetenir(haut, bas)?.toInt())
    }
}
