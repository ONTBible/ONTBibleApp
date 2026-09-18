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
import com.labibleont.ont.kit.reader.ReadingPreferences

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
    preferences: ReadingPreferences,
    titresPleins: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val theme = LocalReadingTheme.current
    val showGloss = preferences.showGloss
    val showLevel3 = preferences.showLevel3

    // **La taille du corps, d'où tout le reste se dérive.**
    //
    // Les préférences entières plutôt que deux booléens extraits : il manquait
    // `textSize`, et c'est ce qui rendait les titres sourds au réglage du
    // lecteur. Passer un objet par ses parties fait qu'on oublie celle qu'on
    // n'a pas encore employée.
    val corps = preferences.textSize.toFloat()

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
            // ## Des rapports au corps, jamais des points fixes
            //
            // Ces quatre valeurs étaient `20.sp`, `17.sp`, `15.sp`, `13.sp` —
            // écrites en dur, donc **sourdes au réglage de taille du lecteur**.
            // Le corps d'une fiche, lui, suit `preferences.textSize`. Dès que le
            // lecteur monte le curseur au-delà de 20, un titre « plein » passait
            // *sous* son propre corps de texte, et un titre resserré s'y trouvait
            // déjà à 15.
            //
            // Ce n'est pas un détail d'esthétique : c'est le curseur que monte
            // celui qui voit mal, donc le défaut frappe exactement qui en dépend
            // le plus. `ShemSheet` était le seul écran à faire juste — ses titres
            // valaient `textSize * 1.1f` — et le brancher ici sans ce correctif
            // aurait cassé la seule chose qui marchait.
            //
            // Les rapports sont ceux d'iOS au chiffre près, relevés dans
            // `BlocDeFiche.swift:86-93` : `title3` et `headline` en régime plein,
            // `subheadline` et `footnote` en resserré.
            //
            // ## Un titre resserré est plus petit que sa propre prose
            //
            // `0.88` et `0.76` sont bien **sous** le corps, et c'est délibéré. Ce
            // qui tient ces titres n'est pas la taille — c'est le demi-gras et la
            // couleur. La taille est cédée volontairement, parce qu'un `##` de
            // fiche est déjà sous un en-tête de section : lui donner une taille de
            // titre le ferait rivaliser avec le bloc qui le contient.
            //
            // **Le demi-gras et la couleur ne sont donc pas décoratifs : ils sont
            // la moitié du mécanisme.** Les retirer ne rendrait pas le titre plus
            // discret, il cesserait d'être un titre — une phrase en retrait.
            //
            // Le principe vient d'iOS et il est documenté là-bas. Il est remonté à
            // l'auteur le 18 septembre 2026, parce qu'un titre plus petit que son
            // corps dans une app dont l'auteur monte le curseur mérite qu'il l'ait
            // vu. S'il le renverse, c'est l'échelle qui changera — pas le régime.
            fontSize = (
                corps * when {
                    titresPleins && bloc.level <= 2 -> 1.18f // title3   20/17
                    titresPleins -> 1.00f // headline    17/17
                    bloc.level <= 2 -> 0.88f // subheadline 15/17
                    else -> 0.76f // footnote    13/17
                }
                ).sp,
            fontWeight = FontWeight.SemiBold,
            // ## `accent`, et non `brandInk` — arbitrage iOS du 18 septembre 2026
            //
            // Les deux tokens sont identiques en sombre et **divergent en clair** :
            // `accent` rend goldDeep, `brandInk` rend burgundy. iOS emploie
            // `theme.accent` pour les trois — titre, puce de liste, barre de
            // citation —, et son `ONTColors.swift` porte la phrase qui tranche :
            // « pour de l'encre, ce rôle ; pour un accent doré, `accent(_:)` ».
            //
            // Un titre de fiche n'est pas de l'encre. C'est un accent, et c'est
            // même l'essentiel de ce qui le tient : au régime resserré il est plus
            // petit que sa prose, donc seuls le demi-gras et la couleur le
            // distinguent. J'avais écrit `brandInk` par réflexe de marque — juste
            // dans le principe, à un cran dans la teinte.
            color = ONTColors.accent(theme),
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
                    Text("·", color = ONTColors.accent(theme))
                    Spacer(Modifier.width(8.dp))
                    Text(rendu(item))
                }
                Spacer(Modifier.height(4.dp))
            }
        }

        is Block.Quote -> Row(modifier = modifier.padding(bottom = 10.dp)) {
            HorizontalDivider(
                modifier = Modifier.width(2.dp).height(20.dp),
                color = ONTColors.accent(theme).copy(alpha = 0.4f),
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
