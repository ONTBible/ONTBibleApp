package com.labibleont.ont.features.qahal

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.Forum
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.labibleont.ont.designsystem.text.ONTTextRenderer
import com.labibleont.ont.designsystem.theme.LocalReadingTheme
import com.labibleont.ont.designsystem.surfaces.ONTMountain
import com.labibleont.ont.designsystem.tokens.ONTColors
import com.labibleont.ont.designsystem.typography.ONTFonts
import com.labibleont.ont.designsystem.typography.ONTTypography
import com.labibleont.ont.kit.corpus.Chapter
import com.labibleont.ont.kit.corpus.Verse
import com.labibleont.ont.kit.reader.ReadingPreferences
import androidx.compose.foundation.layout.width

/**
 * **Qahal** (קָהָל) — l'assemblée. La part communautaire.
 *
 * Le nom est cohérent avec le corpus : la *Kenesset* est le rassemblement des
 * **textes**, le *Qahal* celui des **lecteurs**.
 *
 * ## Ce qui n'existe pas est annoncé, jamais simulé
 *
 * Structure posée, sans serveur : le verset du jour est tiré localement, et
 * tout ce qui suppose d'autres lecteurs est nommé sans être mis en scène. Un
 * faux fil d'activité donnerait une idée fausse de ce qui existe — et le jour
 * où le vrai arrive, personne ne verrait la différence.
 */
@Composable
public fun QahalTab(
    chapitre: Chapter?,
    verset: Verse?,
    preferences: ReadingPreferences,
    onPartager: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val theme = LocalReadingTheme.current

    Column(
        modifier = modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(26.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            "Qahal",
            fontFamily = ONTFonts.display,
            fontSize = 32.sp,
            color = ONTColors.inkStrong(theme),
            modifier = Modifier.fillMaxWidth(),
        )

        if (chapitre != null && verset != null) {
            CarteDuVersetDuJour(
                chapitre = chapitre,
                verset = verset,
                preferences = preferences,
                onPartager = onPartager,
            )
        }

        AVenir()
        Spacer(Modifier.height(24.dp))
    }
}

/**
 * La carte du verset du jour.
 *
 * ## Ce que le widget ne peut pas faire
 *
 * Composer le verset depuis son **arbre d'inline**, avec les intraduisibles en
 * or. Le widget lit un vivier plat de 60 Ko — il n'a pas l'arbre, et n'aurait
 * pas la mémoire pour le charger. Ici on l'a, donc on rend le texte tel qu'il
 * se lit dans le chapitre.
 *
 * Le corps seul, en revanche : un verset du jour se lit d'une traite, et les
 * gloses de l'ONT font parfois quarante mots.
 */
@Composable
private fun CarteDuVersetDuJour(
    chapitre: Chapter,
    verset: Verse,
    preferences: ReadingPreferences,
    onPartager: (String) -> Unit,
) {
    val theme = LocalReadingTheme.current
    val typo = ONTTypography(preferences.textSize.toFloat(), theme, preferences.bodyFont)
    val renvoi = "${chapitre.title}:${verset.n}"
    val texte = ONTTextRenderer.composeBare(verset.nodes, typo, ink = ONTColors.gold)

    Column(
        modifier = Modifier
            // La carte garde sa mesure : l'étaler sur une tablette la
            // transformerait en bande, et le verset ne tiendrait plus que sur
            // deux lignes traversant l'écran.
            .widthIn(max = 420.dp)
            .fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            // Le bordeaux **brut**, et c'est le seul endroit où on l'emploie :
            // c'est une couleur de marque, faite pour être un fond avec de l'or
            // dessus. Jamais comme encre.
            .background(ONTColors.burgundy)
            .padding(22.dp),
    ) {
        // ## L'intitulé, que la carte n'avait pas
        //
        // Sans lui, la carte s'ouvrait sur le verset : un aplat bordeaux avec
        // du texte d'or, qu'on ne distingue d'une citation ordinaire qu'en
        // lisant le renvoi tout en bas. L'intitulé dit d'un coup d'œil ce
        // qu'on regarde, et le mont dit de qui ça vient.
        //
        // En capitales avec l'interlettrage qui va avec : sans lui, des
        // capitales se collent et se lisent moins bien qu'un bas-de-casse.
        Row(verticalAlignment = Alignment.CenterVertically) {
            ONTMountain(hauteur = 21.dp, teinte = ONTColors.gold)
            Spacer(Modifier.width(7.dp))
            Text(
                "VERSET DU JOUR",
                color = ONTColors.gold,
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                letterSpacing = 0.8.sp,
                maxLines = 1,
            )
        }
        Spacer(Modifier.height(18.dp))

        Text(
            texte,
            style = androidx.compose.ui.text.TextStyle(lineHeight = 1.5.em),
        )
        Spacer(Modifier.height(18.dp))

        // Le renvoi est **gras**, pas italique : c'est une étiquette qu'on
        // repère, pas une citation dans une citation.
        Text(
            renvoi,
            color = ONTColors.gold,
            fontFamily = ONTFonts.display,
            fontSize = 15.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
        )
        Spacer(Modifier.height(18.dp))

        // La pastille est **sous** le renvoi, et non à sa droite.
        //
        // Sur la même ligne, elle poussait le renvoi contre le bord gauche et
        // les deux se disputaient la largeur : un renvoi long — « Toledot Adam
        // ve-Chavah 6:2 » en fait vingt-six signes — s'écrasait pour lui faire
        // place. Empilés, chacun a toute la mesure, et l'œil descend
        // intitulé, verset, source, action, dans l'ordre où il en a besoin.
        Text(
            "Partager",
            color = ONTColors.gold,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier
                .clip(RoundedCornerShape(50))
                // Un voile d'or, un texte d'or plein — le même traitement
                // que la pastille du widget, pour que les deux cartes
                // restent jumelles.
                .background(ONTColors.gold.copy(alpha = 0.18f))
                .clickable {
                    onPartager("« ${texte.text} »\n\n$renvoi — La Bible ONT")
                }
                .padding(horizontal = 16.dp, vertical = 8.dp),
        )
    }
}

private val Double.em: androidx.compose.ui.unit.TextUnit
    get() = androidx.compose.ui.unit.TextUnit(
        this.toFloat(),
        androidx.compose.ui.unit.TextUnitType.Em,
    )

@Composable
private fun AVenir() {
    val theme = LocalReadingTheme.current

    Column(
        modifier = Modifier
            .widthIn(max = 420.dp)
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(ONTColors.surface(theme))
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text(
            "À VENIR",
            fontSize = 11.sp,
            color = ONTColors.inkSoft(theme),
        )

        Ligne(
            Icons.Filled.FavoriteBorder,
            "Ce que le Qahal a retenu",
            "les versets les plus repris",
        )
        Ligne(Icons.Filled.Forum, "Échanges", "commenter un passage")
        Ligne(
            Icons.AutoMirrored.Filled.MenuBook,
            "Parcours",
            "lire le corpus à plusieurs",
        )

        Text(
            // Dire ce qui manque **et** ce qui ne manque pas. La lecture ne
            // dépend d'aucun serveur, et c'est une propriété de l'app qui
            // mérite d'être sue plutôt que découverte dans un train.
            "Ces fonctions demandent un serveur. La lecture, elle, fonctionne " +
                "entièrement hors ligne.",
            fontSize = 12.sp,
            color = ONTColors.inkSoft(theme),
            textAlign = TextAlign.Start,
        )
    }
}

@Composable
private fun Ligne(icone: ImageVector, titre: String, detail: String) {
    val theme = LocalReadingTheme.current
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(
            icone,
            contentDescription = null,
            tint = ONTColors.accent(theme),
            modifier = Modifier.padding(end = 12.dp),
        )
        Column {
            Text(titre, color = ONTColors.ink(theme), fontSize = 15.sp)
            Text(detail, color = ONTColors.inkSoft(theme), fontSize = 12.sp)
        }
    }
}
