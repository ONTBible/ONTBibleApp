package com.labibleont.ont.features.search

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import com.labibleont.ont.designsystem.theme.LocalReadingTheme
import com.labibleont.ont.designsystem.tokens.ONTColors
import com.labibleont.ont.designsystem.typography.ONTFonts
import com.labibleont.ont.kit.glossary.OccurrenceLevel
import com.labibleont.ont.kit.search.SearchHit
import com.labibleont.ont.kit.search.SearchScope

/**
 * La recherche.
 *
 * ## Trois portées, parce que ce sont trois questions
 *
 * « Où le texte dit-il *chesed* » et « où l'explique-t-on » ne se confondent
 * pas (§2.1). Les mêler noierait la première dans la seconde — l'appareil est
 * bien plus bavard que le corps.
 *
 * ## La saisie hébraïque marche sans voyelles
 *
 * Taper `חסד` au clavier hébreu ordinaire trouve `חֶסֶד` vocalisé : le moteur
 * dénude l'hébreu des deux côtés. C'est la seule façon d'écrire de l'hébreu au
 * quotidien, et un index qui l'ignorerait ne servirait qu'aux copier-coller.
 */
@Composable
public fun SearchScreen(
    model: SearchModel,
    onOuvrir: (bookId: String, chapterId: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val theme = LocalReadingTheme.current
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { focus.requestFocus() }

    Column(modifier = modifier.fillMaxWidth()) {
        OutlinedTextField(
            value = model.requete,
            onValueChange = model::saisir,
            placeholder = { Text("Chercher dans le corpus") },
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
                .padding(horizontal = 20.dp, vertical = 8.dp)
                .focusRequester(focus),
        )

        Row(modifier = Modifier.padding(horizontal = 20.dp)) {
            for (p in SearchScope.entries) {
                FilterChip(
                    selected = model.portee == p,
                    onClick = { model.changerPortee(p) },
                    label = { Text(p.label, fontSize = 13.sp) },
                    modifier = Modifier.padding(end = 6.dp),
                )
            }
        }

        if (model.cherche) {
            LinearProgressIndicator(
                color = ONTColors.accent(theme),
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
            )
        }

        Spacer(Modifier.height(8.dp))

        LazyColumn(modifier = Modifier.fillMaxWidth()) {
            items(model.resultats, key = { it.id }) { hit ->
                LigneDeResultat(hit = hit, onOuvrir = onOuvrir)
            }
            if (model.resultats.isEmpty() && model.requete.trim().length >= 2 && !model.cherche) {
                item {
                    Text(
                        "Rien trouvé. Le corpus compte quatre livres rédigés sur soixante-dix.",
                        color = ONTColors.inkSoft(theme),
                        modifier = Modifier.padding(20.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun LigneDeResultat(hit: SearchHit, onOuvrir: (String, String) -> Unit) {
    val theme = LocalReadingTheme.current

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onOuvrir(hit.record.b, hit.record.c) }
            .padding(horizontal = 20.dp, vertical = 12.dp),
    ) {
        Row(modifier = Modifier.fillMaxWidth()) {
            Text(
                listOfNotNull(hit.record.c, hit.record.verse?.toString()).joinToString(":"),
                fontFamily = ONTFonts.display,
                fontSize = 13.sp,
                color = ONTColors.brandInk(theme),
                modifier = Modifier.weight(1f),
            )
            // Dire **où** la correspondance a été trouvée : un résultat de
            // glose n'a pas la même valeur qu'un résultat de corps, et le
            // lecteur doit pouvoir le voir sans ouvrir.
            Text(
                if (hit.level == OccurrenceLevel.BODY) "texte" else "glose",
                fontSize = 11.sp,
                color = ONTColors.inkSoft(theme),
            )
        }
        Spacer(Modifier.height(4.dp))
        Text(hit.snippet, fontSize = 15.sp, color = ONTColors.ink(theme), maxLines = 3)
    }
    HorizontalDivider(color = ONTColors.separator(theme))
}
