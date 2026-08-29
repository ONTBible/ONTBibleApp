package com.labibleont.ont.features.reading

import androidx.compose.animation.AnimatedVisibility
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
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.labibleont.ont.designsystem.metrics.ONTRadius
import com.labibleont.ont.designsystem.metrics.ontSpacing
import com.labibleont.ont.designsystem.surfaces.ONTGroup
import com.labibleont.ont.designsystem.surfaces.ONTGroupDivider
import com.labibleont.ont.designsystem.surfaces.ONTLargeTitle
import com.labibleont.ont.designsystem.surfaces.ONTPage
import com.labibleont.ont.designsystem.surfaces.SectionCaption
import com.labibleont.ont.designsystem.theme.LocalReadingTheme
import com.labibleont.ont.designsystem.tokens.ONTColors
import com.labibleont.ont.designsystem.typography.ONTFonts
import com.labibleont.ont.kit.corpus.BookOutline
import com.labibleont.ont.kit.corpus.Conteneur
import com.labibleont.ont.kit.corpus.Mode
import com.labibleont.ont.kit.reader.ReadingFont
import com.labibleont.ont.kit.reader.ReadingPosition
import com.labibleont.ont.kit.corpus.Registre

/**
 * L'onglet Bible — l'arborescence du corpus.
 *
 * ## Les slots vides sont montrés, pas cachés
 *
 * Soixante-dix livres, quatre rédigés. Une liste qui n'afficherait que les
 * quatre laisserait croire que l'ONT *est* ces quatre-là. Elle les montre tous,
 * les à-venir en encre douce : le lecteur voit l'architecture entière et où
 * elle en est.
 *
 * ## Des groupes encartés, et non une liste plate
 *
 * La première version d'Android empilait les modes et les livres avec des
 * filets pleine largeur. C'était lisible, et ça ne ressemblait pas à l'app :
 * iOS pose des surfaces arrondies qui portent leurs lignes. La différence n'est
 * pas décorative — un groupe dit « ces lignes vont ensemble » sans qu'on ait à
 * lire les intitulés.
 */
@Composable
public fun BibleTab(
    model: ReadingModel,
    position: ReadingPosition?,
    onOuvrir: (bookId: String, chapterId: String?) -> Unit,
    modifier: Modifier = Modifier,
) {
    val espace = ontSpacing
    val deplies = remember { mutableStateMapOf<String, Boolean>() }

    Column(
        modifier = modifier.fillMaxWidth().verticalScroll(rememberScrollState()),
    ) {
        ONTPage {
            ONTLargeTitle("La Bible ONT")

            position?.let { CarteReprendre(it, onOuvrir) }

            for (corpus in model.corpora.sortedBy { it.order }) {
                Spacer(Modifier.height(espace.xl))
                SectionCaption(
                    corpus.title,
                    teinte = ONTColors.brandInk(LocalReadingTheme.current),
                )
                // Le second nom, dans le registre choisi. Rien ne s'affiche
                // quand il n'y a rien à dire — une section dont la glose
                // redirait le pont n'en porte pas.
                Registre.second(corpus.french, corpus.glose, model.preferences.french)?.let {
                    Text(
                        it,
                        fontSize = 12.sp,
                        color = ONTColors.inkSoft(LocalReadingTheme.current),
                        modifier = Modifier.padding(
                            start = espace.l,
                            end = espace.l,
                            bottom = espace.xs,
                        ),
                    )
                }
                ONTGroup {
                    corpus.modes.sortedBy { it.order }.forEachIndexed { i, mode ->
                        if (i > 0) ONTGroupDivider(retrait = false)
                        val cle = "${corpus.id}/${mode.id}"
                        SectionDeMode(
                            mode = mode,
                            francaisRecu = model.preferences.french,
                            deplie = deplies[cle] == true,
                            onBasculer = { deplies[cle] = deplies[cle] != true },
                            onOuvrir = onOuvrir,
                        )
                    }
                }
            }
            Spacer(Modifier.height(espace.xxl))
        }
    }
}

/**
 * Reprendre où l'on en était.
 *
 * En tête, avant l'arborescence : c'est ce que le lecteur veut neuf fois sur
 * dix en ouvrant l'app, et le lui faire chercher dans une liste de soixante-dix
 * entrées serait lui demander de refaire chaque jour le chemin qu'il connaît.
 */
@Composable
private fun CarteReprendre(position: ReadingPosition, onOuvrir: (String, String?) -> Unit) {
    val theme = LocalReadingTheme.current
    val espace = ontSpacing

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(ONTRadius.block))
            .background(ONTColors.surface(theme))
            .clickable { onOuvrir(position.bookId, position.chapterId) }
            .padding(espace.l),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text("Reprendre", color = ONTColors.ink(theme), fontSize = 16.sp)
            Text(
                "${position.chapterTitle}:${position.verse}",
                color = ONTColors.inkSoft(theme),
                fontSize = 13.sp,
            )
        }
        Icon(
            Icons.AutoMirrored.Filled.ArrowForward,
            contentDescription = null,
            tint = ONTColors.accent(theme),
        )
    }
}

/**
 * Un mode, replié par défaut.
 *
 * Le compteur « 1/6 » dit d'un coup d'œil ce qui est lisible — c'est
 * l'information qu'on cherche en ouvrant cet écran, et la seule qui justifie de
 * montrer des livres qu'on ne peut pas encore lire.
 */
@Composable
private fun SectionDeMode(
    mode: Mode,
    francaisRecu: Boolean,
    deplie: Boolean,
    onBasculer: () -> Unit,
    onOuvrir: (String, String?) -> Unit,
) {
    val theme = LocalReadingTheme.current
    val espace = ontSpacing
    val rediges = mode.books.count { !it.empty }

    Column {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClick = onBasculer)
                .heightIn(min = 48.dp)
                .padding(horizontal = espace.l, vertical = espace.m),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    mode.title,
                    fontFamily = ONTFonts.display,
                    fontSize = 18.sp,
                    color = ONTColors.ink(theme),
                )
                Registre.second(mode.french, mode.glose, francaisRecu)?.let {
                    Text(it, fontSize = 12.sp, color = ONTColors.inkSoft(theme))
                }
            }
            Text(
                "$rediges/${mode.books.size}",
                fontSize = 14.sp,
                color = ONTColors.inkSoft(theme),
                modifier = Modifier.padding(end = espace.s),
            )
            Icon(
                if (deplie) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
                contentDescription = if (deplie) "Replier" else "Déplier",
                tint = ONTColors.inkSoft(theme),
            )
        }

        AnimatedVisibility(visible = deplie) {
            Column {
                for (element in disposer(mode)) {
                    ONTGroupDivider()
                    when (element) {
                        is Element.Entete ->
                            EnteteDeConteneur(element.conteneur, francaisRecu)
                        is Element.Livre ->
                            LigneDeLivre(
                        livre = element.livre,
                        francaisRecu = francaisRecu,
                        onOuvrir = onOuvrir,
                    )
                    }
                }
            }
        }
    }
}

/**
 * Un livre.
 *
 * Le titre est le nom **hébreu translittéré** — c'est le vrai titre du livre
 * (§2.6), et c'est pourquoi il est en italique de la fonte de lecture. Le
 * français est dessous, plus petit : c'est un pont de navigation pour le
 * lecteur occidental, pas le nom de l'ouvrage.
 */
@Composable
private fun LigneDeLivre(
    livre: BookOutline,
    francaisRecu: Boolean,
    onOuvrir: (String, String?) -> Unit,
) {
    val theme = LocalReadingTheme.current
    val espace = ontSpacing
    val lisible = !livre.empty

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .then(if (lisible) Modifier.clickable { onOuvrir(livre.id, null) } else Modifier)
            .heightIn(min = 48.dp)
            .padding(start = espace.xl, end = espace.l, top = espace.s, bottom = espace.s),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            "%02d".format(livre.slot),
            fontSize = 11.sp,
            color = ONTColors.inkSoft(theme),
            textAlign = TextAlign.End,
            modifier = Modifier.padding(end = espace.m),
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                livre.title,
                fontFamily = ONTFonts.family(ReadingFont.LITERATA),
                fontStyle = FontStyle.Italic,
                fontSize = 17.sp,
                // Un livre à venir s'efface, mais reste lisible : il dit
                // l'architecture, il ne doit pas être un fantôme.
                color = if (lisible) ONTColors.ink(theme) else ONTColors.inkSoft(theme),
            )
            // Le second nom du livre suit le registre, comme partout ailleurs
            // dans cette liste. Il ne le suivait **pas** : la ligne affichait le
            // français en dur, si bien qu'un lecteur ayant éteint le français
            // reçu voyait « Actes des Apôtres » là où le site dit « les gevurot
            // de YHWH par ses neviim ». Le corpus porte la glose sur
            // vingt-quatre livres ; l'app la jetait.
            Registre.second(livre.french, livre.glose, francaisRecu)?.let {
                Text(it, fontSize = 13.sp, color = ONTColors.inkSoft(theme))
            }
        }
        Text(
            if (lisible) "${livre.verseCount} v." else "à venir",
            fontSize = 12.sp,
            color = ONTColors.inkSoft(theme),
        )
    }
}

// --- Les conteneurs, et la fracture du Ḥurban ---


/** Ce que la liste d'un mode pose l'un après l'autre. */
private sealed interface Element {
    data class Entete(val conteneur: Conteneur) : Element
    data class Livre(val livre: BookOutline) : Element
}

/**
 * Intercale les en-têtes de conteneur dans la suite des livres.
 *
 * L'ordre vient des **livres**, jamais de la liste des conteneurs : c'est le
 * corpus qui décide où tombe une coupure. Un identifiant porté par un livre
 * sans déclaration est ignoré — une table des matières qui refuserait de se
 * rendre pour un ornement coûterait plus au lecteur qu'elle ne lui apporte.
 */
private fun disposer(mode: Mode): kotlin.collections.List<Element> {
    val sortie = mutableListOf<Element>()
    var courant: String? = null
    var premier = true
    for (livre in mode.books.sortedBy { it.slot }) {
        if (premier || livre.groupId != courant) {
            courant = livre.groupId
            premier = false
            val declare = courant?.let { id -> mode.groups.firstOrNull { it.id == id } }
            if (declare != null) sortie.add(Element.Entete(declare))
        }
        sortie.add(Element.Livre(livre))
    }
    return sortie
}

/**
 * L'en-tête d'un conteneur, et sa césure quand il en a une.
 *
 * **Deux poids, deux traitements.** Un conteneur qui regroupe reçoit un
 * intertitre discret ; celui qui fracture reçoit d'abord un filet appuyé et la
 * ligne qui dit ce que la fracture change pour lire.
 *
 * C'est le *Ḥurban*, et lui seul. `corpus-order.md` le nomme **pivot
 * herméneutique** : les lettres d'avant parlent du Temple au présent —
 * *Igeret HaIvrim* est « le dernier mot du Bayit vivant » ; trois numéros plus
 * loin, il n'existe plus.
 */
@Composable
private fun EnteteDeConteneur(conteneur: Conteneur, francaisRecu: Boolean) {
    val theme = LocalReadingTheme.current
    val espace = ontSpacing

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = espace.xl, end = espace.l, top = espace.s, bottom = espace.s),
    ) {
        conteneur.rupture?.let { rupture ->
            // Le filet est en accentuation et non en or : l'or dit
            // l'intraduisible partout ailleurs, et une règle horizontale n'en
            // est pas un.
            Spacer(
                Modifier
                    .fillMaxWidth()
                    .height(2.dp)
                    .background(ONTColors.accentuation(theme).copy(alpha = 0.5f)),
            )
            Text(
                rupture,
                fontStyle = FontStyle.Italic,
                fontSize = 13.sp,
                color = ONTColors.inkSoft(theme),
                modifier = Modifier.padding(top = espace.xs, bottom = espace.s),
            )
        }
        SectionCaption(conteneur.title)
        Registre.second(conteneur.french, conteneur.glose, francaisRecu)?.let {
            Text(it, fontSize = 11.sp, color = ONTColors.inkSoft(theme))
        }
    }
}
