package com.labibleont.ont.features.lexicon

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.labibleont.ont.designsystem.metrics.ontSpacing
import com.labibleont.ont.designsystem.text.BlocDeFiche
import com.labibleont.ont.designsystem.theme.LocalReadingTheme
import com.labibleont.ont.designsystem.tokens.ONTColors
import com.labibleont.ont.designsystem.typography.ONTFonts
import com.labibleont.ont.designsystem.typography.ONTProse
import com.labibleont.ont.designsystem.typography.ONTTypography
import com.labibleont.ont.kit.corpus.ShemEntry
import com.labibleont.ont.kit.reader.ReadingPreferences

/**
 * La fiche d'un **Shem** — un porteur de nom.
 *
 * ## Pourquoi ce n'est pas [TermSheet]
 *
 * Une fiche d'intraduisible dit un **concept** : un champ sémantique, une
 * traduction fixée, les endroits où le mot paraît. Une fiche de Shem dit un
 * **porteur** : le sens de la racine, ce que le nom met sur les épaules de qui
 * le porte, et ce qui reste à venir.
 *
 * Les deux se lisent donc autrement. Celle-ci n'a ni compteur d'occurrences ni
 * traduction — un nom ne se traduit pas — et elle porte des **titres de
 * section**, que les fiches de concepts n'ont pas : 197 des 305 fiches en
 * comptent, avec quatre à six mouvements.
 *
 * Les rendre visibles est tout l'objet de cette feuille. Sans eux, six
 * mouvements arrivent en un seul bloc et le « Voir aussi » se colle au reste.
 */
@Composable
public fun ShemSheet(
    entree: ShemEntry,
    preferences: ReadingPreferences,
    modifier: Modifier = Modifier,
) {
    val theme = LocalReadingTheme.current
    val typo = ONTTypography(preferences.textSize.toFloat(), theme, preferences.bodyFont)
    val espace = ontSpacing
    val interligne =
        (preferences.textSize * com.labibleont.ont.designsystem.typography.interligne(
            preferences.lineSpacing,
        )).sp

    Column(
        modifier = modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = espace.page, vertical = espace.m),
    ) {
        // Le nom, dans sa terre brûlée. C'est la seule couleur de la feuille :
        // le corps de la fiche est de l'encre ordinaire, parce qu'il parle du
        // porteur et non du nom.
        Text(
            entree.title,
            fontFamily = ONTFonts.display,
            fontSize = (preferences.textSize * 1.5f).sp,
            fontWeight = FontWeight.SemiBold,
            color = ONTColors.shem(theme),
            modifier = Modifier.semantics { heading() },
        )
        Spacer(Modifier.height(espace.m))

        // ## Le rendu des blocs est délégué — arbitrage iOS du 18 septembre 2026
        //
        // Cet écran gardait sa propre boucle : titres et paragraphes, un seul
        // corps de titre à `textSize * 1.1f`, et les trois autres formes ignorées
        // en silence. Mesuré côté iOS : `ShemSheet.swift:71` appelle `BlocDeFiche`
        // comme les deux autres feuilles — il n'y a **pas** deux rendus là-bas.
        //
        // `titresPleins` reste à `false`, le régime **resserré**, et c'est un
        // argument de structure de contenu, pas de plateforme : un `##` de fiche
        // est déjà sous un en-tête de section, et lui donner une taille de titre
        // le ferait rivaliser avec le bloc qui le contient. Cette feuille a les
        // mêmes sections que celle d'iOS.
        //
        // Ce qu'on perd en le faisant : le titre devient plus petit que sa propre
        // prose. Ce qu'on gagne : un seul rendu de bloc pour les trois feuilles.
        // Deux régimes pour le même composant sur deux plateformes divergeraient
        // à la première correction — c'est l'argument qui avait déjà fait préférer
        // un drapeau à une seconde vue, un cran plus bas.
        for (bloc in entree.definition) {
            BlocDeFiche(
                bloc = bloc,
                typo = typo,
                preferences = preferences,
            )
        }

        Spacer(Modifier.height(espace(48)))
    }
}
