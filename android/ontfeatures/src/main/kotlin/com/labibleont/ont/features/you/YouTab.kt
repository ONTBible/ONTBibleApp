package com.labibleont.ont.features.you

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.FormatSize
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.WbTwilight
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.labibleont.ont.designsystem.metrics.ONTRadius
import com.labibleont.ont.designsystem.metrics.ontSpacing
import com.labibleont.ont.designsystem.surfaces.ONTGroup
import com.labibleont.ont.designsystem.surfaces.ONTGroupDivider
import com.labibleont.ont.designsystem.surfaces.ONTLargeTitle
import com.labibleont.ont.designsystem.surfaces.ONTPage
import com.labibleont.ont.designsystem.surfaces.ONTRow
import com.labibleont.ont.designsystem.surfaces.ONTSectionHeader
import com.labibleont.ont.designsystem.theme.LocalReadingTheme
import com.labibleont.ont.designsystem.tokens.ONTColors
import com.labibleont.ont.kit.reader.ReadingPreferences

/** Ce vers quoi une ligne de l'onglet Vous conduit. */
public enum class DestinationVous {
    LECTURE,
    VERSET_DU_JOUR,
    PARUTIONS,

    /** Le catalogue du design system — en développement seulement. */
    CATALOGUE,
}

/**
 * L'onglet Vous — un **hall**, pas un déversoir de réglages.
 *
 * ## Pourquoi des sous-écrans et non une page unique
 *
 * La première version d'Android empilait tout : niveaux, taille, thème, fonte,
 * rappel. C'était lisible et ça ne ressemblait à rien — une colonne
 * d'interrupteurs séparés par des traits pleine largeur.
 *
 * iOS en fait un sommaire : quelques groupes encartés, chaque ligne menant à un
 * écran qui ne traite qu'une chose. Ce n'est pas une préférence esthétique.
 * C'est ce qui permet à l'écran du **verset du jour** d'exister séparément de
 * celui des **parutions** — la distinction que la PR #74 a établie côté iOS, et
 * qu'une page unique aurait effacée.
 *
 * On reprend donc la structure. Ce qui change, ce sont les gestes : le retour
 * système ferme un sous-écran, et les lignes suivent la cible tactile
 * d'Android.
 */
@Composable
public fun YouTab(
    preferences: ReadingPreferences,
    onPreferences: (ReadingPreferences) -> Unit,
    slotsRediges: Int,
    slotsTotal: Int,
    versets: Int,
    onAller: (DestinationVous) -> Unit,
    onPasEncore: () -> Unit,
    /**
     * Vrai en build de développement.
     *
     * Le catalogue n'a rien à faire dans une app livrée : il ne sert qu'à
     * repérer une dérive de style avant qu'elle n'atteigne un écran de lecture.
     */
    enDeveloppement: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val theme = LocalReadingTheme.current
    val espace = ontSpacing

    Column(
        modifier = modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState()),
    ) {
        ONTPage {
            ONTLargeTitle("Vous")

            ONTSectionHeader("Compte")
            ONTGroup {
                Column(
                    modifier = Modifier.padding(espace.m),
                    verticalArrangement = Arrangement.spacedBy(espace.s),
                ) {
                    BoutonDeConnexion("Continuer avec Google") { onPasEncore() }
                    BoutonDeConnexion("Continuer avec GitHub") { onPasEncore() }
                }
            }
            Text(
                // Le dire avant qu'on se demande : rien n'oblige à créer un
                // compte. C'est une propriété de l'app, pas une concession.
                "La lecture, les surlignages et les notes fonctionnent " +
                    "entièrement sans compte. La connexion ne sert qu'à les " +
                    "retrouver sur un autre appareil.",
                color = ONTColors.inkSoft(theme),
                fontSize = 13.sp,
                modifier = Modifier.padding(
                    start = espace.l,
                    end = espace.l,
                    top = espace.s,
                ),
            )

            Spacer(Modifier.height(espace.xl))

            ONTSectionHeader("Notifications")
            ONTGroup {
                ONTRow(
                    titre = "Verset du jour",
                    detail = if (preferences.daily.enabled) {
                        "à %02d:%02d".format(preferences.daily.hour, preferences.daily.minute)
                    } else {
                        "éteint"
                    },
                    icone = Icons.Filled.WbTwilight,
                    onClick = { onAller(DestinationVous.VERSET_DU_JOUR) },
                    fin = { Chevron() },
                )
                ONTGroupDivider()
                ONTRow(
                    titre = "Parutions",
                    detail = "quand un livre paraît",
                    icone = Icons.AutoMirrored.Filled.MenuBook,
                    onClick = { onAller(DestinationVous.PARUTIONS) },
                    fin = { Chevron() },
                )
            }

            Spacer(Modifier.height(espace.xl))

            ONTSectionHeader("Lecture")
            ONTGroup {
                ONTRow(
                    titre = "Réglages de lecture",
                    detail = "niveaux, taille, thème, fonte",
                    icone = Icons.Filled.FormatSize,
                    onClick = { onAller(DestinationVous.LECTURE) },
                    fin = { Chevron() },
                )
            }

            Spacer(Modifier.height(espace.xl))

            ONTSectionHeader("Le Corpus")
            // **Le registre ouvre la section du corpus, et ne s'y confond pas.**
            //
            // Il était rangé dans les réglages de lecture, entre la disposition
            // des versets et la taille du texte. C'était le ranger avec la
            // typographie : or il ne change pas la façon dont le texte se
            // présente, il change **ce que les livres sont appelés** — donc le
            // corpus lui-même, tel que le lecteur le rencontre.
            //
            // Sa propre carte, détachée des deux compteurs, parce que ce n'est
            // pas une mesure : c'est le seul réglage de cet écran qui décide de
            // ce qu'on lit plutôt que de son état.
            ONTGroup {
                ONTRow(
                    titre = "Le français reçu",
                    fin = {
                        Switch(
                            checked = preferences.french,
                            onCheckedChange = { onPreferences(preferences.copy(french = it)) },
                        )
                    },
                )
            }
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
                modifier = Modifier.padding(start = espace.l, end = espace.l, top = espace.s),
            )

            Spacer(Modifier.height(espace.l))

            ONTGroup {
                ONTRow(titre = "Slots rédigés", fin = { Valeur("$slotsRediges / $slotsTotal") })
                ONTGroupDivider()
                ONTRow(titre = "Versets", fin = { Valeur("$versets") })
            }

            if (enDeveloppement) {
                Spacer(Modifier.height(espace.xl))
                ONTSectionHeader("Développement")
                ONTGroup {
                    ONTRow(
                        titre = "Design system",
                        detail = "jetons, surfaces, fontes, rendu",
                        icone = Icons.Filled.Palette,
                        onClick = { onAller(DestinationVous.CATALOGUE) },
                        fin = { Chevron() },
                    )
                }
            }

            Spacer(Modifier.height(espace.xxl))
        }
    }
}

@Composable
private fun Chevron() {
    val theme = LocalReadingTheme.current
    Icon(
        Icons.AutoMirrored.Filled.KeyboardArrowRight,
        contentDescription = null,
        tint = ONTColors.inkSoft(theme),
    )
}

@Composable
private fun Valeur(texte: String) {
    val theme = LocalReadingTheme.current
    Text(texte, color = ONTColors.inkSoft(theme), fontSize = 15.sp)
}

/**
 * Un bouton de connexion.
 *
 * Éteint tant que le compte n'existe pas, et **il le dit** : un bouton qui ne
 * répond pas sans expliquer pourquoi se lit comme un défaut de l'app.
 *
 * Pas de « Continuer avec Apple » : sur Android, il faudrait passer par le web,
 * et le lecteur qui a un compte Apple l'aura créé sur son iPhone. On l'ajoutera
 * quand la synchronisation existera, pas avant — annoncer trois fournisseurs
 * dont un ne marche pas est pire que d'en annoncer deux.
 */
@Composable
private fun BoutonDeConnexion(intitule: String, onAppui: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .clip(RoundedCornerShape(ONTRadius.pill))
            // **Plein**, pas délavé. Un bouton grisé se lit comme un défaut de
            // l'app ; celui-ci répond, et ce qu'il répond est qu'il n'est pas
            // encore branché. Dire « pas encore » vaut mieux que ne rien dire.
            .background(ONTColors.burgundy)
            .clickable(onClick = onAppui)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            intitule,
            color = ONTColors.gold,
            fontSize = 16.sp,
            textAlign = TextAlign.Center,
        )
    }
}
