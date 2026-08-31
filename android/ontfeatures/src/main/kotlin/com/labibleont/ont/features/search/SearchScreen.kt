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
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.foundation.layout.Arrangement
import com.labibleont.ont.kit.reader.ReadingTheme
import androidx.compose.foundation.lazy.itemsIndexed

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
            placeholder = { Text("Un mot, un intraduisible, ou de l'hébreu") },
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
            // Le nombre de passages, comme sur iOS. Une liste sans son compte
            // oblige à faire défiler pour savoir si la recherche a porté.
            if (model.resultats.isNotEmpty()) {
                item {
                    Text(
                        "${model.resultats.size} passage" +
                            if (model.resultats.size > 1) "s" else "",
                        fontSize = 13.sp,
                        color = ONTColors.inkSoft(theme),
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 6.dp),
                    )
                }
            }
            // ## La clé porte le rang, pas seulement l'identifiant
            //
            // `SearchHit.id` vaut `unité-verset-niveau`, et **ce n'est pas
            // unique** : deux correspondances dans le même verset au même
            // niveau le partagent. Chercher « alliance » suffisait à en
            // produire deux, et l'app tombait —
            // `IllegalArgumentException: Key "bereshit-15-0-body" was already used`.
            //
            // Le défaut vient du portage initial et dormait depuis. Il ne se
            // voit pas sur iOS : SwiftUI tolère les identifiants doublés, il
            // avertit. Compose lève. Le même domaine, la même donnée, et une
            // plateforme qui plante là où l'autre murmure.
            //
            // On ne corrige pas `id` dans `ontkit` : c'est un objet partagé,
            // et le changer relèverait d'un arbitrage qui appartient à iOS. La
            // clé de liste, elle, est une affaire de Compose.
            itemsIndexed(
                model.resultats,
                key = { rang, hit -> "$rang-${hit.id}" },
            ) { _, hit ->
                LigneDeResultat(hit = hit, requete = model.requete, onOuvrir = onOuvrir)
            }
            // Ce qu'on peut chercher, tant qu'on n'a pas assez tapé pour
            // chercher quoi que ce soit. Quatre exemples plutôt qu'une phrase :
            // un moteur qui accepte l'hébreu non vocalisé ne se devine pas.
            if (model.requete.trim().length < 2) {
                item { Exemples() }
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
private fun LigneDeResultat(
    hit: SearchHit,
    requete: String,
    onOuvrir: (String, String) -> Unit,
) {
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
        Text(
            surligne(hit.snippet, requete, theme),
            fontSize = 15.sp,
            color = ONTColors.ink(theme),
            maxLines = 3,
        )
    }
    HorizontalDivider(color = ONTColors.separator(theme))
}

/**
 * Le terme trouvé, marqué dans l'extrait.
 *
 * ## L'or voilé sur fond clair, l'encre dorée sur la nuit
 *
 * À 45 % sur un fond clair, l'or surligne. Sur la nuit il devient un aplat
 * lumineux sous une encre claire — c'est-à-dire un trou blanc. Sur fond sombre
 * on marque donc **par l'encre**, l'accent doré sur le texte lui-même, plutôt
 * que par un fond.
 *
 * La recherche ignore casse et diacritiques ; le marquage doit faire de même,
 * sans quoi « chesed » trouvé ne serait pas « Chesed » marqué.
 */
private fun surligne(extrait: String, requete: String, theme: ReadingTheme): AnnotatedString {
    val aiguille = requete.trim()
    if (aiguille.length < 2) return AnnotatedString(extrait)

    fun plier(t: String) = java.text.Normalizer.normalize(t, java.text.Normalizer.Form.NFD)
        .replace(Regex("\\p{Mn}+"), "")
        .lowercase()

    val i = plier(extrait).indexOf(plier(aiguille))
    if (i < 0 || i + aiguille.length > extrait.length) return AnnotatedString(extrait)

    return buildAnnotatedString {
        append(extrait.substring(0, i))
        withStyle(
            if (theme.isDark) {
                SpanStyle(color = ONTColors.accent(theme), fontWeight = FontWeight.Bold)
            } else {
                SpanStyle(
                    background = ONTColors.gold.copy(alpha = 0.45f),
                    fontWeight = FontWeight.Bold,
                )
            },
        ) { append(extrait.substring(i, i + aiguille.length)) }
        append(extrait.substring(i + aiguille.length))
    }
}

/**
 * Ce qu'on peut chercher.
 *
 * Quatre exemples et non une phrase d'aide : qu'un moteur accepte l'hébreu non
 * vocalisé et rende le texte vocalisé ne se devine pas, et personne ne lit une
 * notice avant de taper.
 */
@Composable
private fun Exemples() {
    val theme = LocalReadingTheme.current
    Column(
        modifier = Modifier.padding(32.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        for ((exemple, explication) in EXEMPLES) {
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(
                    exemple,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Medium,
                    color = ONTColors.brandInk(theme),
                )
                Text(explication, fontSize = 13.sp, color = ONTColors.inkSoft(theme))
            }
        }
    }
}

private val EXEMPLES = listOf(
    "chesed" to "un intraduisible — trouve aussi les passages en hébreu seul",
    "חסד" to "de l'hébreu sans voyelles — trouve le texte vocalisé",
    "alliance" to "un mot français du corps de la traduction",
    "temple cosmique" to "une expression, plutôt dans les gloses",
)
