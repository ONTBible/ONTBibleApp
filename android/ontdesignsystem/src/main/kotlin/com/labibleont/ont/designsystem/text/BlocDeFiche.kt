package com.labibleont.ont.designsystem.text

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.labibleont.ont.designsystem.theme.LocalReadingTheme
import com.labibleont.ont.designsystem.tokens.ONTColors
import com.labibleont.ont.designsystem.typography.ONTFonts
import com.labibleont.ont.designsystem.typography.ONTTypography
import com.labibleont.ont.kit.corpus.Block

/**
 * Un bloc de **prose de fiche** — lexique, Shem, prononciation.
 *
 * ## Le défaut que ça ferme
 *
 * Les trois écrans de fiche d'Android rendaient **les paragraphes et rien
 * d'autre**. Mesuré sur le corpus du 16 septembre 2026 : **1 727 titres perdus
 * sur 378 fiches**, jetés en silence.
 *
 * Le vault avait pourtant autorisé les titres le 30 août, et sa raison est
 * explicite — une fiche porte trois mouvements, « la racine dans les six
 * ruachim, le porteur, les renvois », et sans leurs titres ils arrivent collés
 * en un seul flot. La règle d'avant imposait « des paragraphes et rien
 * d'autre » précisément parce que la feuille **laissait tomber le reste sans
 * rien dire** ; la contrainte est tombée quand iOS a su les rendre.
 *
 * Android ne l'a jamais su. La donnée arrivait, l'écran la jetait, et le seul
 * signe était une fiche qui se lit comme un bloc compact.
 *
 * ## Pourquoi un composant partagé, et non trois corrections
 *
 * `TermSheet`, `ShemSheet` et `PrononciationSheet` répétaient chacun leur
 * `if (bloc is Block.Paragraph)`. Corriger les trois laisserait le quatrième
 * écran de fiche — celui qu'on écrira — recommencer. iOS a `BlocDeFiche.swift`
 * depuis le début, partagé par la feuille d'un intraduisible et celle d'un
 * Shem ; c'est son pendant.
 *
 * ## Ce qu'on ne rend pas, et pourquoi on le nomme
 *
 * `Verses` et `Table` sont nommés plutôt que laissés à un `else`, pour que
 * l'ajout d'un cas au domaine **casse ici** — c'est le seul endroit qui le
 * dirait. Un verset ne peut pas arriver : la prose de fiche n'en porte pas. Un
 * tableau, en revanche, est écrit dans les sept chuqqot du vault ; il n'arrive
 * pas jusqu'ici parce que `blocs_de_prose`, côté pipeline, ne rend que `Para`
 * et `Heading`. **Le trou est en amont**, et le combler ici le masquerait au
 * lieu de le fermer.
 */
@Composable
public fun BlocDeFiche(
    bloc: Block,
    typo: ONTTypography,
    showGloss: Boolean,
    showLevel3: Boolean,
    titresPleins: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val theme = LocalReadingTheme.current

    fun rendu(nodes: kotlin.collections.List<com.labibleont.ont.kit.corpus.Inline>) =
        ONTTextRenderer.compose(nodes, typo, showGloss = showGloss, showLevel3 = showLevel3)

    when (bloc) {
        is Block.Paragraph -> Text(
            rendu(bloc.nodes),
            modifier = modifier.padding(bottom = 10.dp),
        )

        // **Les niveaux se resserrent au lieu de se suivre.** Un `##` de fiche
        // est déjà sous un en-tête de section ; lui donner une taille de titre
        // le ferait rivaliser avec ce qui le contient. Deux tailles suffisent,
        // et la seconde n'est qu'une nuance. La règle vient d'iOS.
        is Block.Heading -> Text(
            rendu(bloc.nodes),
            fontFamily = ONTFonts.display,
            fontSize = when {
                titresPleins && bloc.level <= 2 -> 20.sp
                titresPleins -> 17.sp
                bloc.level <= 2 -> 15.sp
                else -> 13.sp
            },
            fontWeight = FontWeight.SemiBold,
            color = ONTColors.brandInk(theme),
            // Un titre est un en-tête pour TalkBack, sans quoi il se lit comme
            // une phrase de plus dans le flot.
            modifier = modifier
                .semantics { heading() }
                .padding(top = if (titresPleins) 14.dp else 6.dp, bottom = 6.dp),
        )

        // Le « Voir aussi » est une liste, et c'est le bloc qui devenait le plus
        // illisible collé à la prose.
        is Block.List -> Column(modifier = modifier.padding(bottom = 10.dp)) {
            for (item in bloc.items) {
                Row(verticalAlignment = Alignment.Top) {
                    Text("·", color = ONTColors.brandInk(theme))
                    Spacer(Modifier.width(8.dp))
                    Text(rendu(item))
                }
                Spacer(Modifier.height(4.dp))
            }
        }

        is Block.Quote -> Row(modifier = modifier.padding(bottom = 10.dp)) {
            HorizontalDivider(
                modifier = Modifier.width(2.dp).height(20.dp),
                color = ONTColors.brandInk(theme).copy(alpha = 0.4f),
            )
            Spacer(Modifier.width(10.dp))
            Text(rendu(bloc.nodes), fontStyle = FontStyle.Italic)
        }

        is Block.Rule -> HorizontalDivider(
            modifier = modifier.fillMaxWidth().padding(vertical = 10.dp),
            color = ONTColors.separator(theme),
        )

        is Block.Verses, is Block.Table -> Unit
    }
}
