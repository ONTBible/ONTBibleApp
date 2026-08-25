package com.labibleont.ont.features.reading

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.labibleont.ont.designsystem.theme.LocalReadingTheme
import com.labibleont.ont.designsystem.tokens.ONTColors
import com.labibleont.ont.kit.reader.HighlightColor

/**
 * Ce qui paraît quand le lecteur désigne des versets.
 *
 * ## Cinq pastilles, et rien d'autre
 *
 * Le geste courant est « je marque ce passage ». Il doit tenir en un appui, pas
 * en un appui puis un menu. Les cinq teintes sont donc posées à plat — c'est
 * aussi ce qui rend visible qu'il y en a exactement cinq, et pas une palette
 * ouverte où l'on ne retrouverait plus la couleur employée la semaine passée.
 *
 * Le renvoi — « Bereshit 1:1-3, 7 » — est affiché au-dessus. Il dit ce qui est
 * désigné sans qu'on ait à recompter les lignes surlignées, et c'est exactement
 * ce que le partage enverra.
 */
@Composable
public fun SelectionBar(
    renvoi: String,
    dejaMarquee: Boolean,
    onCouleur: (HighlightColor) -> Unit,
    onEffacer: () -> Unit,
    onPartager: () -> Unit,
    onFermer: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val theme = LocalReadingTheme.current

    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(ONTColors.surface(theme)),
    ) {
        HorizontalDivider(color = ONTColors.separator(theme))

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 20.dp, end = 8.dp, top = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                renvoi,
                color = ONTColors.brandInk(theme),
                fontSize = 15.sp,
                modifier = Modifier.weight(1f),
            )
            IconButton(onClick = onPartager) {
                Icon(
                    Icons.Filled.Share,
                    contentDescription = "Partager le passage",
                    tint = ONTColors.brandInk(theme),
                )
            }
            IconButton(onClick = onFermer) {
                Icon(
                    Icons.Filled.Close,
                    contentDescription = "Ne plus rien désigner",
                    tint = ONTColors.inkSoft(theme),
                )
            }
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            for (couleur in HighlightColor.entries) {
                Pastille(couleur = couleur, onClick = { onCouleur(couleur) })
            }

            // « Effacer » n'apparaît que s'il y a quelque chose à effacer :
            // proposer d'annuler ce qui n'existe pas fait douter d'avoir marqué.
            if (dejaMarquee) {
                Text(
                    "Effacer",
                    color = ONTColors.inkSoft(theme),
                    fontSize = 14.sp,
                    modifier = Modifier
                        .clickable(onClick = onEffacer)
                        .padding(horizontal = 6.dp, vertical = 4.dp),
                )
            }
        }
    }
}

@Composable
private fun Pastille(couleur: HighlightColor, onClick: () -> Unit) {
    val theme = LocalReadingTheme.current
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.clickable(onClick = onClick),
    ) {
        Row(
            modifier = Modifier
                .size(34.dp)
                .clip(CircleShape)
                .background(
                    // La même opacité qu'à la lecture : la pastille montre ce
                    // que le verset aura, pas une version plus vive qui
                    // décevrait au moment de la poser.
                    ONTColors.highlight(couleur).copy(alpha = ONTColors.HIGHLIGHT_OPACITY),
                )
                .border(1.dp, ONTColors.separator(theme), CircleShape),
        ) {}
        Text(
            couleur.label,
            fontSize = 10.sp,
            color = ONTColors.inkSoft(theme),
            modifier = Modifier.padding(top = 2.dp),
        )
    }
}
