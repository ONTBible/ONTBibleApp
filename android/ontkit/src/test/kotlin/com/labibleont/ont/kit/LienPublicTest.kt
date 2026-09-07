package com.labibleont.ont.kit

import com.labibleont.ont.kit.reader.LienPublic
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Le lien public d'un passage.
 *
 * La forme du paramètre `?v=` est éprouvée contre ce que le site accepte et ce
 * que sa propre écriture produit — mesuré en production le 29 août 2026 :
 * `{7,2,1,3,7}` y donne `?v=1-3,7`, **sans espace**.
 */
class LienPublicTest {

    @Test
    fun `une unite sans selection n'a pas de parametre`() {
        assertEquals(
            "https://ontbible.com/fr/lire/bereshit/bereshit-1",
            LienPublic.passage("bereshit", "bereshit-1"),
        )
    }

    @Test
    fun `les versets designes passent en parametre, sans espace`() {
        // `VerseRange.label` joint avec « , » — espace comprise, parce que c'est
        // la typographie française d'un renvoi. Une URL n'en veut pas : elle la
        // ferait percent-encoder, et la même sélection produirait deux chaînes
        // différentes selon qui la fabrique.
        assertEquals(
            "https://ontbible.com/fr/lire/bereshit/bereshit-1?v=1-3,7",
            LienPublic.passage("bereshit", "bereshit-1", setOf(1, 2, 3, 7)),
        )
    }

    @Test
    fun `le desordre et les doublons donnent le meme lien`() {
        // Deux personnes qui désignent le même passage doivent produire la même
        // adresse, sans quoi on obtient deux entrées de cache et deux aperçus
        // pour une seule chose.
        assertEquals(
            LienPublic.passage("bereshit", "bereshit-1", setOf(1, 2, 3, 7)),
            LienPublic.passage("bereshit", "bereshit-1", setOf(7, 2, 1, 3)),
        )
    }

    @Test
    fun `un verset seul ne devient pas une plage`() {
        assertEquals(
            "https://ontbible.com/fr/lire/bereshit/bereshit-1?v=6",
            LienPublic.passage("bereshit", "bereshit-1", setOf(6)),
        )
    }

    @Test
    fun `le domaine est ontbible point com, jamais celui qui redirige`() {
        // `labibleont.com` redirige vers `ontbible.com`. Partager l'adresse de
        // redirection ferait un saut de plus pour le destinataire, et un aperçu
        // que le moteur pourrait ne pas suivre.
        val lien = LienPublic.passage("bereshit", "bereshit-1")
        assert(lien.startsWith("https://ontbible.com/")) { "domaine inattendu : $lien" }
    }
}
