package com.labibleont.ont.features.reading

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.labibleont.ont.designsystem.metrics.ontSpacing
import com.labibleont.ont.designsystem.surfaces.QuietBlock
import com.labibleont.ont.designsystem.surfaces.SectionCaption
import com.labibleont.ont.designsystem.text.ONTTextRenderer
import com.labibleont.ont.designsystem.theme.LocalReadingTheme
import com.labibleont.ont.designsystem.tokens.ONTColors
import com.labibleont.ont.designsystem.typography.ONTTypography
import com.labibleont.ont.features.you.ReadingSettings
import com.labibleont.ont.kit.corpus.Block
import com.labibleont.ont.kit.corpus.Chapter
import com.labibleont.ont.kit.corpus.Verse
import com.labibleont.ont.kit.reader.ReadingPreferences

/**
 * Les réglages de lecture, atteignables **pendant** la lecture.
 *
 * ## Pourquoi ils ne vivent pas seulement dans l'onglet Vous
 *
 * On règle la taille du texte quand on bute dessus, pas quand on y pense.
 * Obliger à quitter le chapitre, traverser trois écrans et revenir, c'est
 * garantir que personne ne touchera jamais ces réglages — et pour un lectorat
 * qui monte le curseur parce qu'il ne voit pas autrement, c'est un défaut
 * d'accessibilité déguisé en question de navigation.
 *
 * ## L'aperçu vivant
 *
 * Les deux premiers versets du chapitre ouvert, composés avec les réglages **en
 * cours de modification**. Bouger la taille, changer de fonte ou éteindre les
 * gloses se voit ici, sur le texte réel, sans refermer la feuille.
 *
 * Un échantillon inventé ne dirait rien : c'est la cohabitation des trois
 * niveaux qui décide si un réglage tient. Deux versets suffisent à les faire
 * paraître tous les trois.
 *
 * Et l'aperçu emprunte les **deux** chemins de rendu — prose continue et
 * blocs — parce que « Versets à la suite » est le réglage qui change le plus la
 * page. C'était le seul que l'aperçu d'iOS taisait au début : on basculait à
 * l'aveugle, on refermait pour voir.
 */
@Composable
public fun ReadingSettingsSheet(
    chapitre: Chapter?,
    preferences: ReadingPreferences,
    onChange: (ReadingPreferences) -> Unit,
    modifier: Modifier = Modifier,
) {
    val espace = ontSpacing

    Column(modifier = modifier.fillMaxWidth().verticalScroll(rememberScrollState())) {
        chapitre?.let { Apercu(it, preferences) }
        Spacer(Modifier.height(espace.m))
        // La feuille porte le défilement ; les réglages ne doivent pas
        // en porter un second.
        ReadingSettings(
            preferences = preferences,
            onChange = onChange,
            defilant = false,
        )
    }
}

@Composable
private fun Apercu(chapitre: Chapter, preferences: ReadingPreferences) {
    val theme = LocalReadingTheme.current
    val espace = ontSpacing
    val typo = ONTTypography(preferences.textSize.toFloat(), theme, preferences.bodyFont)

    /*
     * Les deux premiers versets, et rien de plus : ils suffisent à faire
     * paraître les trois niveaux, et l'aperçu doit tenir dans une feuille sans
     * avaler les réglages.
     */
    val versets: kotlin.collections.List<Verse> = chapitre.blocks
        .filterIsInstance<Block.Verses>()
        .flatMap { it.verses }
        .take(2)

    if (versets.isEmpty()) return

    Column(modifier = Modifier.padding(horizontal = espace.l)) {
        SectionCaption("Aperçu — ${chapitre.title}")
        QuietBlock(
            // Borné en hauteur, mais il défile en lui-même : sans ça, la fin du
            // second verset serait coupée — et c'est souvent la fin d'une glose
            // qui départage deux fontes.
            modifier = Modifier.heightIn(max = 220.dp),
        ) {
            Column(modifier = Modifier.verticalScroll(rememberScrollState())) {
                val interligne = (1f + preferences.lineSpacing.toFloat()).em
                if (preferences.continuous) {
                    Text(
                        androidx.compose.ui.text.buildAnnotatedString {
                            for (v in versets) {
                                append(
                                    ONTTextRenderer.composeVerse(
                                        v, typo,
                                        showGloss = preferences.showGloss,
                                        showLevel3 = preferences.showLevel3,
                                    ),
                                )
                                append(" ")
                            }
                        },
                        style = androidx.compose.ui.text.TextStyle(lineHeight = interligne),
                    )
                } else {
                    for (v in versets) {
                        Text(
                            ONTTextRenderer.composeVerse(
                                v, typo,
                                showGloss = preferences.showGloss,
                                showLevel3 = preferences.showLevel3,
                            ),
                            style = androidx.compose.ui.text.TextStyle(lineHeight = interligne),
                            modifier = Modifier.padding(bottom = espace.s),
                        )
                    }
                }
            }
        }
    }
}
