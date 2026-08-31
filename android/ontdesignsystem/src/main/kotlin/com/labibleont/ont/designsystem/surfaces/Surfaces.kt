package com.labibleont.ont.designsystem.surfaces

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.labibleont.ont.designsystem.metrics.ONTLayout
import com.labibleont.ont.designsystem.metrics.ONTRadius
import com.labibleont.ont.designsystem.metrics.ontSpacing
import com.labibleont.ont.designsystem.theme.LocalReadingTheme
import com.labibleont.ont.designsystem.tokens.ONTColors
import com.labibleont.ont.designsystem.typography.ONTFonts
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics

/**
 * L'écran type de l'ONT.
 *
 * ## Pourquoi ce modificateur existe
 *
 * Sans lui, chaque écran hérite du fond que lui impose son conteneur, et l'app
 * finit avec quatre onglets qui ne se ressemblent pas alors même qu'un design
 * system est en place. C'est la règle du Swift, et elle vaut ici : **tout écran
 * de premier niveau le porte.**
 *
 * Le grain de la nuit se pose ici, et **seulement** ici : c'est le point unique
 * par lequel passe le fond de tous les écrans, donc le seul endroit où il ne
 * peut ni manquer quelque part, ni se superposer à lui-même et doubler son
 * opacité.
 */
@Composable
public fun Modifier.ontScreen(): Modifier {
    val theme = LocalReadingTheme.current
    return this
        .fillMaxSize()
        .background(ONTColors.background(theme))
        .then(ONTGrain.modifier(theme))
}

/**
 * La colonne de lecture — largeur bornée, marges d'aération.
 *
 * Au-delà d'une certaine largeur, l'œil ne retrouve plus le début de la ligne
 * suivante. La borne vaut surtout sur tablette, où rien ne limiterait sinon.
 *
 * Pas de grain ici : c'est la **colonne**, pas la page. Le grain s'arrêterait au
 * bord du texte, ce qui se verrait dès qu'un écran est plus large que la mesure.
 */
@Composable
public fun ParchmentPage(
    modifier: Modifier = Modifier,
    contenu: @Composable ColumnScope.() -> Unit,
) {
    val espace = ontSpacing
    Box(modifier = modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
        Column(
            modifier = Modifier
                .widthIn(max = ONTLayout.readingWidth)
                .fillMaxWidth()
                .padding(horizontal = espace.page, vertical = espace.l),
            content = contenu,
        )
    }
}

/**
 * La colonne d'une **page** — listes, cartes, réglages.
 *
 * Plus large que la mesure du texte suivi : une liste ne se lit pas comme une
 * phrase, l'œil y saute d'un intitulé à sa valeur.
 */
@Composable
public fun ONTPage(
    modifier: Modifier = Modifier,
    contenu: @Composable ColumnScope.() -> Unit,
) {
    val espace = ontSpacing
    Box(modifier = modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
        Column(
            modifier = Modifier
                .widthIn(max = ONTLayout.pageWidth)
                .fillMaxWidth()
                .padding(horizontal = espace.l),
            content = contenu,
        )
    }
}

/**
 * La carte bordeaux — le verset du jour, les mises en exergue.
 *
 * Elle garde la mesure qu'elle a sur téléphone : étalée, elle deviendrait une
 * bande où le verset ne tiendrait plus que sur deux lignes.
 */
@Composable
public fun BurgundyCard(
    modifier: Modifier = Modifier,
    contenu: @Composable ColumnScope.() -> Unit,
) {
    val espace = ontSpacing
    Column(
        modifier = modifier
            .widthIn(max = ONTLayout.cardWidth)
            .fillMaxWidth()
            .clip(RoundedCornerShape(ONTRadius.card))
            .background(ONTColors.burgundy)
            .padding(espace.page),
        content = contenu,
    )
}

/**
 * Un bloc secondaire, en retrait.
 *
 * Le fond est la surface du thème posée à faible opacité — sur parchemin, un
 * blanc pur détonnerait ; sur la nuit, un gris ferait sale.
 */
@Composable
public fun QuietBlock(
    modifier: Modifier = Modifier,
    contenu: @Composable ColumnScope.() -> Unit,
) {
    val theme = LocalReadingTheme.current
    val espace = ontSpacing
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(ONTRadius.block))
            .background(ONTColors.surface(theme))
            .padding(espace.l),
        content = contenu,
    )
}

/**
 * Un groupe de lignes, encarté.
 *
 * ## Ce que ça remplace, et pourquoi il fallait l'écrire
 *
 * iOS l'obtient gratuitement : un `Form` ou une `List(.insetGrouped)` dessine
 * des surfaces arrondies qui portent leurs lignes, avec des filets qui ne
 * touchent pas les bords. C'est ce qui donne aux réglages leur aspect fini.
 *
 * Compose n'a pas d'équivalent — une `LazyColumn` est une liste plate, et
 * `ListItem` de Material pose des lignes sur le fond de l'écran. Sans ce
 * composant, l'onglet Vous d'Android était une suite d'interrupteurs séparés
 * par des traits pleine largeur : lisible, mais pas dessiné.
 *
 * Le filet s'arrête aux marges intérieures, pas au bord de la carte : c'est le
 * détail qui distingue un groupe encarté d'une pile de lignes.
 */
@Composable
public fun ONTGroup(
    modifier: Modifier = Modifier,
    contenu: @Composable ColumnScope.() -> Unit,
) {
    val theme = LocalReadingTheme.current
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(ONTRadius.block))
            .background(ONTColors.surface(theme)),
        content = contenu,
    )
}

/** Le filet entre deux lignes d'un groupe — en retrait des bords. */
@Composable
public fun ONTGroupDivider(retrait: Boolean = true) {
    val theme = LocalReadingTheme.current
    val espace = ontSpacing
    HorizontalDivider(
        color = ONTColors.separator(theme),
        modifier = Modifier.padding(start = if (retrait) espace.l else 0.dp),
    )
}

/**
 * Une ligne d'un groupe.
 *
 * Icône à gauche, intitulé, et ce qui vient après à droite — une valeur, un
 * interrupteur, un chevron. La hauteur minimale de 48 dp est la cible tactile
 * qu'Android exige : en dessous, le doigt manque la ligne.
 */
@Composable
public fun ONTRow(
    titre: String,
    modifier: Modifier = Modifier,
    detail: String? = null,
    icone: ImageVector? = null,
    onClick: (() -> Unit)? = null,
    fin: @Composable (RowScope.() -> Unit)? = null,
) {
    val theme = LocalReadingTheme.current
    val espace = ontSpacing

    Row(
        modifier = modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .heightIn(min = 48.dp)
            .padding(horizontal = espace.l, vertical = espace.m),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        icone?.let {
            Icon(
                it,
                contentDescription = null,
                tint = ONTColors.brandInk(theme),
                modifier = Modifier.padding(end = espace.m),
            )
        }
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(titre, color = ONTColors.ink(theme), fontSize = 16.sp)
            detail?.let {
                Text(it, color = ONTColors.inkSoft(theme), fontSize = 13.sp)
            }
        }
        fin?.invoke(this)
    }
}

/**
 * Un titre de section, dans le registre du projet.
 *
 * ## De vraies petites capitales, pas des capitales
 *
 * Le Swift emploie `.caption.smallCaps()` : « Kenesset » y garde sa majuscule
 * initiale et le reste passe en petites capitales. La première version Android
 * mettait tout en capitales — « KENESSET » — ce qui crie là où iOS annonce.
 *
 * On demande donc la fonctionnalité OpenType `smcp` à la fonte. Jost la porte ;
 * si une fonte ne l'avait pas, le texte se rendrait en casse normale — moins
 * juste, mais toujours plus proche que des capitales.
 *
 * La casse d'origine est conservée : c'est elle qui donne la majuscule
 * initiale, et la mettre en capitales détruirait l'effet qu'on cherche.
 */
@Composable
public fun SectionCaption(
    label: String,
    modifier: Modifier = Modifier,
    teinte: Color? = null,
) {
    val theme = LocalReadingTheme.current
    val espace = ontSpacing
    Text(
        label,
        fontFamily = ONTFonts.display,
        color = teinte ?: ONTColors.inkSoft(theme),
        fontSize = 14.sp,
        fontWeight = FontWeight.Medium,
        letterSpacing = 0.04.sp * 14,
        // `fontFeatureSettings` ne vit que dans `TextStyle`, pas dans les
        // paramètres de `Text`.
        style = androidx.compose.ui.text.TextStyle(fontFeatureSettings = "smcp"),
        modifier = modifier.padding(start = espace.l, bottom = espace.s),
    )
}

/**
 * L'en-tête d'une section de réglages.
 *
 * ## Pourquoi il ne se confond pas avec [SectionCaption]
 *
 * Les deux existent côté iOS et ne servent pas au même endroit.
 * [SectionCaption] est en petites capitales et en encre douce : il annonce sans
 * concurrencer, à l'intérieur d'un contenu — « À venir » dans le Qahal.
 *
 * Celui-ci est l'en-tête qu'un `Form` dessine au-dessus de chaque groupe :
 * casse normale, plus grand, plus lisible. Il structure la **page**, pas un
 * bloc. Les confondre donnait un écran de réglages en capitales criardes là où
 * iOS a des intitulés qui se lisent.
 */
@Composable
public fun ONTSectionHeader(label: String, modifier: Modifier = Modifier) {
    val theme = LocalReadingTheme.current
    val espace = ontSpacing
    Text(
        label,
        color = ONTColors.inkSoft(theme),
        fontSize = 17.sp,
        modifier = modifier.padding(
            start = espace.l,
            top = espace.m,
            bottom = espace.s,
        ),
    )
}

/** Une pastille d'état — « brouillon », « glose ». */
@Composable
public fun StatusPill(
    label: String,
    modifier: Modifier = Modifier,
    teinte: Color = ONTColors.gold,
) {
    val theme = LocalReadingTheme.current
    Text(
        label,
        fontSize = 11.sp,
        color = ONTColors.ink(theme),
        modifier = modifier
            .clip(RoundedCornerShape(ONTRadius.pill))
            .background(teinte.copy(alpha = 0.3f))
            .padding(horizontal = 7.dp, vertical = 3.dp),
    )
}

/** Le filet doré qui sépare l'en-tête d'une unité de son corps. */
@Composable
public fun GoldRule(modifier: Modifier = Modifier, opacite: Float = 1f) {
    HorizontalDivider(
        color = ONTColors.gold.copy(alpha = opacite * 0.55f),
        modifier = modifier,
    )
}

/**
 * Le grand titre d'un écran de premier niveau.
 *
 * iOS l'obtient de sa barre de navigation ; Compose ne pose rien de tel, et
 * l'écrire à la main dans chaque écran ferait dériver les tailles. Ici il est
 * un composant, donc il ne dérive pas.
 */
@Composable
public fun ONTLargeTitle(titre: String, modifier: Modifier = Modifier) {
    val theme = LocalReadingTheme.current
    val espace = ontSpacing
    Text(
        titre,
        fontFamily = ONTFonts.display,
        fontWeight = FontWeight.SemiBold,
        fontSize = 34.sp,
        color = ONTColors.inkStrong(theme),
        // Annoncé comme un titre : TalkBack propose alors de sauter d'en-tête
        // en en-tête, ce qui est la seule façon de traverser un écran long sans
        // l'écouter en entier.
        modifier = modifier
            .semantics { heading() }
            .padding(
                start = espace.l,
                top = espace.l,
                bottom = espace.m,
            ),
    )
}
