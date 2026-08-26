package com.labibleont.ont.features.reading

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.foundation.clickable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.TextLayoutResult
import com.labibleont.ont.designsystem.text.ONTTextRenderer
import com.labibleont.ont.designsystem.text.soulignerEnPointille
import com.labibleont.ont.designsystem.theme.LocalReadingTheme
import com.labibleont.ont.designsystem.tokens.ONTColors
import com.labibleont.ont.designsystem.typography.ONTFonts
import com.labibleont.ont.designsystem.typography.ONTTypography
import com.labibleont.ont.kit.corpus.Block
import com.labibleont.ont.kit.corpus.Chapter
import com.labibleont.ont.kit.corpus.fusingConsecutiveVerses
import com.labibleont.ont.kit.reader.HighlightColor
import com.labibleont.ont.kit.reader.ReadingPreferences
import com.labibleont.ont.designsystem.typography.interligne

/**
 * La lecture d'une unité.
 *
 * ## Deux façons de lire, pas deux goûts
 *
 * En **prose continue**, les versets consécutifs sont réunis avant d'être
 * composés : c'est la lecture suivie, où la découpe en versets est un artefact
 * du XIIIᵉ siècle qui hache une phrase en trois. En **blocs**, chaque verset se
 * tient seul — c'est l'étude, où l'on vise, on annote, on compare.
 *
 * La réunion se fait dans le domaine (`fusingConsecutiveVerses`) et non ici :
 * c'est une question de texte, pas d'affichage. Côté iOS, l'avoir mise dans la
 * vue rendait le mode inopérant partout où le corpus ne groupait pas déjà —
 * 504 blocs d'un seul verset contre 109 qui en groupent plusieurs. Rien ne le
 * signalait : le réglage s'enregistrait, la branche s'exécutait, le rendu ne
 * changeait pas d'un pixel.
 */
@Composable
public fun ChapterScreen(
    chapitre: Chapter,
    preferences: ReadingPreferences,
    onTerme: (String) -> Unit,
    /** Les versets désignés — vide quand le lecteur lit sans rien viser. */
    selection: Set<Int> = emptySet(),
    onVerset: (Int) -> Unit = {},
    /** La couleur posée par le lecteur sur un verset, s'il y en a une. */
    marque: (Int) -> HighlightColor? = { null },
    modifier: Modifier = Modifier,
) {
    val theme = LocalReadingTheme.current
    val typo = ONTTypography(
        size = preferences.textSize.toFloat(),
        theme = theme,
        face = preferences.bodyFont,
    )
    val blocs = if (preferences.continuous) {
        chapitre.blocks.fusingConsecutiveVerses()
    } else {
        chapitre.blocks
    }

    val espace = com.labibleont.ont.designsystem.metrics.ontSpacing

    LazyColumn(
        // La mesure est bornée, et les marges suivent le curseur
        // d'accessibilité. Au-delà de cette largeur, l'œil ne retrouve plus le
        // début de la ligne suivante — ça vaut surtout sur tablette, où rien ne
        // limiterait sinon.
        modifier = modifier
            .fillMaxWidth()
            .widthIn(max = com.labibleont.ont.designsystem.metrics.ONTLayout.readingWidth),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(
            start = espace.page,
            end = espace.page,
            top = espace.m,
            bottom = espace(48),
        ),
    ) {
        item { EnTete(chapitre, typo) }

        itemsIndexed(blocs) { bloc ->
            BlocDeTexte(
                bloc = bloc,
                typo = typo,
                preferences = preferences,
                onTerme = onTerme,
                selection = selection,
                onVerset = onVerset,
                marque = marque,
            )
        }
    }
}

/** `items` avec index, sans clé — les blocs n'ont pas d'identité stable. */
private fun androidx.compose.foundation.lazy.LazyListScope.itemsIndexed(
    blocs: kotlin.collections.List<Block>,
    contenu: @Composable (Block) -> Unit,
) {
    items(blocs.size) { i -> contenu(blocs[i]) }
}

/**
 * Le titre de l'unité et son sous-titre de référence.
 *
 * Le renvoi biblique — « Genèse 18:1-33 » — est la **seule** trace de la
 * numérotation d'origine. L'ONT découpe en unités fonctionnelles : un bloc se
 * clôt quand une fonction cosmique est accomplie, pas quand un numéro change.
 * Sans ce sous-titre, un lecteur venu d'une autre Bible ne saurait pas où il
 * est.
 */
@Composable
private fun EnTete(chapitre: Chapter, typo: ONTTypography) {
    val theme = LocalReadingTheme.current
    Column(modifier = Modifier.fillMaxWidth().padding(bottom = 20.dp)) {
        Text(
            chapitre.title,
            fontFamily = ONTFonts.display,
            fontSize = (typo.size * 1.7f).sp,
            color = ONTColors.inkStrong(theme),
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )
        chapitre.subtitle?.let { sous ->
            Spacer(Modifier.height(6.dp))
            Text(
                listOfNotNull(sous.french, sous.reference).joinToString(" "),
                fontSize = (typo.size * 0.8f).sp,
                color = ONTColors.inkSoft(theme),
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        Spacer(Modifier.height(14.dp))
        HorizontalDivider(color = ONTColors.separator(theme))
    }
}

@Composable
private fun BlocDeTexte(
    bloc: Block,
    typo: ONTTypography,
    preferences: ReadingPreferences,
    onTerme: (String) -> Unit,
    selection: Set<Int> = emptySet(),
    onVerset: (Int) -> Unit = {},
    marque: (Int) -> HighlightColor? = { null },
) {
    val theme = LocalReadingTheme.current
    // L'interligne est un multiple de la taille du corps, comme sur iOS : un
    // interligne en points absolus ne suivrait pas le curseur d'accessibilité,
    // et le texte se resserrerait à mesure qu'on l'agrandit.
    val interligne = interligne(preferences.lineSpacing).em

    when (bloc) {
        is Block.Heading -> Column(Modifier.padding(top = 22.dp, bottom = 8.dp)) {
            Text(
                ONTTextRenderer.compose(
                    bloc.nodes, typo,
                    showGloss = preferences.showGloss,
                    showLevel3 = preferences.showLevel3,
                ),
                style = androidx.compose.ui.text.TextStyle(
                    lineHeight = interligne,
                    color = ONTColors.brandInk(theme),
                    fontFamily = ONTFonts.display,
                    fontSize = (typo.size * 1.25f).sp,
                ),
            )
        }

        is Block.Verses -> Column(
            // L'écart entre deux versets suit le corps **et** le réglage
            // d'interligne, comme sur iOS — `scaledTextSize × lineSpacing`.
            // Figé à 10 dp, il se refermait à mesure qu'on grossissait le
            // texte : à 34 pt, iOS respire de 17 points là où Android en
            // gardait 10, et les versets finissaient par se toucher.
            verticalArrangement = Arrangement.spacedBy(
                (preferences.textSize * preferences.lineSpacing).dp,
            ),
            modifier = Modifier.padding(vertical = 4.dp),
        ) {
            // En prose continue, le bloc réuni ne contient qu'un enchaînement :
            // on le compose d'un seul tenant pour que les lignes se lient.
            val pointille = ONTColors.accent(theme).copy(alpha = 0.8f)

            if (preferences.continuous) {
                // Un seul texte pour que les lignes se lient. La désignation et
                // le surlignage y passent par des fragments — voir le rendu.
                var mise by remember { mutableStateOf<TextLayoutResult?>(null) }
                val plages = remember(bloc, selection, preferences) { mutableMapOf<Int, IntRange>() }

                val texte = androidx.compose.ui.text.buildAnnotatedString {
                    for (verset in bloc.verses) {
                        val debut = length
                        append(
                            ONTTextRenderer.composeVerse(
                                verset, typo,
                                showGloss = preferences.showGloss,
                                showLevel3 = preferences.showLevel3,
                                onTerme = onTerme,
                                onVerset = onVerset,
                                fond = fondDe(marque(verset.n)),
                                estompe = selection.isNotEmpty() && verset.n !in selection,
                                fondDuTheme = ONTColors.background(theme),
                            ),
                        )
                        // Le corps commence après le numéro : celui-ci est en
                        // exposant, et un pointillé qui le rejoindrait ferait
                        // un décroché à chaque début de verset.
                        plages[verset.n] = (debut + "${'$'}{verset.n} ".length) until length
                        // Une espace pleine entre deux versets, jamais un
                        // retour à la ligne : c'est toute la différence entre
                        // les deux modes.
                        append(" ")
                    }
                }

                Text(
                    texte,
                    style = androidx.compose.ui.text.TextStyle(lineHeight = interligne),
                    onTextLayout = { mise = it },
                    modifier = Modifier.soulignerEnPointille(
                        layout = { mise },
                        plages = { selection.mapNotNull { plages[it] } },
                        couleur = pointille,
                    ),
                )
            } else {
                for (verset in bloc.verses) {
                    val estompe = selection.isNotEmpty() && verset.n !in selection
                    val designe = verset.n in selection
                    var mise by remember(verset.n) { mutableStateOf<TextLayoutResult?>(null) }
                    val texte = ONTTextRenderer.composeVerse(
                        verset, typo,
                        showGloss = preferences.showGloss,
                        showLevel3 = preferences.showLevel3,
                        onTerme = onTerme,
                        fond = fondDe(marque(verset.n)),
                    )
                    Text(
                        texte,
                        style = androidx.compose.ui.text.TextStyle(lineHeight = interligne),
                        onTextLayout = { mise = it },
                        modifier = Modifier
                            // `Modifier.alpha` et non une couleur : il efface
                            // le verset **entier**, l'or des intraduisibles et
                            // l'encre douce des gloses comprises.
                            .alpha(if (estompe) ONTColors.DIMMED_OPACITY else 1f)
                            .soulignerEnPointille(
                                layout = { mise },
                                plages = {
                                    if (designe) {
                                        listOf("${'$'}{verset.n} ".length until texte.text.length)
                                    } else {
                                        emptyList()
                                    }
                                },
                                couleur = pointille,
                            )
                            .clickable { onVerset(verset.n) },
                    )
                }
            }
        }

        is Block.Paragraph -> Text(
            ONTTextRenderer.compose(
                bloc.nodes, typo,
                showGloss = preferences.showGloss,
                showLevel3 = preferences.showLevel3,
                onTerme = onTerme,
            ),
            style = androidx.compose.ui.text.TextStyle(lineHeight = interligne),
            modifier = Modifier.padding(vertical = 6.dp),
        )

        is Block.Quote -> Text(
            ONTTextRenderer.compose(
                bloc.nodes, typo,
                showGloss = preferences.showGloss,
                showLevel3 = preferences.showLevel3,
                onTerme = onTerme,
            ),
            style = androidx.compose.ui.text.TextStyle(lineHeight = interligne),
            modifier = Modifier.padding(start = 16.dp, top = 8.dp, bottom = 8.dp),
        )

        is Block.List -> Column(Modifier.padding(vertical = 6.dp)) {
            bloc.items.forEachIndexed { i, item ->
                Text(
                    androidx.compose.ui.text.buildAnnotatedString {
                        append(if (bloc.ordered) "${i + 1}. " else "• ")
                        append(
                            ONTTextRenderer.compose(
                                item, typo,
                                showGloss = preferences.showGloss,
                                showLevel3 = preferences.showLevel3,
                                onTerme = onTerme,
                            ),
                        )
                    },
                    style = androidx.compose.ui.text.TextStyle(lineHeight = interligne),
                    modifier = Modifier.padding(start = 8.dp, bottom = 4.dp),
                )
            }
        }

        is Block.Table -> Column(Modifier.padding(vertical = 8.dp)) {
            // Un tableau du lexique — rare, et jamais large. On empile les
            // cellules plutôt que d'imposer un défilement horizontal, qui sur
            // téléphone se dispute toujours avec le geste de page.
            for (ligne in bloc.rows) {
                Text(
                    ligne.joinToString("  ·  ") {
                        ONTTextRenderer.compose(
                            it, typo,
                            showGloss = preferences.showGloss,
                            showLevel3 = preferences.showLevel3,
                        ).text
                    },
                    fontSize = (typo.size * 0.9f).sp,
                    color = ONTColors.ink(theme),
                    modifier = Modifier.padding(bottom = 4.dp),
                )
            }
        }

        Block.Rule -> HorizontalDivider(
            color = ONTColors.separator(theme),
            modifier = Modifier.padding(vertical = 18.dp),
        )
    }
}

/**
 * La teinte réelle d'une marque, avec son opacité.
 *
 * Le domaine ne connaît que le nom de la couleur ; la valeur vit dans le design
 * system, ce qui permet de retoucher la palette sans migrer les surlignages
 * déjà enregistrés chez les lecteurs.
 */
private fun fondDe(couleur: HighlightColor?): androidx.compose.ui.graphics.Color? =
    couleur?.let {
        ONTColors.highlight(it).copy(alpha = ONTColors.HIGHLIGHT_OPACITY)
    }
