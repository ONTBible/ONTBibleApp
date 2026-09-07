package com.labibleont.ont.kit

import com.labibleont.ont.kit.account.Pkce
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.security.SecureRandom

/**
 * PKCE, éprouvé contre le vecteur publié plutôt que contre lui-même.
 *
 * Un test qui recalculerait le défi avec le même code que la production
 * passerait quelle que soit l'erreur : il mesurerait la cohérence, pas la
 * justesse. La RFC 7636 publie un couple en annexe B — c'est lui qui dit si
 * notre encodage est le bon.
 */
class PkceTest {

    /** RFC 7636, annexe B. */
    private val verificateurDeLaRfc = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    private val defiDeLaRfc = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"

    @Test
    fun `le defi est celui que la RFC publie`() {
        assertEquals(defiDeLaRfc, Pkce.defiPour(verificateurDeLaRfc))
    }

    /**
     * Les trois conditions de l'encodage, séparément.
     *
     * Un `+`, un `/` ou un `=` ne se voient pas dans le cas nominal — ils
     * n'apparaissent que sur certains tirages. Le défaut serait donc
     * intermittent, et l'erreur rendue par le fournisseur dirait seulement
     * « invalid_grant ».
     */
    @Test
    fun `l'encodage est URL-safe et sans remplissage, sur mille tirages`() {
        val alea = SecureRandom()
        repeat(1_000) {
            val pkce = Pkce.tirer(alea)
            for (valeur in listOf(pkce.verificateur, pkce.defi)) {
                assertFalse("« + » interdit : $valeur", valeur.contains('+'))
                assertFalse("« / » interdit : $valeur", valeur.contains('/'))
                assertFalse("« = » interdit : $valeur", valeur.contains('='))
            }
        }
    }

    /**
     * La RFC borne le vérificateur entre 43 et 128 signes. Trente-deux octets
     * en base64 sans remplissage en font quarante-trois — le minimum, et c'est
     * délibéré : plus long ne renforce rien et allonge chaque URL.
     */
    @Test
    fun `le verificateur tient dans les bornes de la RFC`() {
        val v = Pkce.tirer().verificateur
        assertTrue("longueur ${v.length}", v.length in 43..128)
    }

    @Test
    fun `deux tirages ne se ressemblent pas`() {
        assertNotEquals(Pkce.tirer().verificateur, Pkce.tirer().verificateur)
    }

    @Test
    fun `le defi n'est pas le verificateur`() {
        val pkce = Pkce.tirer()
        assertNotEquals(pkce.verificateur, pkce.defi)
    }
}
