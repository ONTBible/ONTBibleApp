package com.labibleont.ont.features.lexicon

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.labibleont.ont.designsystem.theme.LocalReadingTheme
import com.labibleont.ont.designsystem.tokens.ONTColors
import com.labibleont.ont.designsystem.typography.ONTFonts
import com.labibleont.ont.kit.glossary.GlossaryEntry

/**
 * L'onglet Lexique — les intraduisibles, toutes formes confondues.
 *
 * ## Ce qui est montré à côté du terme
 *
 * Le compte des occurrences, **séparé en deux** : corps et gloses. C'est la
 * distinction du §2.1, et elle est la première chose qu'on veut savoir d'un
 * terme — *YHWH* paraît 150 fois dans le texte et 313 fois dans son appareil.
 * Un total unique de 463 ne dirait rien de cet écart.
 */
@Composable
public fun LexiconTab(
    model: LexiconModel,
    onOuvrir: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val theme = LocalReadingTheme.current

    Column(modifier = modifier.fillMaxWidth()) {
        Text(
            "Lexique",
            fontFamily = ONTFonts.display,
            fontSize = 32.sp,
            color = ONTColors.inkStrong(theme),
            modifier = Modifier.padding(start = 20.dp, top = 16.dp, bottom = 8.dp),
        )

        OutlinedTextField(
            value = model.requete,
            onValueChange = { model.requete = it },
            placeholder = { Text("Chercher un intraduisible") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            colors = TextFieldDefaults.colors(
                focusedContainerColor = ONTColors.surface(theme),
                unfocusedContainerColor = ONTColors.surface(theme),
                focusedIndicatorColor = ONTColors.accent(theme),
                unfocusedIndicatorColor = ONTColors.separator(theme),
                cursorColor = ONTColors.accent(theme),
            ),
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 8.dp),
        )

        val visibles = model.visibles
        LazyColumn(modifier = Modifier.fillMaxWidth()) {
            items(visibles, key = { it.lemma }) { entree ->
                LigneDeTerme(entree = entree, onOuvrir = onOuvrir)
            }
            if (visibles.isEmpty()) {
                item {
                    Text(
                        "Aucun terme ne répond à cette recherche.",
                        color = ONTColors.inkSoft(theme),
                        modifier = Modifier.padding(20.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun LigneDeTerme(entree: GlossaryEntry, onOuvrir: (String) -> Unit) {
    val theme = LocalReadingTheme.current

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onOuvrir(entree.lemma) }
            .padding(horizontal = 20.dp, vertical = 12.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                entree.title,
                // L'or, comme dans le texte : un intraduisible se reconnaît à
                // sa couleur, ici comme à la lecture.
                color = ONTColors.accent(theme),
                fontSize = 18.sp,
            )
            entree.hebrew?.let {
                Text(
                    it,
                    fontFamily = ONTFonts.hebrew,
                    fontSize = 18.sp,
                    color = ONTColors.ink(theme).copy(alpha = 0.85f),
                )
            }
        }
        entree.rendering?.let {
            Text(it, fontSize = 14.sp, color = ONTColors.ink(theme))
        }
        Text(
            // Corps et gloses séparés — voir la doc de l'écran.
            "${entree.bodyCount} dans le texte · ${entree.glossCount} dans les gloses",
            fontSize = 12.sp,
            color = ONTColors.inkSoft(theme),
        )
        if (!entree.tagged) {
            Text(
                // Le §3 : traduit dans le corps, donc invisible au toucher,
                // mais consultable ici. Le dire évite qu'on le cherche en vain
                // dans le texte.
                "Traduit dans le texte, non balisé",
                fontSize = 11.sp,
                fontStyle = FontStyle.Italic,
                color = ONTColors.inkSoft(theme),
            )
        }
    }
    HorizontalDivider(color = ONTColors.separator(theme))
}
