package com.labibleont.ont.features.reading

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.labibleont.ont.designsystem.theme.LocalReadingTheme
import com.labibleont.ont.designsystem.tokens.ONTColors
import com.labibleont.ont.designsystem.typography.ONTFonts
import com.labibleont.ont.kit.corpus.BookOutline
import com.labibleont.ont.kit.corpus.Mode

/**
 * L'onglet Bible — l'arborescence du corpus.
 *
 * ## Les slots vides sont montrés, pas cachés
 *
 * Soixante-dix livres, quatre rédigés. Une liste qui n'afficherait que les
 * quatre laisserait croire que l'ONT *est* ces quatre-là. Elle les montre tous,
 * les à-venir en retrait et sans le poids de l'encre : le lecteur voit
 * l'architecture entière et où elle en est.
 *
 * C'est aussi ce que fait la liseuse iOS, et pour la même raison — un corpus
 * est un plan avant d'être un texte.
 */
@Composable
public fun BibleTab(
    model: ReadingModel,
    onOuvrir: (bookId: String, chapterId: String?) -> Unit,
    modifier: Modifier = Modifier,
) {
    val theme = LocalReadingTheme.current

    LazyColumn(modifier = modifier.fillMaxWidth()) {
        item {
            Text(
                "La Bible ONT",
                fontFamily = ONTFonts.display,
                fontSize = 32.sp,
                color = ONTColors.inkStrong(theme),
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 16.dp),
            )
        }

        for (corpus in model.corpora.sortedBy { it.order }) {
            item(key = "corpus-${corpus.id}") {
                Text(
                    corpus.title,
                    fontFamily = ONTFonts.display,
                    fontSize = 15.sp,
                    color = ONTColors.brandInk(theme),
                    modifier = Modifier.padding(start = 20.dp, top = 20.dp, bottom = 6.dp),
                )
            }
            for (mode in corpus.modes.sortedBy { it.order }) {
                // La clé porte **les deux** identifiants, et ce n'est pas de la
                // prudence : les modes ne sont uniques que dans leur corpus.
                // `ketouvim` existe dans la Kenesset et dans la Berit Hadashah,
                // et une clé sur le seul mode fait tomber la liste avec
                // « Key was already used ». Découvert en lançant, pas en
                // compilant — c'est le genre de collision qu'aucun type ne dit.
                item(key = "mode-${corpus.id}-${mode.id}") {
                    ModeSection(mode = mode, onOuvrir = onOuvrir)
                }
            }
        }
    }
}

/**
 * Un mode, replié par défaut.
 *
 * Le compteur « 1/6 » dit d'un coup d'œil ce qui est lisible — c'est
 * l'information que le lecteur cherche en ouvrant cet écran, et la seule qui
 * justifie de montrer des livres qu'il ne peut pas encore lire.
 */
@Composable
private fun ModeSection(mode: Mode, onOuvrir: (String, String?) -> Unit) {
    val theme = LocalReadingTheme.current
    var deplie by remember { mutableStateOf(false) }
    val rediges = mode.books.count { !it.empty }

    Column {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { deplie = !deplie }
                .padding(horizontal = 20.dp, vertical = 14.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                mode.title,
                fontFamily = ONTFonts.display,
                fontSize = 19.sp,
                color = ONTColors.ink(theme),
            )
            Text(
                "$rediges/${mode.books.size}",
                fontSize = 14.sp,
                color = ONTColors.inkSoft(theme),
            )
        }
        HorizontalDivider(color = ONTColors.separator(theme))

        if (deplie) {
            for (livre in mode.books.sortedBy { it.slot }) {
                LigneDeLivre(livre = livre, onOuvrir = onOuvrir)
            }
        }
    }
}

/**
 * Un livre.
 *
 * Le titre est le nom **hébreu translittéré** — c'est le vrai titre du livre
 * (§2.6). Le français est dessous, en plus petit : c'est un pont de navigation
 * pour le lecteur occidental, pas le nom de l'ouvrage.
 */
@Composable
private fun LigneDeLivre(livre: BookOutline, onOuvrir: (String, String?) -> Unit) {
    val theme = LocalReadingTheme.current
    val lisible = !livre.empty

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .then(
                if (lisible) Modifier.clickable { onOuvrir(livre.id, null) } else Modifier,
            )
            .padding(start = 28.dp, end = 20.dp, top = 10.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            "%02d".format(livre.slot),
            fontSize = 12.sp,
            color = ONTColors.inkSoft(theme),
            textAlign = TextAlign.End,
            modifier = Modifier.padding(end = 10.dp),
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                livre.title,
                fontFamily = ONTFonts.family(com.labibleont.ont.kit.reader.ReadingFont.LITERATA),
                fontStyle = FontStyle.Italic,
                fontSize = 17.sp,
                // Un livre à venir s'efface, mais reste lisible : il dit
                // l'architecture, il ne doit pas être un fantôme.
                color = if (lisible) ONTColors.ink(theme) else ONTColors.inkSoft(theme),
            )
            Text(
                livre.french,
                fontSize = 13.sp,
                color = ONTColors.inkSoft(theme),
            )
        }
        Text(
            if (lisible) "${livre.verseCount} v." else "à venir",
            fontSize = 12.sp,
            color = ONTColors.inkSoft(theme),
        )
    }
}
