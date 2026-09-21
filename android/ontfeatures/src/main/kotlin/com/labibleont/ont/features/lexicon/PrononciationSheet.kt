package com.labibleont.ont.features.lexicon

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.labibleont.ont.designsystem.text.BlocDeFiche
import com.labibleont.ont.designsystem.theme.LocalReadingTheme
import com.labibleont.ont.designsystem.tokens.ONTColors
import com.labibleont.ont.designsystem.typography.ONTFonts
import com.labibleont.ont.designsystem.typography.ONTTypography
import com.labibleont.ont.kit.reader.ReadingPreferences
import com.labibleont.ont.kit.ports.FeuilleDePrononciation

/**
 * **Le pavé qui ouvre la feuille de prononciation**, en tête du Lexique.
 *
 * ## Ce qu'il répare
 *
 * Le corpus écrit `chokhmah`, `malʾakh`, `Chanokh` — et rien dans la graphie
 * n'avertit le lecteur quand il se trompe. Une translittération sans
 * diacritiques est faite pour **remonter à la lettre**, jamais pour guider la
 * bouche.
 *
 * ## Pourquoi un pavé et non une ligne de plus
 *
 * Le Lexique est une longue liste. Une ligne de plus s'y noierait, et personne
 * ne la toucherait jamais — alors que c'est ce qu'il faut lire **avant** la
 * première fiche.
 *
 * ## Ce qui vient d'iOS, et qu'on applique sans le rejuger
 *
 * L'aplat de marque avec l'encre retournée dessus : c'est le seul autre endroit
 * de l'app où la marque s'affirme en aplat, et les deux disent « ceci n'est pas
 * du corpus, c'est l'app qui te parle ».
 *
 * **La fonte du système, et non celle de la marque** — iOS l'a mesuré : la fonte
 * d'affichage porte un interligne large, fait pour un titre qui tient sur une
 * ligne. Dès que le libellé se replie — et il s'y replie au premier cran
 * d'accessibilité — le blanc entre les deux lignes fait le double de celui du
 * sous-titre, et le pavé se lit comme deux fragments au lieu d'un titre.
 *
 * Sur Android le piège est plus discret qu'ailleurs : les rôles `title*` de
 * `ONTChromeTypography` **imposent Jost**. Écrire `MaterialTheme.typography
 * .titleMedium` par réflexe rappellerait la fonte d'affichage sans qu'on le
 * voie. D'où `bodyLarge`, qui ne porte aucune famille — ce que ce fichier-là
 * dit explicitement de ses rôles de corps.
 *
 * **Une marge verticale, jamais une hauteur minimale seule.** iOS a payé ce
 * réglage sur l'iPhone de l'auteur : `minHeight` centre un contenu plus court
 * que lui, et l'espace autour *ressemble* à une marge. Dès que le contenu
 * dépasse, le cadre l'épouse exactement et le texte se colle au bord. Un réglage
 * qui marchait tant qu'une condition tenait, sans que rien ne dise laquelle.
 */
@Composable
public fun HeroDePrononciation(
    onOuvrir: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val theme = LocalReadingTheme.current

    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = modifier
            .fillMaxWidth()
            .clip(MaterialTheme.shapes.medium)
            .background(ONTColors.brandInk(theme))
            .clickable(onClick = onOuvrir)
            .defaultMinSize(minHeight = 76.dp)
            .padding(horizontal = 20.dp, vertical = 12.dp),
    ) {
        Column(Modifier.weight(1f)) {
            Text(
                "Comment ça se prononce",
                style = MaterialTheme.typography.bodyLarge,
                color = ONTColors.onBrand(theme),
            )
            Spacer(Modifier.height(2.dp))
            Text(
                "Les cinq sons que le français n'a pas",
                style = MaterialTheme.typography.bodySmall,
                color = ONTColors.onBrand(theme).copy(alpha = 0.85f),
            )
        }
    }
}

/**
 * La feuille elle-même — le texte du vault, rendu comme du corpus.
 *
 * ## Pourquoi elle ne porte aucun texte en dur
 *
 * Elle cite `chokhmah`, `malʾakh` et `Chanokh`, et c'est le rendu du corpus qui
 * les pose en or et en terre brûlée, touchables, sans une ligne de plus. Écrire
 * ce texte ici en ferait une **seconde source**, qui divergerait à la première
 * correction du vault.
 *
 * ## Le rendu des blocs est délégué
 *
 * `BlocDeFiche` du design system rend les cinq formes que le vault autorise, et
 * nomme les deux qu'il ne rend pas. Ce fichier disait que le `when` exhaustif
 * « vaudrait pour les trois écrans, pas pour celui-ci seul » — c'est exactement
 * ce qui a été fait le 16 septembre, et ce paragraphe en est la trace.
 */
@Composable
public fun PrononciationSheet(
    feuille: FeuilleDePrononciation,
    preferences: ReadingPreferences,
    modifier: Modifier = Modifier,
) {
    val theme = LocalReadingTheme.current
    // Les préférences entières, et non deux booléens extraits : `ONTTypography`
    // a besoin de la **taille de texte** choisie par le lecteur, qui est la
    // raison d'être de ce réglage. La passer par ses parties ferait rendre la
    // feuille à une taille fixe pendant que le reste du corpus suit le curseur.
    val typo = ONTTypography(preferences.textSize.toFloat(), theme, preferences.bodyFont)

    Column(
        modifier = modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .padding(bottom = 32.dp),
    ) {
        Text(
            feuille.titre,
            fontFamily = ONTFonts.display,
            fontSize = 22.sp,
            color = ONTColors.brandInk(theme),
            modifier = Modifier.padding(bottom = 16.dp),
        )

        for (bloc in feuille.blocs) {
            BlocDeFiche(
                bloc = bloc,
                typo = typo,
                preferences = preferences,
                titresPleins = true,
            )
        }
    }
}
