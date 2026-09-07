package com.labibleont.ont.kit

import com.labibleont.ont.kit.account.Fournisseur
import com.labibleont.ont.kit.account.RetourDAutorisation
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * L'adresse de retour vient du dehors, et on la malmène en conséquence.
 *
 * Sur Android, **une autre app peut déclarer `ont://`** et nous envoyer ce
 * qu'elle veut. Aucune de ces entrées ne doit lever, et aucune ne doit être
 * confondue avec un succès.
 */
class RetourDAutorisationTest {

    @Test
    fun `un retour accorde rend le fournisseur et le code`() {
        val lu = RetourDAutorisation.lire("ont://auth/callback?provider=github&code=abc123")
        assertEquals(RetourDAutorisation.Accorde(Fournisseur.GITHUB, "abc123"), lu)
    }

    /**
     * `null` dit « ce n'est pas pour moi », pas « c'est mal formé ». L'app
     * reçoit des liens de lecture par le même canal : les confondre ferait
     * avaler un renvoi biblique par le flux de connexion.
     */
    @Test
    fun `un lien de lecture n'est pas un retour d'autorisation`() {
        assertNull(RetourDAutorisation.lire("ont://read/bereshit/bereshit-1?v=3"))
        assertNull(RetourDAutorisation.lire("https://ontbible.com/fr/lire/bereshit/bereshit-1"))
        assertNull(RetourDAutorisation.lire(null))
        assertNull(RetourDAutorisation.lire(""))
    }

    @Test
    fun `une erreur du fournisseur est un refus`() {
        assertEquals(
            RetourDAutorisation.Refuse,
            RetourDAutorisation.lire("ont://auth/callback?error=access_denied"),
        )
    }

    /**
     * **L'ordre de lecture compte.** Une adresse qui porte une erreur *et* un
     * code est un refus : tenter l'échange sur un code que le fournisseur a
     * déjà décliné ferait une requête pour rien, et son échec parlerait
     * d'autre chose.
     */
    @Test
    fun `une erreur l'emporte sur un code present`() {
        assertEquals(
            RetourDAutorisation.Refuse,
            RetourDAutorisation.lire("ont://auth/callback?provider=google&code=x&error=access_denied"),
        )
    }

    @Test
    fun `un fournisseur inconnu est un refus, pas une exception`() {
        assertEquals(
            RetourDAutorisation.Refuse,
            RetourDAutorisation.lire("ont://auth/callback?provider=facebook&code=x"),
        )
    }

    @Test
    fun `un code vide est un refus`() {
        assertEquals(
            RetourDAutorisation.Refuse,
            RetourDAutorisation.lire("ont://auth/callback?provider=google&code="),
        )
        assertEquals(
            RetourDAutorisation.Refuse,
            RetourDAutorisation.lire("ont://auth/callback?provider=google"),
        )
    }

    @Test
    fun `le code est decode, pourcentages et plus compris`() {
        val lu = RetourDAutorisation.lire("ont://auth/callback?provider=google&code=a%2Fb+c")
        assertEquals(RetourDAutorisation.Accorde(Fournisseur.GOOGLE, "a/b c"), lu)
    }

    /** Rien de tout cela ne doit lever. */
    @Test
    fun `les formes tordues ne levent pas`() {
        for (cas in listOf(
            "ont://auth/callback",
            "ont://auth/callback?",
            "ont://auth/callback?&&&",
            "ont://auth/callback?=x",
            "ont://auth/callback?provider=google&code=%",
            "ont://auth/callback?provider=google&code=%zz",
        )) {
            RetourDAutorisation.lire(cas)
        }
    }
}
