package com.labibleont.ont.features.reading

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.automirrored.filled.Notes
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.labibleont.ont.designsystem.metrics.ONTRadius
import com.labibleont.ont.designsystem.metrics.ontSpacing
import com.labibleont.ont.designsystem.surfaces.ONTGroup
import com.labibleont.ont.designsystem.surfaces.ONTGroupDivider
import com.labibleont.ont.designsystem.surfaces.ONTPage
import com.labibleont.ont.designsystem.surfaces.SectionCaption
import com.labibleont.ont.designsystem.theme.LocalReadingTheme
import com.labibleont.ont.designsystem.tokens.ONTColors
import com.labibleont.ont.designsystem.typography.ONTFonts
import com.labibleont.ont.kit.corpus.BookOutline
import com.labibleont.ont.kit.corpus.ChapterStub
import com.labibleont.ont.kit.corpus.Status
import com.labibleont.ont.kit.reader.ReadingFont
import com.labibleont.ont.kit.search.SearchEngine

/**
 * Le sélecteur de renvoi — livre, unité, verset.
 *
 * ## Ce qu'il remplace
 *
 * Le geste de YouVersion et de Bible Strong : une pastille qui dit où l'on est,
 * et qu'on touche pour aller ailleurs. Sans lui, aller de *Bereshit* 1 à
 * *Bereshit* 18 demandait quatre gestes — revenir au sommaire, replier le
 * livre, le déplier, viser. C'est exactement le manque signalé : toucher un
 * livre ouvrait la première unité et il n'y avait pas d'autre chemin.
 *
 * ## Trois étapes, dont on sort à la deuxième
 *
 * Livres, unités, versets. Neuf fois sur dix on s'arrête à l'unité, alors
 * chaque étape porte sa sortie courte en tête — « Introduction », « Toute
 * l'unité » — plutôt que de forcer à traverser la troisième.
 *
 * ## Il lit l'esquisse, pas le livre
 *
 * `books/bereshit.json` fait 750 Ko d'arbre d'inline. L'esquisse porte déjà le
 * numéro, le titre, le statut et le nombre de versets de chaque unité : tout ce
 * qu'une grille de numéros demande. Ouvrir le livre pour la dessiner serait
 * payer très cher un renseignement qu'on a.
 */
@Composable
public fun ReferencePicker(
    model: ReadingModel,
    /** L'unité ouverte — le sélecteur s'ouvre là, pas en haut de la liste. */
    livreCourant: String?,
    uniteCourante: String?,
    /**
     * Un livre imposé à l'ouverture, distinct de celui qu'on lit.
     *
     * C'est par là que passe l'onglet Bible : y toucher un livre doit montrer
     * **ses** unités, pas celles du chapitre ouvert ailleurs — et surtout pas
     * sauter directement à la première, ce qu'il faisait.
     */
    livreImpose: String? = null,
    onAller: (bookId: String, chapterId: String, verse: Int?) -> Unit,
    modifier: Modifier = Modifier,
) {
    // Un chemin, pas des onglets : on avance et on revient. La pile est tenue
    // ici plutôt que par la navigation de l'app, parce qu'elle ne sort pas de
    // ce sélecteur — l'app n'a pas à connaître ses étapes.
    var etape: Etape by remember(livreCourant, livreImpose) {
        mutableStateOf(
            when {
                // Un livre imposé l'emporte : il vient d'un geste explicite.
                livreImpose != null -> Etape.Unites(livreImpose)
                // Sinon on ouvre sur le livre courant : le lecteur cherche
                // presque toujours à côté de là où il est.
                livreCourant != null -> Etape.Unites(livreCourant)
                else -> Etape.Livres
            },
        )
    }

    when (val e = etape) {
        Etape.Livres -> EtapeDesLivres(
            model = model,
            livreCourant = livreCourant,
            onChoisir = { etape = Etape.Unites(it) },
            modifier = modifier,
        )

        is Etape.Unites -> EtapeDesUnites(
            livre = model.esquisse(e.livre),
            uniteCourante = uniteCourante,
            onRetour = { etape = Etape.Livres },
            onUnite = { unite -> etape = Etape.Versets(e.livre, unite) },
            onIntroduction = { intro -> onAller(e.livre, intro, null) },
            modifier = modifier,
        )

        is Etape.Versets -> EtapeDesVersets(
            unite = model.esquisse(e.livre)?.chapters?.firstOrNull { it.id == e.unite },
            francaisRecu = model.preferences.french,
            onRetour = { etape = Etape.Unites(e.livre) },
            onToutLUnite = { onAller(e.livre, e.unite, null) },
            onVerset = { n -> onAller(e.livre, e.unite, n) },
            modifier = modifier,
        )
    }
}

private sealed interface Etape {
    data object Livres : Etape
    data class Unites(val livre: String) : Etape
    data class Versets(val livre: String, val unite: String) : Etape
}

// ── 1. Les livres ───────────────────────────────────────────────────────

@Composable
private fun EtapeDesLivres(
    model: ReadingModel,
    livreCourant: String?,
    onChoisir: (String) -> Unit,
    modifier: Modifier,
) {
    val theme = LocalReadingTheme.current
    val espace = ontSpacing
    var recherche by remember { mutableStateOf("") }

    Column(modifier = modifier.fillMaxWidth().verticalScroll(rememberScrollState())) {
        ONTPage {
            OutlinedTextField(
                value = recherche,
                onValueChange = { recherche = it },
                placeholder = { Text("Chercher un livre") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = ONTColors.surface(theme),
                    unfocusedContainerColor = ONTColors.surface(theme),
                    focusedIndicatorColor = ONTColors.accent(theme),
                    unfocusedIndicatorColor = ONTColors.separator(theme),
                    cursorColor = ONTColors.accent(theme),
                ),
                modifier = Modifier.fillMaxWidth().padding(vertical = espace.s),
            )

            for (corpus in model.corpora.sortedBy { it.order }) {
                val livres = corpus.modes.sortedBy { it.order }
                    .flatMap { it.books }
                    .filter { correspond(it, recherche) }
                if (livres.isEmpty()) continue

                Spacer(Modifier.height(espace.m))
                SectionCaption(corpus.title, teinte = ONTColors.brandInk(theme))
                ONTGroup {
                    livres.forEachIndexed { i, livre ->
                        if (i > 0) ONTGroupDivider()
                        LigneDuSelecteur(
                            livre = livre,
                            courant = livre.id == livreCourant,
                            onChoisir = { onChoisir(livre.id) },
                        )
                    }
                }
            }
            Spacer(Modifier.height(espace.xxl))
        }
    }
}

/**
 * Replie une chaîne pour la comparaison : sans accents, sans casse.
 *
 * On emploie le `fold` du moteur de recherche plutôt qu'un `lowercase` : c'est
 * le même pliage que celui du pipeline, donc chercher « berechit » trouve
 * *Bereshit* et « genese » trouve *Genèse* — ce qu'un lecteur tape vraiment.
 */
private fun correspond(livre: BookOutline, recherche: String): Boolean {
    val cherche = SearchEngine.fold(recherche.trim())
    if (cherche.isEmpty()) return true
    return SearchEngine.fold(livre.title).contains(cherche) ||
        SearchEngine.fold(livre.french).contains(cherche)
}

@Composable
private fun LigneDuSelecteur(livre: BookOutline, courant: Boolean, onChoisir: () -> Unit) {
    val theme = LocalReadingTheme.current
    val espace = ontSpacing
    // Un slot vide reste **visible mais éteint** : le corpus est un chantier, et
    // masquer les vides donnerait une fausse idée de sa forme.
    val lisible = !livre.empty

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .then(if (lisible) Modifier.clickable(onClick = onChoisir) else Modifier)
            .heightIn(min = 48.dp)
            .padding(horizontal = espace.l, vertical = espace.s),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            "%02d".format(livre.slot),
            fontSize = 11.sp,
            color = ONTColors.inkSoft(theme),
            modifier = Modifier.padding(end = espace.m),
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                livre.title,
                fontFamily = ONTFonts.family(ReadingFont.LITERATA),
                fontStyle = FontStyle.Italic,
                fontSize = 17.sp,
                fontWeight = if (courant) FontWeight.SemiBold else FontWeight.Normal,
                color = when {
                    courant -> ONTColors.accent(theme)
                    lisible -> ONTColors.ink(theme)
                    else -> ONTColors.inkSoft(theme)
                },
            )
            Text(livre.french, fontSize = 13.sp, color = ONTColors.inkSoft(theme))
        }
        if (!lisible) {
            Text("à venir", fontSize = 12.sp, color = ONTColors.inkSoft(theme))
        }
    }
}

// ── 2. Les unités ───────────────────────────────────────────────────────

@Composable
private fun EtapeDesUnites(
    livre: BookOutline?,
    uniteCourante: String?,
    onRetour: () -> Unit,
    onUnite: (String) -> Unit,
    onIntroduction: (String) -> Unit,
    modifier: Modifier,
) {
    val theme = LocalReadingTheme.current
    val espace = ontSpacing

    Column(modifier = modifier.fillMaxWidth()) {
        FilDAriane(livre?.title ?: "", onRetour = onRetour)

        if (livre == null || livre.empty) {
            Indisponible("Ce livre n'est pas encore rédigé.")
            return@Column
        }

        livre.intro?.let { intro ->
            SortieCourte(
                intitule = "Introduction",
                icone = Icons.AutoMirrored.Filled.MenuBook,
                onClick = { onIntroduction(intro.id) },
                modifier = Modifier.padding(horizontal = espace.l),
            )
            Spacer(Modifier.height(espace.m))
        }

        LazyVerticalGrid(
            columns = GridCells.Adaptive(minSize = 64.dp),
            horizontalArrangement = Arrangement.spacedBy(espace.s),
            verticalArrangement = Arrangement.spacedBy(espace.s),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(espace.l),
        ) {
            items(livre.chapters, key = { it.id }) { unite ->
                Case(
                    unite = unite,
                    courant = unite.id == uniteCourante,
                    onClick = { onUnite(unite.id) },
                )
            }
        }
    }
}

/**
 * Une case de la grille.
 *
 * Le numéro, et rien d'autre — le titre d'une unité ONT est une phrase, elle ne
 * tient pas dans une case. Un brouillon porte un point : c'est l'état du §12,
 * et le lecteur doit savoir avant d'ouvrir que ce texte n'est pas encore
 * verrouillé.
 */
@Composable
private fun Case(unite: ChapterStub, courant: Boolean, onClick: () -> Unit) {
    val theme = LocalReadingTheme.current

    Box(
        modifier = Modifier
            .size(64.dp)
            .clip(RoundedCornerShape(ONTRadius.highlight * 2))
            .background(
                if (courant) ONTColors.accent(theme).copy(alpha = 0.25f)
                else ONTColors.surface(theme),
            )
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            "${unite.n}",
            fontFamily = ONTFonts.display,
            fontSize = 19.sp,
            color = if (courant) ONTColors.accent(theme) else ONTColors.ink(theme),
            textAlign = TextAlign.Center,
        )
        if (unite.status == Status.BROUILLON) {
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(6.dp)
                    .size(6.dp)
                    .clip(RoundedCornerShape(ONTRadius.pill))
                    .background(ONTColors.accentuation(theme)),
            )
        }
    }
}

// ── 3. Les versets ──────────────────────────────────────────────────────

@Composable
private fun EtapeDesVersets(
    unite: ChapterStub?,
    francaisRecu: Boolean,
    onRetour: () -> Unit,
    onToutLUnite: () -> Unit,
    onVerset: (Int) -> Unit,
    modifier: Modifier,
) {
    val espace = ontSpacing

    Column(modifier = modifier.fillMaxWidth()) {
        // **Le même mot que le sommaire.** Le fil d'Ariane disait le titre brut
        // — « Bereshit 2 » — pendant que l'arborescence disait déjà
        // « Parashah 2 ». Deux noms pour la même unité, à un écran d'écart.
        FilDAriane(unite?.libelle(francaisRecu) ?: "", onRetour = onRetour)

        // La sortie courte, en premier : neuf fois sur dix on veut l'unité, pas
        // un verset précis. Elle nomme l'unité dans le registre choisi plutôt
        // que de la dire « unité » — le mot générique était le seul endroit de
        // l'app où le lecteur ne lisait ni « chapitre » ni « parashah ».
        SortieCourte(
            intitule = if (francaisRecu) "Tout le chapitre" else "Toute la parashah",
            icone = Icons.AutoMirrored.Filled.Notes,
            onClick = onToutLUnite,
            modifier = Modifier.padding(horizontal = espace.l),
        )

        if (unite == null || unite.verseCount == 0) {
            Indisponible("Cette unité ne porte pas de versets.")
            return@Column
        }

        Spacer(Modifier.height(espace.m))
        LazyVerticalGrid(
            columns = GridCells.Adaptive(minSize = 56.dp),
            horizontalArrangement = Arrangement.spacedBy(espace.s),
            verticalArrangement = Arrangement.spacedBy(espace.s),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(espace.l),
        ) {
            items((1..unite.verseCount).toList()) { n ->
                CaseDeVerset(n = n, onClick = { onVerset(n) })
            }
        }
    }
}

@Composable
private fun CaseDeVerset(n: Int, onClick: () -> Unit) {
    val theme = LocalReadingTheme.current
    Box(
        modifier = Modifier
            .size(56.dp)
            .clip(RoundedCornerShape(ONTRadius.highlight * 2))
            .background(ONTColors.surface(theme))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text("$n", fontSize = 16.sp, color = ONTColors.ink(theme))
    }
}

// ── Le commun ───────────────────────────────────────────────────────────

/**
 * Le fil d'Ariane d'une étape.
 *
 * Il porte le retour **dans** le sélecteur, distinct du retour système qui,
 * lui, ferme le sélecteur entier. Les deux existent parce qu'ils ne font pas la
 * même chose : revenir d'une étape n'est pas renoncer à changer de passage.
 */
@Composable
private fun FilDAriane(titre: String, onRetour: () -> Unit) {
    val theme = LocalReadingTheme.current
    val espace = ontSpacing
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onRetour)
            .padding(horizontal = espace.l, vertical = espace.m),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            Icons.AutoMirrored.Filled.ArrowBack,
            contentDescription = "Revenir à l'étape précédente",
            tint = ONTColors.brandInk(theme),
            modifier = Modifier.padding(end = espace.s),
        )
        Text(
            titre,
            fontFamily = ONTFonts.display,
            fontSize = 18.sp,
            color = ONTColors.inkStrong(theme),
        )
    }
}

@Composable
private fun SortieCourte(
    intitule: String,
    icone: androidx.compose.ui.graphics.vector.ImageVector,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val theme = LocalReadingTheme.current
    val espace = ontSpacing
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(ONTRadius.card))
            .background(ONTColors.accent(theme).copy(alpha = 0.10f))
            .clickable(onClick = onClick)
            .padding(espace.m),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            icone,
            contentDescription = null,
            tint = ONTColors.accent(theme),
            modifier = Modifier.padding(end = espace.s),
        )
        Text(intitule, color = ONTColors.accent(theme), fontSize = 15.sp)
    }
}

@Composable
private fun Indisponible(message: String) {
    val theme = LocalReadingTheme.current
    Text(
        message,
        color = ONTColors.inkSoft(theme),
        modifier = Modifier.fillMaxWidth().padding(ontSpacing.xl),
        textAlign = TextAlign.Center,
    )
}
