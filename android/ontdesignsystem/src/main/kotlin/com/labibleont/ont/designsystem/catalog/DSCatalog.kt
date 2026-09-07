package com.labibleont.ont.designsystem.catalog

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.labibleont.ont.designsystem.metrics.ONTRadius
import com.labibleont.ont.designsystem.metrics.ontSpacing
import com.labibleont.ont.designsystem.surfaces.BurgundyCard
import com.labibleont.ont.designsystem.surfaces.GoldRule
import com.labibleont.ont.designsystem.surfaces.ONTGroup
import com.labibleont.ont.designsystem.surfaces.ONTGroupDivider
import com.labibleont.ont.designsystem.surfaces.ONTPage
import com.labibleont.ont.designsystem.surfaces.ONTRow
import com.labibleont.ont.designsystem.surfaces.ONTSectionHeader
import com.labibleont.ont.designsystem.surfaces.QuietBlock
import com.labibleont.ont.designsystem.surfaces.SectionCaption
import com.labibleont.ont.designsystem.surfaces.StatusPill
import com.labibleont.ont.designsystem.text.ONTTextRenderer
import com.labibleont.ont.designsystem.theme.LocalReadingTheme
import com.labibleont.ont.designsystem.theme.ONTTheme
import com.labibleont.ont.designsystem.tokens.ONTColors
import com.labibleont.ont.designsystem.typography.ONTFonts
import com.labibleont.ont.designsystem.typography.ONTTypography
import com.labibleont.ont.kit.corpus.Inline
import com.labibleont.ont.kit.reader.HighlightColor
import com.labibleont.ont.kit.reader.ReadingFont
import com.labibleont.ont.kit.reader.ReadingTheme

/**
 * Le catalogue du design system.
 *
 * ## Ce n'est pas une vitrine, c'est un contrôle
 *
 * Chaque jeton et chaque composant a sa section. **Un composant ajouté sans sa
 * ligne de catalogue est un composant qu'on oubliera** — l'ajouter dans le même
 * commit.
 *
 * Ce qu'il attrape, et qu'aucun test ne dit :
 *
 * - une **teinte qui a dérivé** — les quatre thèmes sont côte à côte, et un
 *   contraste qui s'écroule sur l'un des quatre se voit à l'œil avant de se
 *   mesurer ;
 * - une **fonte qui ne s'est pas chargée** — Android retombe silencieusement
 *   sur la fonte système, et un texte en Roboto au lieu de Literata ne lève
 *   aucune erreur. La section des fontes les rend toutes ensemble : une ligne
 *   qui ne ressemble pas aux autres est une fonte absente ;
 * - un **rendu de texte cassé** — les trois niveaux, le nœud d'hébreu, le
 *   surlignage, tous rendus sur un exemple fabriqué, sans dépendre du corpus.
 *
 * Côté iOS il vit dans l'onglet « Vous » en build de développement. Ici de
 * même.
 */
@Composable
public fun DSCatalog(modifier: Modifier = Modifier) {
    val espace = ontSpacing

    Column(modifier = modifier.fillMaxWidth().verticalScroll(rememberScrollState())) {
        ONTPage {
            ONTSectionHeader("Les quatre peaux")
            for (t in ReadingTheme.entries) {
                EchantillonDeTheme(t)
                Spacer(Modifier.height(espace.m))
            }

            Spacer(Modifier.height(espace.xl))
            ONTSectionHeader("Les surfaces")
            SectionSurfaces()

            Spacer(Modifier.height(espace.xl))
            ONTSectionHeader("Les fontes embarquées")
            SectionFontes()

            Spacer(Modifier.height(espace.xl))
            ONTSectionHeader("Le rendu des trois niveaux")
            SectionRendu()

            Spacer(Modifier.height(espace.xl))
            ONTSectionHeader("Les surlignages")
            SectionSurlignages()

            Spacer(Modifier.height(espace.xl))
            ONTSectionHeader("L'espacement et les rayons")
            SectionMetriques()

            Spacer(Modifier.height(espace.xxl))
        }
    }
}

/**
 * Un thème, avec ses rôles de couleur les uns à côté des autres.
 *
 * Rendu **dans** son propre thème et non dans celui de l'app : c'est la seule
 * façon de voir les quatre en même temps, et donc de repérer celui où un
 * contraste s'écroule.
 */
@Composable
private fun EchantillonDeTheme(t: ReadingTheme) {
    val espace = ontSpacing
    ONTTheme(theme = t) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(ONTRadius.block))
                .background(ONTColors.background(t))
                .padding(espace.m),
        ) {
            Text(
                t.label,
                fontFamily = ONTFonts.display,
                fontSize = 17.sp,
                color = ONTColors.inkStrong(t),
            )
            Spacer(Modifier.height(espace.s))
            Row(horizontalArrangement = Arrangement.spacedBy(espace.xs)) {
                Pastille("fond", ONTColors.background(t))
                Pastille("surface", ONTColors.surface(t))
                Pastille("encre", ONTColors.ink(t))
                Pastille("douce", ONTColors.inkSoft(t))
                Pastille("marque", ONTColors.brandInk(t))
                Pastille("accent", ONTColors.accent(t))
                Pastille("accentu.", ONTColors.accentuation(t))
            }
            Spacer(Modifier.height(espace.s))
            Text(
                "Le corps, la glose et l'accentuation sur ce fond.",
                color = ONTColors.ink(t),
                fontSize = 14.sp,
            )
            Text(
                "Le niveau 2, plus doux, qui doit reculer sans disparaître.",
                color = ONTColors.inkSoft(t),
                fontSize = 13.sp,
            )
            Text(
                "Une accentuation, ni corps ni intraduisible.",
                color = ONTColors.accentuation(t),
                fontWeight = FontWeight.SemiBold,
                fontSize = 14.sp,
            )
        }
    }
}

@Composable
private fun Pastille(nom: String, couleur: Color) {
    val theme = LocalReadingTheme.current
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            modifier = Modifier
                .size(28.dp)
                .clip(RoundedCornerShape(6.dp))
                .background(couleur)
                .border(1.dp, ONTColors.separator(theme), RoundedCornerShape(6.dp)),
        )
        Text(nom, fontSize = 9.sp, color = ONTColors.inkSoft(theme))
    }
}

@Composable
private fun SectionSurfaces() {
    val espace = ontSpacing
    Column(verticalArrangement = Arrangement.spacedBy(espace.m)) {
        BurgundyCard {
            Text("BurgundyCard", color = ONTColors.gold, fontSize = 16.sp)
            Text(
                "Le seul emploi du bordeaux brut : un fond, avec de l'or dessus.",
                color = ONTColors.gold.copy(alpha = 0.85f),
                fontSize = 13.sp,
            )
        }
        QuietBlock {
            Text("QuietBlock", color = ONTColors.ink(LocalReadingTheme.current), fontSize = 16.sp)
            Text(
                "Un bloc secondaire, en retrait.",
                color = ONTColors.inkSoft(LocalReadingTheme.current),
                fontSize = 13.sp,
            )
        }
        ONTGroup {
            ONTRow(titre = "ONTRow", detail = "une ligne de groupe")
            ONTGroupDivider()
            ONTRow(titre = "Avec une valeur", fin = { Valeur("4 / 70") })
            ONTGroupDivider()
            ONTRow(titre = "Avec une pastille", fin = { StatusPill("brouillon") })
        }
        SectionCaption("SectionCaption en petites capitales")
        GoldRule()
    }
}

@Composable
private fun Valeur(texte: String) {
    Text(texte, color = ONTColors.inkSoft(LocalReadingTheme.current), fontSize = 15.sp)
}

/**
 * Les sept fontes, rendues ensemble.
 *
 * **C'est le contrôle le plus utile du catalogue.** Une fonte absente ne lève
 * rien : Android retombe sur la fonte système, et le texte s'affiche. Rendues
 * côte à côte, une ligne qui ne ressemble pas aux autres se repère
 * immédiatement — et « Georgia » doit en être une, puisqu'elle n'existe pas ici
 * et tombe volontairement sur la serif du système.
 */
@Composable
private fun SectionFontes() {
    val theme = LocalReadingTheme.current
    ONTGroup {
        ReadingFont.entries.forEachIndexed { i, f ->
            if (i > 0) ONTGroupDivider()
            Column(modifier = Modifier.padding(ontSpacing.l)) {
                Text(f.label, fontSize = 12.sp, color = ONTColors.inkSoft(theme))
                Text(
                    "Au commencement Elohim — 0123456789",
                    fontFamily = ONTFonts.family(f),
                    fontSize = 18.sp,
                    color = ONTColors.ink(theme),
                )
                Text(
                    "L'italique, qui porte la translittération.",
                    fontFamily = ONTFonts.family(f),
                    fontStyle = FontStyle.Italic,
                    fontSize = 15.sp,
                    color = ONTColors.inkSoft(theme),
                )
            }
        }
        ONTGroupDivider()
        Column(modifier = Modifier.padding(ontSpacing.l)) {
            Text("Ezra SIL — l'hébreu", fontSize = 12.sp, color = ONTColors.inkSoft(theme))
            Text(
                // Vocalisé exprès : si la fonte manque, le niqqud se décroche
                // de ses consonnes et ça se voit d'un coup d'œil.
                "בְּרֵאשִׁ֖ית בָּרָ֣א אֱלֹהִ֑ים",
                fontFamily = ONTFonts.hebrew,
                fontSize = 22.sp,
                color = ONTColors.ink(theme),
            )
        }
    }
}

/**
 * Les trois niveaux, sur un exemple fabriqué — sans dépendre du corpus.
 *
 * ## Les espaces viennent du texte, pas du moteur
 *
 * Le rendu n'insère **aucune** espace autour de l'appareil : les parenthèses du
 * niveau 3 et les crochets du niveau 2 sont collés à ce qui les précède. C'est
 * délibéré — le vault porte déjà sa ponctuation, et un moteur qui en ajouterait
 * doublerait les espaces partout.
 *
 * La première version de cet exemple les avait oubliées et rendait
 * « Elohim(elohim / אֱלֹהִים)[nom… », ce qui donnait l'impression d'un défaut
 * du moteur. Elles sont donc écrites ici comme le vault les écrit.
 */
@Composable
private fun SectionRendu() {
    val theme = LocalReadingTheme.current
    val typo = ONTTypography(size = 17f, theme = theme)
    val exemple = listOf(
        Inline.Text("Quand "),
        Inline.Term("Elohim", "elohim"),
        Inline.Text(" "),
        Inline.Translit("elohim", "אֱלֹהִים"),
        Inline.Text(" "),
        Inline.Gloss(listOf(Inline.Text("nom divin laissé intact"))),
        Inline.Text(" "),
        Inline.Accentuation(listOf(Inline.Text("commença"))),
        Inline.Text(" à orchestrer."),
    )

    QuietBlock {
        Text(
            ONTTextRenderer.compose(exemple, typo, showGloss = true, showLevel3 = true),
        )
        Spacer(Modifier.height(ontSpacing.s))
        SectionCaption("Le corps seul")
        Text(ONTTextRenderer.compose(exemple, typo, showGloss = false, showLevel3 = false))
    }
}

@Composable
private fun SectionSurlignages() {
    val theme = LocalReadingTheme.current
    QuietBlock {
        Row(horizontalArrangement = Arrangement.spacedBy(ontSpacing.s)) {
            for (c in HighlightColor.entries) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(
                        modifier = Modifier
                            .size(34.dp)
                            .clip(RoundedCornerShape(ONTRadius.highlight))
                            .background(
                                ONTColors.highlight(c, theme)
                                    .copy(alpha = ONTColors.HIGHLIGHT_OPACITY),
                            ),
                    )
                    Text(c.label, fontSize = 10.sp, color = ONTColors.inkSoft(theme))
                }
            }
        }
    }
}

@Composable
private fun SectionMetriques() {
    val theme = LocalReadingTheme.current
    val e = ontSpacing
    ONTGroup {
        listOf(
            "xs" to e.xs, "s" to e.s, "m" to e.m, "l" to e.l,
            "page" to e.page, "xl" to e.xl, "xxl" to e.xxl,
        ).forEachIndexed { i, (nom, valeur) ->
            if (i > 0) ONTGroupDivider()
            Row(
                modifier = Modifier.fillMaxWidth().padding(e.m),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    nom,
                    fontSize = 13.sp,
                    color = ONTColors.inkSoft(theme),
                    modifier = Modifier.width(48.dp),
                )
                Box(
                    modifier = Modifier
                        .width(valeur)
                        .height(10.dp)
                        .background(ONTColors.accent(theme)),
                )
            }
        }
    }
    Text(
        // La démonstration de la règle : monter le curseur système fait
        // grandir ces barres. Si elles ne bougent pas, l'échelle n'est plus
        // branchée.
        "Ces barres grandissent avec le curseur d'accessibilité du système. " +
            "Si elles restent figées quand vous le montez, l'échelle n'est plus " +
            "branchée — et les marges cesseront de suivre le texte.",
        fontSize = 12.sp,
        color = ONTColors.inkSoft(theme),
        modifier = Modifier.padding(ontSpacing.l),
    )
}
