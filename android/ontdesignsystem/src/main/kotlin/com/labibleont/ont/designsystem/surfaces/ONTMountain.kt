package com.labibleont.ont.designsystem.surfaces

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.Dp
import com.labibleont.ont.designsystem.R

/**
 * Le mont de la marque, en ornement.
 *
 * ## Il se dimensionne par la hauteur, jamais par la largeur
 *
 * Il accompagne toujours un texte — un intitulé, un titre — et c'est la
 * hauteur des lettres qui décide de la sienne. Lui donner une largeur le
 * ferait dépasser ou disparaître selon la langue du libellé.
 *
 * ## Pourquoi il est plus grand que les lettres qu'il accompagne
 *
 * À la taille des capitales, ses crêtes de gauche deviennent une bavure : le
 * dessin porte des dentelures d'un ou deux points de large, que l'écran ne sait
 * plus rendre en dessous d'une certaine échelle. La liseuse iOS a mesuré la
 * limite et l'a écrite — 10 pt donne une bouillie, 14 pt est limite, 18 pt
 * tient. On le pose donc au-dessus du corps du texte qu'il suit, pas à sa
 * hauteur.
 *
 * @param hauteur la hauteur du dessin ; sa largeur suit son rapport d'origine.
 * @param teinte sa couleur — l'or sur le bordeaux de la carte du jour.
 */
@Composable
public fun ONTMountain(
    hauteur: Dp,
    teinte: Color,
    modifier: Modifier = Modifier,
) {
    Image(
        painter = painterResource(R.drawable.ont_mont),
        // Muet pour l'accessibilité : c'est un ornement, et l'intitulé qu'il
        // accompagne dit déjà ce qu'il faut entendre. L'annoncer ferait
        // entendre « image » avant « verset du jour ».
        contentDescription = null,
        colorFilter = ColorFilter.tint(teinte),
        modifier = modifier
            .height(hauteur)
            .aspectRatio(RAPPORT),
    )
}

/** 502 sur 249 — les proportions du tracé, telles que le site les porte. */
private const val RAPPORT = 502f / 249f
