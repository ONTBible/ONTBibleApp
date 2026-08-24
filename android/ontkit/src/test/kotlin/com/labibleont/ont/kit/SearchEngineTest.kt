package com.labibleont.ont.kit

import com.labibleont.ont.kit.search.SearchEngine
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Le pliage doit être **identique** à celui du pipeline.
 *
 * Sinon l'index et la requête ne se rencontrent jamais, et la recherche ne rend
 * rien sans que rien ne signale d'erreur — le pire des défauts, parce qu'il
 * ressemble à « ce mot n'est pas dans le corpus ».
 *
 * Les attentes ci-dessous ne sont pas devinées : elles ont été produites par
 * `ont::search::fold` et `ont::search::strip_hebrew` eux-mêmes, sur ces
 * entrées-là. Si le pipeline change son pliage, ces tests tombent — c'est
 * exactement ce qu'on veut, puisque l'index changerait aussi.
 */
class SearchEngineTest {

    @Test
    fun `le pliage latin suit celui du pipeline`() {
        assertEquals("elohim", SearchEngine.fold("Élohîm"))
        assertEquals("l'etre faconne", SearchEngine.fold("L'ÊTRE  façonné"))
        assertEquals("espaces multiples", SearchEngine.fold("  ESPACES   multiples  "))
    }

    @Test
    fun `l'apostrophe courbe devient droite`() {
        // Le vault écrit « chesed’s » avec l'apostrophe typographique, un
        // lecteur tape la droite. Sans cette normalisation, il ne trouve rien.
        assertEquals("chesed's", SearchEngine.fold("chesed’s"))
        assertEquals("chesed's", SearchEngine.fold("chesedʼs"))
    }

    @Test
    fun `l'hebreu se denude de son niqqud`() {
        // C'est ce qui permet de taper au clavier hébreu ordinaire — sans
        // voyelles — et de rencontrer un texte intégralement vocalisé.
        assertEquals("חסד", SearchEngine.stripHebrew("חֶסֶד"))
        assertEquals("בראשית", SearchEngine.stripHebrew("בְּרֵאשִׁ֖ית"))
    }

    @Test
    fun `le maqaf disparait comme dans le pipeline`() {
        // Le maqaf joint deux mots sans espace, et le pipeline le retire sans
        // en poser un. On fait pareil : ce qui compte n'est pas que ce soit
        // joli, c'est que les deux côtés produisent la même chaîne.
        assertEquals("אלהיםיהוה", SearchEngine.stripHebrew("אֱלֹהִ֑ים־יְהוָה"))
    }

    @Test
    fun `on reconnait une saisie en hebreu`() {
        assertTrue(SearchEngine.isHebrew("חסד"))
        assertFalse(SearchEngine.isHebrew("chesed"))
    }
}
