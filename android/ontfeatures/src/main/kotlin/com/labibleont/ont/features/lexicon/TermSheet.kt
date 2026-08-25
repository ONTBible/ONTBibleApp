package com.labibleont.ont.features.lexicon

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.labibleont.ont.designsystem.text.ONTTextRenderer
import com.labibleont.ont.designsystem.theme.LocalReadingTheme
import com.labibleont.ont.designsystem.tokens.ONTColors
import com.labibleont.ont.designsystem.typography.ONTFonts
import com.labibleont.ont.designsystem.typography.ONTTypography
import com.labibleont.ont.kit.corpus.Block
import com.labibleont.ont.kit.reader.ReadingPreferences

/**
 * La fiche d'un intraduisible.
 *
 * ## Un terme sans fiche est un état prévu, pas une erreur
 *
 * Vingt lemmes de *Bereshit* n'ont pas encore d'entrée — `ishto`, `neshei`,
 * `ad-olam` : des formes dérivées de termes qui, eux, en ont une. On le dit au
 * lecteur plutôt que d'ouvrir une feuille vide, parce qu'une feuille vide
 * ressemble à un défaut de l'app alors que c'est l'état du corpus.
 */
@Composable
public fun TermSheet(
    lemme: String,
    model: LexiconModel,
    preferences: ReadingPreferences,
    modifier: Modifier = Modifier,
) {
    val theme = LocalReadingTheme.current
    val typo = ONTTypography(preferences.textSize.toFloat(), theme, preferences.bodyFont)
    val entree = model.entree(lemme)
    var corpsSeulement by remember { mutableStateOf(true) }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
    ) {
        if (entree == null) {
            Text(
                "Terme non documenté",
                fontFamily = ONTFonts.display,
                fontSize = 22.sp,
                color = ONTColors.inkStrong(theme),
            )
            Spacer(Modifier.height(8.dp))
            Text(
                "« $lemme » est balisé dans le texte mais n'a pas encore " +
                    "d'entrée dans le glossaire.",
                color = ONTColors.inkSoft(theme),
            )
            return@Column
        }

        Row(modifier = Modifier.fillMaxWidth()) {
            Text(
                entree.title,
                fontFamily = ONTFonts.display,
                fontSize = 28.sp,
                color = ONTColors.accent(theme),
                modifier = Modifier.weight(1f),
            )
            entree.hebrew?.let {
                Text(
                    it,
                    fontFamily = ONTFonts.hebrew,
                    fontSize = 26.sp,
                    color = ONTColors.ink(theme).copy(alpha = 0.85f),
                )
            }
        }

        entree.rendering?.let {
            Spacer(Modifier.height(4.dp))
            Text(it, fontSize = 16.sp, color = ONTColors.ink(theme))
        }

        // Les formes attestées : c'est ce qui permet de reconnaître le terme
        // sous ses flexions, et donc de comprendre qu'`ishto` est `ishah`.
        if (entree.forms.size > 1) {
            Spacer(Modifier.height(6.dp))
            Text(
                entree.forms.joinToString(" · "),
                fontSize = 13.sp,
                fontStyle = FontStyle.Italic,
                color = ONTColors.inkSoft(theme),
            )
        }

        entree.firstUse?.let {
            Spacer(Modifier.height(6.dp))
            Text("Premier emploi — $it", fontSize = 13.sp, color = ONTColors.inkSoft(theme))
        }

        Spacer(Modifier.height(16.dp))
        HorizontalDivider(color = ONTColors.separator(theme))
        Spacer(Modifier.height(16.dp))

        entree.definition?.let { blocs ->
            for (bloc in blocs) {
                if (bloc is Block.Paragraph) {
                    Text(
                        ONTTextRenderer.compose(
                            bloc.nodes, typo,
                            showGloss = preferences.showGloss,
                            showLevel3 = preferences.showLevel3,
                        ),
                        modifier = Modifier.padding(bottom = 10.dp),
                    )
                }
            }
        }

        Spacer(Modifier.height(20.dp))
        Text(
            "Où il paraît",
            fontFamily = ONTFonts.display,
            fontSize = 18.sp,
            color = ONTColors.brandInk(theme),
        )
        Spacer(Modifier.height(8.dp))

        // Deux questions, pas deux filtres : « où le texte dit ce mot » et
        // « où on l'explique » (§2.1).
        Row {
            FilterChip(
                selected = corpsSeulement,
                onClick = { corpsSeulement = true },
                label = { Text("Dans le texte (${entree.bodyCount})") },
            )
            Spacer(Modifier.padding(4.dp))
            FilterChip(
                selected = !corpsSeulement,
                onClick = { corpsSeulement = false },
                label = { Text("Partout (${entree.count})") },
            )
        }

        Spacer(Modifier.height(12.dp))
        for (occurrence in model.occurrences(entree.lemma, corpsSeulement).take(60)) {
            Column(modifier = Modifier.padding(bottom = 10.dp)) {
                Text(
                    listOfNotNull(occurrence.chapterId, occurrence.verse?.toString())
                        .joinToString(":"),
                    fontSize = 12.sp,
                    color = ONTColors.accent(theme),
                )
                Text(occurrence.snippet, fontSize = 14.sp, color = ONTColors.ink(theme))
            }
        }
    }
}
