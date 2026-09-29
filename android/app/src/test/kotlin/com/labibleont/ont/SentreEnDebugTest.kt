package com.labibleont.ont

import com.labibleont.ont.observabilite.Observabilite
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Ce qu'un build de développement a le droit de remonter.
 *
 * ## Le défaut que ça ferme
 *
 * Un `./gradlew installDebug` alertait **comme la production**, au même projet
 * Sentry — et avec `tracesSampleRate = 1.0` contre `0.2` en release, donc cinq
 * fois plus de traces qu'une app entre les mains d'un lecteur.
 *
 * Relevé par la session iOS le 29 septembre 2026, après un courriel Sentry pour
 * un blocage de douze secondes qui ne venait d'aucun lecteur : c'était
 * l'appareil de l'auteur, sous un build posé par les scripts de lancement.
 *
 * ## Pourquoi ce test peut exister
 *
 * Parce que la décision a été extraite dans une fonction qui **prend son monde
 * en paramètre**. `BuildConfig.DEBUG` ne se pose pas depuis un test JVM : une
 * garde qui le lirait elle-même serait invérifiable, et c'est exactement ce qui
 * a laissé passer le défaut pendant trois semaines.
 */
class SentreEnDebugTest {

    /** Le cas du défaut : un build de développement se taisait-il ? Non. */
    @Test
    fun `un build de developpement ne remonte rien`() {
        assertFalse(
            "un installDebug alertait comme la production",
            Observabilite.doitRemonter(debug = true, sousTest = false, porteOuverte = false),
        )
    }

    /** Et la production continue de remonter — sinon on aurait tout éteint. */
    @Test
    fun `un build de livraison remonte`() {
        assertTrue(
            Observabilite.doitRemonter(debug = false, sousTest = false, porteOuverte = false),
        )
    }

    /**
     * La porte rouvre, et **seulement** en debug.
     *
     * Elle existe pour qu'une épreuve de bout en bout reste possible : couper
     * sans exception la rendrait inerte en silence — rien n'échouerait, le
     * tableau de bord resterait vide, et l'on chercherait le défaut dans la
     * chaîne de remontée plutôt que dans la coupure.
     */
    @Test
    fun `la porte rouvre la remontee en developpement`() {
        assertTrue(
            Observabilite.doitRemonter(debug = true, sousTest = false, porteOuverte = true),
        )
    }

    /**
     * Un test ne remonte jamais, porte ouverte ou non.
     *
     * Il polluerait le tableau de bord à chaque exécution de la CI, avec des
     * piles qui ne décrivent rien. Ce cas prime sur les deux autres, et le test
     * le fige : c'est l'ordre des branches du `when` qui le décide, et il ne se
     * voit pas à la relecture.
     */
    @Test
    fun `un test ne remonte jamais, meme porte ouverte`() {
        assertFalse(Observabilite.doitRemonter(debug = true, sousTest = true, porteOuverte = true))
        assertFalse(Observabilite.doitRemonter(debug = false, sousTest = true, porteOuverte = true))
    }
}
