package com.labibleont.ont.data

import com.labibleont.ont.data.store.PreferencesFichier
import com.labibleont.ont.data.store.versDomaine
import com.labibleont.ont.data.store.versFichier
import com.labibleont.ont.kit.reader.ReadingPreferences
import kotlin.reflect.full.primaryConstructor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `PreferencesFichier` est écrit **à la main**, et rien ne le tient à jour.
 *
 * Le 25 août 2026, « Le français reçu » est arrivé dans [ReadingPreferences] et
 * pas ici : le réglage se laissait basculer, l'écran suivait, et il disparaissait
 * à la fermeture. Le champ ne s'écrivait nulle part. Aucun test ne l'a vu, parce
 * qu'aucun ne regardait ce DTO.
 *
 * C'est la même faute que celle qui a cassé le site le même jour : un type écrit
 * à la main qui doit suivre un contrat qu'il ne surveille pas.
 */
class PreferencesFichierTest {

    /** Ce qui part doit revenir — sur des valeurs toutes différentes du défaut. */
    @Test
    fun `le tour complet conserve chaque réglage`() {
        val depart = ReadingPreferences(
            showGloss = false,
            showLevel3 = false,
            textSize = 27.0,
            lineSpacing = 0.8,
            continuous = false,
            french = false,
        )
        assertEquals(depart, depart.versFichier().versDomaine())
    }

    /**
     * La garde qui vaut pour **les champs à venir**, pas seulement pour ceux
     * d'aujourd'hui : un réglage ajouté au domaine sans l'être ici fait rougir ce
     * test sans que personne ait à y penser.
     *
     * `daily` est l'exception assumée — il est mis à plat en trois entiers, et
     * c'est délibéré : le fichier est déjà le corps de la future requête de
     * synchronisation, où un objet imbriqué coûterait plus qu'il ne rapporte.
     */
    @Test
    fun `chaque réglage du domaine a sa contrepartie dans le fichier`() {
        // Le **constructeur primaire**, et pas les propriétés : `isDisplayDefault`
        // est calculée à partir des autres, elle n'a rien à enregistrer.
        val aPlat = setOf("daily")
        val fichier = PreferencesFichier::class.primaryConstructor!!
            .parameters.mapNotNull { it.name }.toSet()
        val manquants = ReadingPreferences::class.primaryConstructor!!
            .parameters.mapNotNull { it.name }
            .filterNot { it in aPlat || it in fichier }
        assertTrue(
            "Réglages absents de PreferencesFichier : $manquants — " +
                "ils se basculeront à l'écran et disparaîtront à la fermeture.",
            manquants.isEmpty(),
        )
    }
}
