package com.labibleont.ont.kit

import com.labibleont.ont.kit.reader.DailySelection
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DailySelectionTest {

    private val paris = ZoneId.of("Europe/Paris")
    private val depart = Instant.parse("2026-08-24T10:00:00Z")

    @Test
    fun `le meme jour donne le meme verset`() {
        // La propriété qui fait tenir tout le reste : l'app, le widget et la
        // notification calculent chacun de leur côté et doivent tomber juste.
        val matin = Instant.parse("2026-08-24T06:00:00Z")
        val soir = Instant.parse("2026-08-24T21:00:00Z")
        assertEquals(
            DailySelection.index(matin, 251, paris),
            DailySelection.index(soir, 251, paris),
        )
    }

    @Test
    fun `on visite tout le vivier avant d'en revoir un`() {
        // Une permutation, pas un tirage. La première version brassait le
        // numéro du jour : sur 251 versets, deux jours d'un même mois
        // tombaient sur le même avec quatre chances sur cinq.
        val taille = 251
        val vus = mutableSetOf<Int>()
        for (jour in 0 until taille) {
            vus.add(DailySelection.index(depart.plus(jour.toLong(), ChronoUnit.DAYS), taille, paris))
        }
        assertEquals("le cycle doit couvrir le vivier entier", taille, vus.size)
    }

    @Test
    fun `deux jours voisins sont eloignes dans le corpus`() {
        // Le pas vaut ~0,618 × la taille — le nombre d'or, qui écarte au
        // maximum deux positions consécutives.
        val taille = 251
        val a = DailySelection.index(depart, taille, paris)
        val b = DailySelection.index(depart.plus(1, ChronoUnit.DAYS), taille, paris)
        val ecart = minOf(Math.floorMod(a - b, taille), Math.floorMod(b - a, taille))
        assertTrue("deux jours voisins trop proches : $a puis $b", ecart > taille / 8)
    }

    @Test
    fun `un vivier d'un seul verset ne calcule rien`() {
        assertEquals(0, DailySelection.index(depart, 1, paris))
        assertEquals(0, DailySelection.index(depart, 0, paris))
    }

    @Test
    fun `le pas est premier avec la taille`() {
        // Sans quoi le cycle ne couvrirait qu'une partie du vivier.
        for (taille in 3..400) {
            val pas = DailySelection.step(taille)
            assertEquals("pas non premier avec $taille", 1, pgcd(pas, taille))
        }
    }

    @Test
    fun `le calcul suit minuit local, comme en Swift`() {
        // Swift prend minuit **local**, le convertit en secondes depuis 1970 et
        // tronque. À l'est de Greenwich, minuit local précède minuit UTC : la
        // troncature retire un jour, et `LocalDate.toEpochDay()` ne le ferait
        // pas. C'est ce décalage qui ferait diverger un iPhone et une tablette
        // Android du même lecteur — d'où la réplication exacte.
        //
        // Le 24 août 2026 à Paris : minuit local = 2026-08-23T22:00:00Z, soit
        // 20 688 jours et 22 heures. Tronqué : 20 688.
        val numeroAttendu = 20_688
        val taille = 100
        val position = ((numeroAttendu % taille) + taille) % taille
        val attendu = (position.toLong() * DailySelection.step(taille) % taille).toInt()

        val midi = Instant.parse("2026-08-24T12:00:00Z")
        assertEquals(attendu, DailySelection.index(midi, taille, paris))
    }

    private fun pgcd(a: Int, b: Int): Int {
        var x = a
        var y = b
        while (y != 0) {
            val t = y
            y = x % y
            x = t
        }
        return x
    }
}
