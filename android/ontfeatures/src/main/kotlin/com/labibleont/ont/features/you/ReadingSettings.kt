package com.labibleont.ont.features.you

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.sp
import com.labibleont.ont.designsystem.metrics.ontSpacing
import com.labibleont.ont.designsystem.surfaces.ONTGroup
import com.labibleont.ont.designsystem.surfaces.ONTGroupDivider
import com.labibleont.ont.designsystem.surfaces.ONTPage
import com.labibleont.ont.designsystem.surfaces.ONTRow
import com.labibleont.ont.designsystem.surfaces.ONTSectionHeader
import com.labibleont.ont.designsystem.theme.LocalReadingTheme
import com.labibleont.ont.designsystem.tokens.ONTColors
import com.labibleont.ont.designsystem.typography.ONTFonts
import com.labibleont.ont.kit.reader.ReadingFont
import com.labibleont.ont.kit.reader.ReadingPreferences
import com.labibleont.ont.kit.reader.ReadingTheme

/**
 * Les réglages de lecture.
 *
 * Les deux premiers interrupteurs ne sont pas des préférences d'affichage : ce
 * sont les **niveaux du texte** (§2.1), et pouvoir les éteindre est la raison
 * d'être de la liseuse. Corps seul, on lit d'une traite ; gloses allumées, on
 * lit l'appareil ; hébreu allumé, on travaille. Ils sont donc en tête.
 */
@Composable
public fun ReadingSettings(
    preferences: ReadingPreferences,
    onChange: (ReadingPreferences) -> Unit,
    /**
     * Faux quand l'écran est **déjà** dans un défilement.
     *
     * Deux défilements verticaux imbriqués font lever Compose : le parent
     * mesure l'enfant avec une hauteur infinie, et un composant défilant ne
     * sait pas quoi en faire. C'est ce qui faisait planter la feuille des
     * réglages en boucle.
     */
    defilant: Boolean = true,
    modifier: Modifier = Modifier,
) {
    val theme = LocalReadingTheme.current
    val espace = ontSpacing

    Column(
        modifier = modifier
            .fillMaxWidth()
            .then(if (defilant) Modifier.verticalScroll(rememberScrollState()) else Modifier),
    ) {
        ONTPage {
            ONTSectionHeader("Les niveaux du texte")
            ONTGroup {
                ONTRow(
                    titre = "Les gloses",
                    detail = "Niveau 2 — la voix du projet, entre crochets",
                    fin = {
                        Switch(
                            checked = preferences.showGloss,
                            onCheckedChange = { onChange(preferences.copy(showGloss = it)) },
                        )
                    },
                )
                ONTGroupDivider()
                ONTRow(
                    titre = "Translittération et hébreu",
                    detail = "Niveau 3 — entre parenthèses",
                    fin = {
                        Switch(
                            checked = preferences.showLevel3,
                            onCheckedChange = { onChange(preferences.copy(showLevel3 = it)) },
                        )
                    },
                )
            }

            Spacer(Modifier.height(espace.xl))

            ONTSectionHeader("La lecture")
            ONTGroup {
                ONTRow(
                    titre = "Versets à la suite",
                    detail = "En prose continue plutôt qu'un verset par bloc",
                    fin = {
                        Switch(
                            checked = preferences.continuous,
                            onCheckedChange = { onChange(preferences.copy(continuous = it)) },
                        )
                    },
                )
                ONTGroupDivider()
                Column(modifier = Modifier.padding(espace.l)) {
                    Row(modifier = Modifier.fillMaxWidth()) {
                        Text(
                            "Taille du texte",
                            color = ONTColors.ink(theme),
                            fontSize = 16.sp,
                            modifier = Modifier.weight(1f),
                        )
                        Text(
                            "${preferences.textSize.toInt()} pt",
                            color = ONTColors.accent(theme),
                            fontSize = 15.sp,
                        )
                    }
                    Text(
                        // Le curseur du système s'applique par-dessus : ce
                        // réglage est la taille de base, pas la taille finale.
                        // Le dire évite qu'on le croie plafonné quand c'est
                        // l'inverse.
                        "L'accessibilité du système s'y ajoute",
                        color = ONTColors.inkSoft(theme),
                        fontSize = 13.sp,
                    )
                    Slider(
                        value = preferences.textSize.toFloat(),
                        onValueChange = { onChange(preferences.copy(textSize = it.toDouble())) },
                        valueRange = 14f..34f,
                        steps = 19,
                    )
                }
            }

            Spacer(Modifier.height(espace.xl))

            ONTSectionHeader("Nom des livres")
            ONTGroup {
                ONTRow(
                    titre = "Le français reçu",
                    fin = {
                        Switch(
                            checked = preferences.french,
                            onCheckedChange = { onChange(preferences.copy(french = it)) },
                        )
                    },
                )
            }
            // Le texte d'iOS, mot pour mot. `Form` lui donne un bas de section ;
            // Compose n'en a pas, donc il se pose sous le groupe — mais il ne
            // se résume pas : c'est le seul endroit où le lecteur apprend
            // pourquoi le réglage existe.
            Text(
                "Allumé, les livres portent le nom qu'on leur connaît — " +
                    "« Apocalypse », « la Loi », « Chapitre 7 ». Éteint, ils " +
                    "portent ce que leur nom hébreu veut dire : « le machazeh " +
                    "de Yohanan », « la Fondation », « Parashah 7 ».\n\n" +
                    "L'écart entre les deux n'est pas une nuance de traduction. " +
                    "La torah est l'instruction qui vise ; le grec l'a rendue par " +
                    "nomos, le code qui contraint, et le français en a hérité " +
                    "« la Loi ».\n\n" +
                    "Ce réglage est une béquille, et il est allumé pour qu'on " +
                    "puisse marcher avant de savoir. En l'éteignant, des mots " +
                    "apparaissent que vous n'avez peut-être jamais lus — parashah, " +
                    "la division que le scribe hébreu traçait en laissant un blanc, " +
                    "mille ans avant qu'on numérote des chapitres.",
                color = ONTColors.inkSoft(theme),
                fontSize = 13.sp,
                modifier = Modifier.padding(
                    start = espace.l,
                    end = espace.l,
                    top = espace.s,
                ),
            )

            Spacer(Modifier.height(espace.xl))

            ONTSectionHeader("La peau")
            ONTGroup {
                Column(modifier = Modifier.padding(espace.m)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(espace.s)) {
                        for (t in ReadingTheme.entries) {
                            FilterChip(
                                selected = preferences.theme == t,
                                onClick = { onChange(preferences.copy(theme = t)) },
                                label = { Text(t.label, fontSize = 13.sp) },
                            )
                        }
                    }
                }
            }

            Spacer(Modifier.height(espace.xl))

            ONTSectionHeader("La fonte du corps")
            ONTGroup {
                ReadingFont.entries.forEachIndexed { i, f ->
                    if (i > 0) ONTGroupDivider()
                    ONTRow(
                        titre = f.label,
                        detail = f.note,
                        onClick = { onChange(preferences.copy(bodyFont = f)) },
                        fin = {
                            // Un aperçu de la fonte à côté de son nom : on
                            // choisit une lettre, pas une étiquette.
                            Text(
                                "Aa",
                                fontFamily = ONTFonts.family(f),
                                fontSize = 22.sp,
                                color = if (preferences.bodyFont == f) {
                                    ONTColors.accent(theme)
                                } else {
                                    ONTColors.inkSoft(theme)
                                },
                            )
                        },
                    )
                }
            }

            Spacer(Modifier.height(espace.xxl))
        }
    }
}
