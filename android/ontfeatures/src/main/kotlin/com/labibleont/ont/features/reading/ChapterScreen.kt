package com.labibleont.ont.features.reading

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.foundation.layout.Box
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
import com.labibleont.ont.designsystem.text.pointille
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
import com.labibleont.ont.designsystem.typography.ONTProse
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.withStyle
import com.labibleont.ont.designsystem.surfaces.GoldRule
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.Icon
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.ui.Alignment
import com.labibleont.ont.designsystem.surfaces.SectionCaption
import com.labibleont.ont.designsystem.metrics.ontSpacing
import com.labibleont.ont.kit.corpus.Footer
import com.labibleont.ont.kit.corpus.Inline

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
    /** Le nom propre touché — voir `Inline.Shem`. */
    onShem: (String) -> Unit = {},
    /** Les versets désignés — vide quand le lecteur lit sans rien viser. */
    selection: Set<Int> = emptySet(),
    onVerset: (Int) -> Unit = {},
    /** La couleur posée par le lecteur sur un verset, s'il y en a une. */
    marque: (Int) -> HighlightColor? = { null },
    /**
     * Le verset en tête d'écran quand le défilement s'arrête.
     *
     * Appelé pour la reprise, jamais pendant le geste : on retient où le
     * lecteur *s'est posé*, pas tout ce qu'il a survolé en chemin.
     */
    onPositionLue: (Int) -> Unit = {},
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
    val etatListe = androidx.compose.foundation.lazy.rememberLazyListState()

    // ## Le suivi de lecture
    //
    // iOS retient le verset le plus haut visible **quand le défilement
    // s'arrête**, et seulement si le lecteur a fait défiler quelque chose. Le
    // détail du procédé et ce qu'il répare sont dans `SuiviDeLecture`.
    val suivi = remember(chapitre.id) { SuiviDeLecture() }
    var fenetre by remember { mutableStateOf(0f to 0f) }

    LaunchedEffect(etatListe, chapitre.id) {
        snapshotFlow { etatListe.isScrollInProgress }.collect { enCours ->
            if (enCours) {
                suivi.defile()
                return@collect
            }
            suivi.aRetenir(fenetre.first, fenetre.second)?.let(onPositionLue)
        }
    }

    LazyColumn(
        state = etatListe,
        // La mesure est bornée, et les marges suivent le curseur
        // d'accessibilité. Au-delà de cette largeur, l'œil ne retrouve plus le
        // début de la ligne suivante — ça vaut surtout sur tablette, où rien ne
        // limiterait sinon.
        modifier = modifier
            .fillMaxWidth()
            .widthIn(max = com.labibleont.ont.designsystem.metrics.ONTLayout.readingWidth)
            // La fenêtre de lecture, en coordonnées de la racine — c'est à elle
            // que les bornes des versets sont comparées.
            .onGloballyPositioned { cadre ->
                val boite = cadre.boundsInRoot()
                fenetre = boite.top to boite.bottom
            },
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
                onShem = onShem,
                selection = selection,
                onVerset = onVerset,
                marque = marque,
                suivi = suivi,
            )
        }

        chapitre.footer?.let { pied ->
            item { PiedDUnite(pied, typo, preferences) }
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
            // ## Annoncé comme un titre, pas comme du texte
            //
            // TalkBack propose de sauter d'en-tête en en-tête. Sans cette
            // marque, un lecteur non-voyant traverse un chapitre entier
            // linéairement — quatre cents versets pour atteindre l'intertitre
            // suivant. Le geste existe dans le système ; il faut seulement lui
            // dire où sont les têtes.
            modifier = Modifier.fillMaxWidth().semantics { heading() },
        )
        chapitre.subtitle?.let { sous ->
            Spacer(Modifier.height(6.dp))
            // ## Le pont de navigation, dans ses trois écritures
            //
            // Le nom français, le nom hébreu, et le renvoi biblique — jamais la
            // désignation principale, qui est le titre juste au-dessus.
            //
            // L'hébreu était **absent** côté Android : le sous-titre ne
            // joignait que le français et le renvoi. Or c'est le seul endroit
            // de l'écran où le nom hébreu de l'unité paraît, et le laisser
            // tomber revenait à publier une liseuse de l'ONT qui tait l'hébreu
            // de son titre.
            //
            // Trois écritures, trois fontes : l'italique dit que le français
            // est une glose du nom, Ezra SIL porte le niqqud à sa place — une
            // fonte système le décrocherait de sa consonne —, et les chiffres à
            // chasse fixe alignent le renvoi.
            Text(
                buildAnnotatedString {
                    withStyle(SpanStyle(fontStyle = FontStyle.Italic)) {
                        append(sous.french)
                    }
                    if (sous.hebrew.isNotBlank()) {
                        append(" ")
                        withStyle(
                            SpanStyle(
                                fontFamily = ONTFonts.hebrew,
                                fontSize = (typo.size * 0.8f * ONTFonts.HEBREW_SCALE).sp,
                            ),
                        ) { append(sous.hebrew) }
                    }
                    sous.reference?.let {
                        append(" ")
                        withStyle(
                            SpanStyle(
                                fontFeatureSettings = "tnum",
                            ),
                        ) { append(it) }
                    }
                },
                fontSize = (typo.size * 0.8f).sp,
                // La même encre que sur iOS : l'encre du corps à 60 %, et non
                // le jeton d'encre douce. Les deux se ressemblent sur le
                // parchemin et divergent sur la nuit.
                color = ONTColors.ink(theme).copy(alpha = 0.6f),
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
    /** Le nom propre touché — voir `Inline.Shem`. */
    onShem: (String) -> Unit = {},
    selection: Set<Int> = emptySet(),
    onVerset: (Int) -> Unit = {},
    marque: (Int) -> HighlightColor? = { null },
    /** Où chaque verset se trouve à l'écran, pour la reprise de lecture. */
    suivi: SuiviDeLecture? = null,
) {
    val theme = LocalReadingTheme.current
    // L'interligne est un multiple de la taille du corps, comme sur iOS : un
    // interligne en points absolus ne suivrait pas le curseur d'accessibilité,
    // et le texte se resserrerait à mesure qu'on l'agrandit.
    val interligne = interligne(preferences.lineSpacing).em

    when (bloc) {
        is Block.Heading -> Column(
            Modifier.padding(top = 22.dp, bottom = 8.dp).semantics { heading() },
        ) {
            Text(
                ONTTextRenderer.compose(
                    bloc.nodes, typo,
                    showGloss = preferences.showGloss,
                    showLevel3 = preferences.showLevel3,
                ),
                style = ONTProse.francaise.copy(
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
            val pointille2 = ONTColors.accent(theme).copy(alpha = 0.8f)

            // Quand la liste met ce bloc au rebut, ses versets quittent l'écran
            // sans que rien ne le dise : `onGloballyPositioned` cesse simplement
            // de parler. On le dit ici, sinon leurs bornes restent figées dans
            // la fenêtre et le premier verset gagne pour toujours.
            if (suivi != null) {
                DisposableEffect(bloc) {
                    onDispose { suivi.oublier(bloc.verses.map { it.n }) }
                }
            }

            if (preferences.continuous) {
                // Un seul texte pour que les lignes se lient. La désignation et
                // le surlignage y passent par des fragments — voir le rendu.
                var mise by remember { mutableStateOf<TextLayoutResult?>(null) }
                val plages = remember(bloc, selection, preferences) { mutableMapOf<Int, IntRange>() }
                // Où commence chaque verset dans le texte réuni. C'est ce qui
                // permet de lire ses bornes **réelles** dans la mise en page,
                // là où iOS doit les estimer au prorata des signes affichés.
                val ancres = remember(bloc, preferences) { mutableMapOf<Int, Int>() }
                var hautDuTexte by remember { mutableStateOf(0f) }

                LaunchedEffect(mise, hautDuTexte, suivi) {
                    val pose = mise ?: return@LaunchedEffect
                    val ou = suivi ?: return@LaunchedEffect
                    val dernier = pose.layoutInput.text.length - 1
                    for ((verset, offset) in ancres) {
                        val premiere = pose.getLineForOffset(offset.coerceAtMost(dernier))
                        val derniere = pose.getLineForOffset(
                            (plages[verset]?.last ?: offset).coerceIn(0, dernier),
                        )
                        ou.situer(
                            verset,
                            hautDuTexte + pose.getLineTop(premiere),
                            hautDuTexte + pose.getLineBottom(derniere),
                        )
                    }
                }

                // ## Pourquoi ce texte est mémorisé
                //
                // Il était rebâti à **chaque recomposition**. En prose
                // continue, un bloc est une section entière : des centaines de
                // fragments, chacun avec son style, ses annotations de lien et
                // son fond de surlignage. Reconstruire tout ça pendant un
                // défilement mettait le fil d'interface à 250 ms par image,
                // pour 16 ms cibles — le GPU, lui, était à 4 ms.
                //
                // Les clés sont exactement ce dont le texte dépend. `marques`
                // en fait partie parce qu'un surlignage change les fonds sans
                // changer le bloc : une liste de valeurs comparables suffit à
                // le rendre visible, là où la lambda `marque` ne le serait pas.
                val marques = bloc.verses.map { marque(it.n) }
                val texte = remember(bloc, typo, preferences, selection, marques, theme) {
                    plages.clear()
                    ancres.clear()
                    androidx.compose.ui.text.buildAnnotatedString {
                    for (verset in bloc.verses) {
                        val debut = length
                        append(
                            ONTTextRenderer.composeVerse(
                                verset, typo,
                                showGloss = preferences.showGloss,
                                showLevel3 = preferences.showLevel3,
                                onTerme = onTerme,
                onShem = onShem,
                                onVerset = onVerset,
                                fond = fondDe(marque(verset.n)),
                                estompe = selection.isNotEmpty() && verset.n !in selection,
                                fondDuTheme = ONTColors.background(theme),
                            ),
                        )
                        // Le corps commence après le numéro : celui-ci est en
                        // exposant, et un pointillé qui le rejoindrait ferait
                        // un décroché à chaque début de verset.
                        plages[verset.n] = (debut + "${verset.n} ".length) until length
                        // L'ancre vise le **numéro**, pas le corps : c'est là
                        // que le verset commence à l'œil.
                        ancres[verset.n] = debut
                        // Une espace pleine entre deux versets, jamais un
                        // retour à la ligne : c'est toute la différence entre
                        // les deux modes.
                        append(" ")
                    }
                    }
                }

                // Le texte et son pointillé sont **deux nœuds de dessin**.
                //
                // Posé sur la chaîne du `Text`, le pointillé partageait son
                // nœud : l'invalider réenregistrait aussi les glyphes, et sur
                // une section haute de plusieurs écrans ça coûtait 48 ms par
                // image en défilant avec une sélection — pour 16 ms de budget.
                // Un `Canvas` frère se redessine seul.
                Box {
                    Text(
                        texte,
                        style = ONTProse.francaise.copy(lineHeight = interligne),
                        onTextLayout = { mise = it },
                        modifier = Modifier
                            // `positionInRoot` et non `boundsInRoot` : le
                            // second **rogne** aux limites visibles, si bien
                            // qu'un bloc à moitié sorti par le haut se déclare
                            // au bord de la fenêtre. Tous ses versets
                            // paraissaient alors visibles, et le plus petit
                            // numéro gagnait — c'est-à-dire celui qu'on venait
                            // justement de quitter.
                            .onGloballyPositioned { hautDuTexte = it.positionInRoot().y },
                    )
                    if (selection.isNotEmpty()) {
                        val aSouligner = selection.mapNotNull { plages[it] }
                        androidx.compose.foundation.Canvas(Modifier.matchParentSize()) {
                            pointille(mise, aSouligner, pointille2)
                        }
                    }
                }
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
                onShem = onShem,
                        fond = fondDe(marque(verset.n)),
                    )
                    Text(
                        texte,
                        style = ONTProse.francaise.copy(lineHeight = interligne),
                        onTextLayout = { mise = it },
                        modifier = Modifier
                            .onGloballyPositioned { cadre ->
                                // Non rogné — voir la note du mode continu.
                                val haut = cadre.positionInRoot().y
                                suivi?.situer(verset.n, haut, haut + cadre.size.height)
                            }
                            // `Modifier.alpha` et non une couleur : il efface
                            // le verset **entier**, l'or des intraduisibles et
                            // l'encre douce des gloses comprises.
                            .alpha(if (estompe) ONTColors.DIMMED_OPACITY else 1f)
                            .soulignerEnPointille(
                                layout = mise,
                                plages = if (designe) {
                                    listOf("${verset.n} ".length until texte.text.length)
                                } else {
                                    emptyList()
                                },
                                couleur = pointille2,
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
                onShem = onShem,
            ),
            style = ONTProse.francaise.copy(lineHeight = interligne),
            modifier = Modifier.padding(vertical = 6.dp),
        )

        is Block.Quote -> Text(
            ONTTextRenderer.compose(
                bloc.nodes, typo,
                showGloss = preferences.showGloss,
                showLevel3 = preferences.showLevel3,
                onTerme = onTerme,
                onShem = onShem,
            ),
            style = ONTProse.francaise.copy(lineHeight = interligne),
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
                onShem = onShem,
                            ),
                        )
                    },
                    style = ONTProse.francaise.copy(lineHeight = interligne),
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

        // Le filet du Ḥurban — **en or**, pas en séparateur gris.
        //
        // Ce n'est pas un trait de mise en page : c'est une césure du texte,
        // qui marque une rupture dans le corpus. Le rendre en gris comme les
        // séparateurs d'interface le faisait passer pour du mobilier.
        //
        // `GoldRule` existait dans le design system depuis le début — il ne
        // servait qu'au catalogue. Le filet le plus discuté du projet était
        // dessiné, disponible, et jamais posé là où il compte.
        Block.Rule -> GoldRule(
            opacite = 0.6f,
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

/**
 * Le pied d'unité — version, verrouillage, décisions terminologiques.
 *
 * ## Ce qu'il porte, et pourquoi ce n'est pas du mobilier
 *
 * Les décisions terminologiques sont du **texte éditorial** : elles disent
 * pourquoi tel mot a été rendu ainsi et pas autrement. Un lecteur qui bute sur
 * un choix de traduction y trouve sa raison. Les taire — ce que faisait
 * Android — revient à publier la traduction sans ses attendus.
 *
 * Le filet d'or les annonce, comme sur iOS : ce qui suit n'appartient plus au
 * corpus.
 */
@Composable
private fun PiedDUnite(pied: Footer, typo: ONTTypography, preferences: ReadingPreferences) {
    val theme = LocalReadingTheme.current
    val espace = ontSpacing
    Column(
        modifier = Modifier.fillMaxWidth().padding(top = espace.m),
        verticalArrangement = Arrangement.spacedBy(espace.m),
    ) {
        GoldRule()

        Row(
            horizontalArrangement = Arrangement.spacedBy(espace.xs),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                if (pied.locked) Icons.Filled.Lock else Icons.Filled.Edit,
                contentDescription = null,
                tint = ONTColors.accent(theme),
                modifier = Modifier.size(espace(14)),
            )
            Text(
                buildString {
                    append(if (pied.locked) "Verrouillée" else "À valider")
                    pied.version?.let { append(" · Version ").append(it) }
                },
                fontSize = 12.sp,
                color = ONTColors.accent(theme),
            )
        }

        if (pied.notes.isNotEmpty()) {
            SectionCaption("Décisions terminologiques")
            pied.notes.forEach { note ->
                Text(
                    ONTTextRenderer.compose(
                        aplatir(note),
                        typo,
                        showGloss = preferences.showGloss,
                        showLevel3 = preferences.showLevel3,
                    ),
                    style = ONTProse.francaise.copy(
                        fontSize = (typo.size * 0.82f).sp,
                        color = ONTColors.inkSoft(theme),
                    ),
                )
            }
        }
    }
}

/**
 * Les nœuds d'un bloc de note, à plat.
 *
 * Une note est un bloc comme un autre, mais elle se rend d'une traite : ni
 * titre, ni puces, ni tableau. On en tire donc le texte, et le reste tombe.
 */
private fun aplatir(bloc: Block): List<Inline> = when (bloc) {
    is Block.Paragraph -> bloc.nodes
    is Block.Heading -> bloc.nodes
    is Block.Quote -> bloc.nodes
    // Un retour à la ligne **entre** les entrées, jamais après la dernière.
    //
    // `flatten()` seul les collait bout à bout : « laissé en hébreu*Ruach »
    // au lieu de deux décisions distinctes. Une liste de décisions
    // terminologiques lue d'un seul tenant ne se lit pas — c'est précisément
    // ce qui la rend consultable qui disparaissait.
    is Block.List -> bloc.items.flatMapIndexed { i, item ->
        if (i == 0) item else listOf(Inline.LineBreak) + item
    }
    else -> emptyList()
}
