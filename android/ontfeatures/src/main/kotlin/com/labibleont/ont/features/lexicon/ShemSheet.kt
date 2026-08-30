package com.labibleont.ont.features.lexicon

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.labibleont.ont.designsystem.metrics.ontSpacing
import com.labibleont.ont.designsystem.text.ONTTextRenderer
import com.labibleont.ont.designsystem.theme.LocalReadingTheme
import com.labibleont.ont.designsystem.tokens.ONTColors
import com.labibleont.ont.designsystem.typography.ONTFonts
import com.labibleont.ont.designsystem.typography.ONTProse
import com.labibleont.ont.designsystem.typography.ONTTypography
import com.labibleont.ont.kit.corpus.Block
import com.labibleont.ont.kit.corpus.ShemEntry
import com.labibleont.ont.kit.reader.ReadingPreferences

/**
 * La fiche d'un **Shem** — un porteur de nom.
 *
 * ## Pourquoi ce n'est pas [TermSheet]
 *
 * Une fiche d'intraduisible dit un **concept** : un champ sémantique, une
 * traduction fixée, les endroits où le mot paraît. Une fiche de Shem dit un
 * **porteur** : le sens de la racine, ce que le nom met sur les épaules de qui
 * le porte, et ce qui reste à venir.
 *
 * Les deux se lisent donc autrement. Celle-ci n'a ni compteur d'occurrences ni
 * traduction — un nom ne se traduit pas — et elle porte des **titres de
 * section**, que les fiches de concepts n'ont pas : 197 des 305 fiches en
 * comptent, avec quatre à six mouvements.
 *
 * Les rendre visibles est tout l'objet de cette feuille. Sans eux, six
 * mouvements arrivent en un seul bloc et le « Voir aussi » se colle au reste.
 */
@Composable
public fun ShemSheet(
    entree: ShemEntry,
    preferences: ReadingPreferences,
    modifier: Modifier = Modifier,
) {
    val theme = LocalReadingTheme.current
    val typo = ONTTypography(preferences.textSize.toFloat(), theme, preferences.bodyFont)
    val espace = ontSpacing
    val interligne =
        (preferences.textSize * com.labibleont.ont.designsystem.typography.interligne(
            preferences.lineSpacing,
        )).sp

    Column(
        modifier = modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = espace.page, vertical = espace.m),
    ) {
        // Le nom, dans sa terre brûlée. C'est la seule couleur de la feuille :
        // le corps de la fiche est de l'encre ordinaire, parce qu'il parle du
        // porteur et non du nom.
        Text(
            entree.title,
            fontFamily = ONTFonts.display,
            fontSize = (preferences.textSize * 1.5f).sp,
            fontWeight = FontWeight.SemiBold,
            color = ONTColors.shem(theme),
            modifier = Modifier.semantics { heading() },
        )
        Spacer(Modifier.height(espace.m))

        for (bloc in entree.definition) {
            when (bloc) {
                is Block.Heading -> {
                    Spacer(Modifier.height(espace.m))
                    Text(
                        ONTTextRenderer.compose(
                            bloc.nodes,
                            typo,
                            showGloss = preferences.showGloss,
                            showLevel3 = preferences.showLevel3,
                        ),
                        fontFamily = ONTFonts.display,
                        // Un seul corps pour tous les niveaux de titre. Les
                        // fiches n'en emploient que deux, et les distinguer
                        // typographiquement demanderait au lecteur de tenir une
                        // hiérarchie qu'aucune fiche ne fait sentir.
                        fontSize = (preferences.textSize * 1.1f).sp,
                        fontWeight = FontWeight.SemiBold,
                        color = ONTColors.ink(theme),
                        // Le lecteur d'écran doit pouvoir sauter de mouvement en
                        // mouvement : c'est à ça que servent des titres.
                        modifier = Modifier.semantics { heading() },
                    )
                    Spacer(Modifier.height(espace.xs))
                }

                is Block.Paragraph -> {
                    Text(
                        ONTTextRenderer.compose(
                            bloc.nodes,
                            typo,
                            showGloss = preferences.showGloss,
                            showLevel3 = preferences.showLevel3,
                        ),
                        style = ONTProse.francaise.copy(lineHeight = interligne),
                    )
                    Spacer(Modifier.height(espace.s))
                }

                // Une fiche ne porte que des titres et des paragraphes. Le reste
                // du schéma existe pour le corpus, pas pour elle — et l'ignorer
                // en silence vaut mieux que de rendre au hasard une forme qu'on
                // n'a jamais vue ici.
                else -> Unit
            }
        }
        Spacer(Modifier.height(espace(48)))
    }
}
