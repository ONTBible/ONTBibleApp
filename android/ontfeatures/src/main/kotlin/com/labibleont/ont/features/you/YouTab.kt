package com.labibleont.ont.features.you

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
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.labibleont.ont.designsystem.theme.LocalReadingTheme
import com.labibleont.ont.designsystem.tokens.ONTColors
import com.labibleont.ont.designsystem.typography.ONTFonts
import com.labibleont.ont.kit.reader.DailyVerseSchedule
import com.labibleont.ont.kit.reader.ReadingFont
import com.labibleont.ont.kit.reader.ReadingPreferences
import com.labibleont.ont.kit.reader.ReadingTheme

/**
 * L'onglet Vous — ce que le lecteur règle.
 *
 * ## Les deux premiers interrupteurs ne sont pas des préférences d'affichage
 *
 * Ce sont les **niveaux du texte** (§2.1), et pouvoir les éteindre est la raison
 * d'être de la liseuse. Corps seul, on lit d'une traite ; gloses allumées, on
 * lit l'appareil ; hébreu allumé, on travaille. Ils sont donc en tête, avant la
 * taille et le thème.
 */
@Composable
public fun YouTab(
    preferences: ReadingPreferences,
    onChange: (ReadingPreferences) -> Unit,
    /**
     * Appelé quand le rappel change — pour demander l'autorisation et
     * (re)programmer le réveil.
     *
     * L'écran ne le fait pas lui-même : demander une autorisation système
     * demande une activité, et un module de fonctionnalités n'en a pas. C'est
     * la racine de composition qui sait.
     */
    onRappel: (DailyVerseSchedule) -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val theme = LocalReadingTheme.current

    Column(
        modifier = modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp),
    ) {
        Text(
            "Vous",
            fontFamily = ONTFonts.display,
            fontSize = 32.sp,
            color = ONTColors.inkStrong(theme),
            modifier = Modifier.padding(top = 16.dp, bottom = 16.dp),
        )

        Section("Les niveaux du texte")
        Interrupteur(
            titre = "Les gloses",
            detail = "Niveau 2 — la voix du projet, entre crochets",
            actif = preferences.showGloss,
            onChange = { onChange(preferences.copy(showGloss = it)) },
        )
        Interrupteur(
            titre = "Translittération et hébreu",
            detail = "Niveau 3 — entre parenthèses",
            actif = preferences.showLevel3,
            onChange = { onChange(preferences.copy(showLevel3 = it)) },
        )

        Section("La lecture")
        Interrupteur(
            titre = "Versets à la suite",
            detail = "En prose continue plutôt qu'un verset par bloc",
            actif = preferences.continuous,
            onChange = { onChange(preferences.copy(continuous = it)) },
        )

        Spacer(Modifier.height(8.dp))
        Text("Taille du texte", color = ONTColors.ink(theme))
        Text(
            // Le curseur du système s'applique par-dessus : ce réglage-ci est
            // la taille de base, pas la taille finale. Le dire évite qu'on le
            // croie plafonné quand c'est l'inverse.
            "${preferences.textSize.toInt()} pt — l'accessibilité du système s'y ajoute",
            fontSize = 12.sp,
            color = ONTColors.inkSoft(theme),
        )
        Slider(
            value = preferences.textSize.toFloat(),
            onValueChange = { onChange(preferences.copy(textSize = it.toDouble())) },
            valueRange = 14f..34f,
            steps = 19,
        )

        Section("Notifications")
        Interrupteur(
            titre = "Le verset du jour",
            detail = "Posé par l'appareil, à l'heure que vous choisissez",
            actif = preferences.daily.enabled,
            onChange = { actif ->
                val rappel = preferences.daily.copy(enabled = actif)
                onChange(preferences.copy(daily = rappel))
                onRappel(rappel)
            },
        )
        if (preferences.daily.enabled) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("À ", color = ONTColors.ink(theme))
                Text(
                    "%02d:%02d".format(preferences.daily.hour, preferences.daily.minute),
                    fontFamily = ONTFonts.display,
                    fontSize = 20.sp,
                    color = ONTColors.accent(theme),
                )
                Spacer(Modifier.padding(8.dp))
                // À la minute près, parce que la minute est ce qui rend le
                // rappel utilisable : 7 h 00 tombe dans le réveil, 7 h 12 dans
                // le trajet. N'offrir que des heures rondes force à choisir
                // entre deux mauvais moments.
                for (pas in listOf(-60, -5, 5, 60)) {
                    FilterChip(
                        selected = false,
                        onClick = {
                            val total = (preferences.daily.hour * 60 +
                                preferences.daily.minute + pas + 1440) % 1440
                            val rappel = DailyVerseSchedule.borne(
                                enabled = true,
                                hour = total / 60,
                                minute = total % 60,
                            )
                            onChange(preferences.copy(daily = rappel))
                            onRappel(rappel)
                        },
                        label = {
                            Text(
                                if (pas > 0) "+${if (pas == 60) "1 h" else "$pas min"}"
                                else "−${if (pas == -60) "1 h" else "${-pas} min"}",
                                fontSize = 12.sp,
                            )
                        },
                        modifier = Modifier.padding(end = 4.dp),
                    )
                }
            }
            Text(
                // Le point où Android fait mieux qu'iOS, et il vaut d'être dit
                // au lecteur : là-bas les deux usages partagent une seule
                // autorisation, ici ce sont deux canaux qu'il règle séparément
                // depuis le système.
                "Les parutions sont un canal séparé : vous pouvez couper l'un " +
                    "sans l'autre depuis les réglages d'Android.",
                fontSize = 12.sp,
                color = ONTColors.inkSoft(theme),
                modifier = Modifier.padding(bottom = 8.dp),
            )
        }

        Section("La peau")
        Row(modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp)) {
            for (t in ReadingTheme.entries) {
                FilterChip(
                    selected = preferences.theme == t,
                    onClick = { onChange(preferences.copy(theme = t)) },
                    label = { Text(t.label) },
                    modifier = Modifier.padding(end = 6.dp),
                )
            }
        }

        Section("La fonte du corps")
        for (f in ReadingFont.entries) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                FilterChip(
                    selected = preferences.bodyFont == f,
                    onClick = { onChange(preferences.copy(bodyFont = f)) },
                    label = { Text(f.label) },
                )
                Spacer(Modifier.padding(6.dp))
                Text(f.note, fontSize = 12.sp, color = ONTColors.inkSoft(theme))
            }
        }

        Spacer(Modifier.height(40.dp))
    }
}

@Composable
private fun Section(titre: String) {
    val theme = LocalReadingTheme.current
    Spacer(Modifier.height(20.dp))
    Text(
        titre,
        fontFamily = ONTFonts.display,
        fontSize = 15.sp,
        color = ONTColors.brandInk(theme),
    )
    HorizontalDivider(
        color = ONTColors.separator(theme),
        modifier = Modifier.padding(top = 4.dp, bottom = 8.dp),
    )
}

@Composable
private fun Interrupteur(
    titre: String,
    detail: String,
    actif: Boolean,
    onChange: (Boolean) -> Unit,
) {
    val theme = LocalReadingTheme.current
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(titre, color = ONTColors.ink(theme))
            Text(detail, fontSize = 12.sp, color = ONTColors.inkSoft(theme))
        }
        Switch(checked = actif, onCheckedChange = onChange)
    }
}
