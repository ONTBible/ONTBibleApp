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
import com.labibleont.ont.kit.reader.DailyVerseSchedule
import com.labibleont.ont.kit.reader.ReadingPreferences

/**
 * Le verset du jour.
 *
 * ## Son propre écran, et c'est le point
 *
 * Côté iOS, la PR #74 a séparé cet écran de celui des parutions bien que les
 * deux partagent **une seule** autorisation système : la distinction est de
 * nature, pas de réglage. Le verset du jour est **local** — l'appareil le pose
 * à l'heure choisie, rien ne sort du téléphone. Une parution est **poussée**
 * par le serveur.
 *
 * Sur Android la séparation va plus loin : ce sont deux **canaux**, que le
 * lecteur règle indépendamment depuis le système. On le lui dit ici, parce que
 * c'est une liberté qu'il n'a pas sur l'autre plateforme.
 */
@Composable
public fun DailyVerseSettings(
    preferences: ReadingPreferences,
    apercu: String?,
    onChange: (DailyVerseSchedule) -> Unit,
    modifier: Modifier = Modifier,
) {
    val theme = LocalReadingTheme.current
    val espace = ontSpacing
    val rappel = preferences.daily

    Column(modifier = modifier.fillMaxWidth().verticalScroll(rememberScrollState())) {
        ONTPage {
            ONTGroup {
                ONTRow(
                    titre = "Le verset du jour",
                    detail = "Posé par l'appareil, à l'heure que vous choisissez",
                    fin = {
                        Switch(
                            checked = rappel.enabled,
                            onCheckedChange = { onChange(rappel.copy(enabled = it)) },
                        )
                    },
                )
                if (rappel.enabled) {
                    ONTGroupDivider()
                    Column(modifier = Modifier.padding(espace.l)) {
                        Text(
                            "%02d:%02d".format(rappel.hour, rappel.minute),
                            fontFamily = ONTFonts.display,
                            fontSize = 34.sp,
                            color = ONTColors.accent(theme),
                        )
                        Text(
                            // À la minute près, parce que la minute est ce qui
                            // rend le rappel utilisable : 7 h 00 tombe dans le
                            // réveil, 7 h 12 dans le trajet.
                            "À la minute près — 7 h 00 tombe dans le réveil, " +
                                "7 h 12 dans le trajet.",
                            color = ONTColors.inkSoft(theme),
                            fontSize = 13.sp,
                            modifier = Modifier.padding(bottom = espace.s),
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(espace.xs)) {
                            for (pas in listOf(-60, -5, 5, 60)) {
                                FilterChip(
                                    selected = false,
                                    onClick = {
                                        val total =
                                            (rappel.hour * 60 + rappel.minute + pas + 1440) % 1440
                                        onChange(
                                            DailyVerseSchedule.borne(
                                                enabled = true,
                                                hour = total / 60,
                                                minute = total % 60,
                                            ),
                                        )
                                    },
                                    label = {
                                        Text(
                                            if (pas > 0) {
                                                "+${if (pas == 60) "1 h" else "$pas min"}"
                                            } else {
                                                "−${if (pas == -60) "1 h" else "${-pas} min"}"
                                            },
                                            fontSize = 13.sp,
                                        )
                                    },
                                )
                            }
                        }
                    }
                }
            }

            Spacer(Modifier.height(espace.xl))

            apercu?.let {
                ONTSectionHeader("Aujourd'hui")
                ONTGroup {
                    Text(
                        it,
                        color = ONTColors.ink(theme),
                        fontSize = 15.sp,
                        modifier = Modifier.padding(espace.l),
                    )
                }
                Spacer(Modifier.height(espace.xl))
            }

            Text(
                "Le verset est calculé sur l'appareil, à partir de la date. " +
                    "Aucune requête, aucun horaire de lecture ne quitte votre " +
                    "téléphone.\n\nLes parutions sont un canal séparé : vous " +
                    "pouvez couper l'un sans l'autre depuis les réglages " +
                    "d'Android.",
                color = ONTColors.inkSoft(theme),
                fontSize = 13.sp,
                modifier = Modifier.padding(horizontal = espace.l),
            )
            Spacer(Modifier.height(espace.xxl))
        }
    }
}

/**
 * Les parutions.
 *
 * Annoncées, pas simulées : elles demandent le serveur de diffusion, qui
 * existe — les routes `/appareils` et `/diffuser` sont en place — mais que
 * l'app Android ne sait pas encore joindre.
 */
@Composable
public fun ParutionsSettings(modifier: Modifier = Modifier) {
    val theme = LocalReadingTheme.current
    val espace = ontSpacing

    Column(modifier = modifier.fillMaxWidth().verticalScroll(rememberScrollState())) {
        ONTPage {
            ONTGroup {
                ONTRow(
                    titre = "Parutions",
                    detail = "Quand un livre ou un chapitre paraît",
                    fin = { Switch(checked = false, onCheckedChange = null, enabled = false) },
                )
            }
            Spacer(Modifier.height(espace.l))
            Text(
                "Cette notification vient du serveur, pas de l'appareil : il " +
                    "faut donc un compte pour qu'il sache où l'envoyer. Elle " +
                    "s'allumera quand la connexion existera.\n\nElle a son " +
                    "propre canal Android : le jour venu, vous pourrez la " +
                    "régler sans toucher au verset du jour.",
                color = ONTColors.inkSoft(theme),
                fontSize = 13.sp,
                modifier = Modifier.padding(horizontal = espace.l),
            )
            Spacer(Modifier.height(espace.xxl))
        }
    }
}
