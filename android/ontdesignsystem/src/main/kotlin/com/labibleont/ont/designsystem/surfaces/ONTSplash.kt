package com.labibleont.ont.designsystem.surfaces

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.min
import com.labibleont.ont.designsystem.tokens.ONTColors
import kotlin.math.PI
import kotlin.math.cos

/**
 * L'ouverture — la montagne qu'un trait de lumière révèle.
 *
 * ## Ce que ce n'est pas
 *
 * **Ce n'est pas l'écran de lancement d'Android.** Celui-là est décrit par
 * `windowBackground` dans `themes.xml`, il est fixe par construction, et aucun
 * code n'y tourne : le système l'affiche avant que l'app existe. Il reste ce
 * qu'il est, un aplat de nuit.
 *
 * Ceci est une **vue de l'app**, posée par-dessus le premier écran et dissoute
 * ensuite. C'est le seul endroit où une animation est possible.
 *
 * ## D'où vient ce qui est ici
 *
 * Le mouvement est celui composé par l'auteur — `app/Marque/ouverture/`, et
 * porté sur iOS par `ONTSplash.swift`. Ses trois temps, sa courbe et la
 * géométrie de sa lueur sont **repris tels quels**, pas réinventés : c'est le
 * même dessin qui doit s'ouvrir sur les deux téléphones.
 *
 * ## Le fond est la nuit du projet, quel que soit le thème de lecture
 *
 * Deux raisons qui vont dans le même sens. La première est technique : toute la
 * lumière du dessin s'ajoute au fond, et une addition n'a **aucun effet** sur un
 * fond clair — sur le parchemin, le balayage serait invisible et la montagne
 * plate. L'ouverture exige un fond sombre.
 *
 * La seconde tient à ce qu'elle est : une ouverture n'est pas une page. Elle
 * porte la marque, qui ne se règle pas.
 */
@Composable
public fun ONTSplash(
    /** De 0 à 1 — l'avancement du minutage entier. */
    avancement: Float,
    /** Vrai quand le lecteur a demandé moins de mouvement. */
    mouvementReduit: Boolean = false,
    modifier: Modifier = Modifier,
) {
    BoxWithConstraints(
        modifier = modifier.fillMaxSize().background(ONTColors.nuit),
        contentAlignment = Alignment.Center,
    ) {
        // Le logomark est large — 502 sur 249. Un peu plus d'un tiers de la
        // largeur, et non les trois quarts : posé grand il cesse d'être une
        // marque et devient un décor.
        val largeurDuLogo: Dp = min(maxWidth * PART_DE_LARGEUR, PLAFOND_DU_LOGO)
        val hauteurDuLogo = largeurDuLogo * 249f / 502f

        val t = avancement * TOTAL

        // Sans mouvement, la montagne paraît simplement. Ce réglage ne relève
        // pas du goût : il sert ceux que le mouvement rend malades, et un
        // balayage « seulement plus doux » ne les soulagerait pas.
        val front = if (mouvementReduit) 1f else frontDeLumiere(t)
        val allumage = if (mouvementReduit) 0f else allumage(t)

        Box(Modifier.size(largeurDuLogo, hauteurDuLogo)) {
            // La montagne dans la pénombre — elle est là avant que la lumière
            // n'arrive, à peine visible.
            ONTMountain(hauteur = hauteurDuLogo, teinte = PENOMBRE)

            if (allumage > 0f) {
                // La bande, découpée **par la silhouette** : la lumière ne
                // traverse que la montagne. `SrcIn` sur un calque hors écran
                // est ce qui remplace le mélange par écran du dessin — même
                // résultat, et il tient sur toutes les versions.
                Box(
                    Modifier
                        .size(largeurDuLogo, hauteurDuLogo)
                        .graphicsLayer {
                            compositingStrategy = CompositingStrategy.Offscreen
                            alpha = allumage
                        }
                        .drawWithContent {
                            drawContent()
                            drawRect(
                                brush = bande(size, front),
                                blendMode = BlendMode.SrcIn,
                            )
                        },
                ) {
                    ONTMountain(hauteur = hauteurDuLogo, teinte = Color.White)
                }
            }
        }

        if (allumage > 0f && !mouvementReduit) {
            // La traînée déborde de la silhouette et traverse le cadre : c'est
            // elle qui fait que la lumière vient d'ailleurs et s'en va
            // ailleurs, au lieu de naître dans le logo.
            Box(
                Modifier
                    .fillMaxSize()
                    .graphicsLayer { alpha = allumage * 0.8f }
                    .blur(20.dp)
                    .drawWithContent {
                        val y = size.height / 2f
                        drawRect(
                            brush = Brush.horizontalGradient(
                                0f to ORCLAIR.copy(alpha = 0f),
                                0.45f to TRAINEE.copy(alpha = 0.55f),
                                0.5f to TRAINEE_COEUR,
                                0.55f to TRAINEE.copy(alpha = 0.55f),
                                1f to ORCLAIR.copy(alpha = 0f),
                                startX = (front - 0.72f) * size.width,
                                endX = (front + 0.72f) * size.width,
                            ),
                            topLeft = Offset(0f, y - 13f),
                            size = Size(size.width, 26f),
                        )
                    },
            )
        }
    }
}

/**
 * La bande claire, 2,2 fois la largeur du logo.
 *
 * Son cœur est centré sur le front, et ses bords s'éteignent avant d'atteindre
 * la silhouette : c'est ce qui donne un trait qui passe, et non un aplat qui
 * s'allume. L'inclinaison — 100° dans le dessin — est presque horizontale.
 */
private fun bande(taille: Size, front: Float): Brush {
    val large = taille.width * 2.2f
    val depart = front * taille.width - large / 2f
    return Brush.linearGradient(
        0.32f to OR.copy(alpha = 0f),
        0.44f to ORCLAIR.copy(alpha = 0.95f),
        0.5f to COEUR,
        0.56f to ORCLAIR.copy(alpha = 0.95f),
        0.68f to OR.copy(alpha = 0f),
        start = Offset(depart, taille.height * 0.41f),
        end = Offset(depart + large, taille.height * 0.59f),
    )
}

/**
 * Où en est le front de lumière, de part et d'autre du cadre.
 *
 * Il part **avant** le bord et finit **après** — de −0,22 à 1,22 — pour que la
 * lueur entre et sorte au lieu de naître et mourir sur place.
 */
private fun frontDeLumiere(t: Float): Float {
    val p = sinusoidale(entre(DEBUT_DU_BALAYAGE, FIN_DU_BALAYAGE, t))
    return -0.22f + (1.22f + 0.22f) * p
}

/**
 * L'intensité de la part éclairée.
 *
 * Elle monte avant le balayage et retombe après, pour que la lumière
 * n'apparaisse pas d'un coup — un allumage franc se lit comme un défaut
 * d'affichage.
 */
private fun allumage(t: Float): Float = paliers(
    t,
    floatArrayOf(
        DEBUT_DU_BALAYAGE - 0.3f,
        DEBUT_DU_BALAYAGE + 0.25f,
        FIN_DU_BALAYAGE - 0.15f,
        FIN_DU_BALAYAGE + 0.5f,
    ),
    floatArrayOf(0f, 1f, 1f, 0f),
)

private fun entre(debut: Float, fin: Float, t: Float): Float =
    ((t - debut) / (fin - debut)).coerceIn(0f, 1f)

/** L'adoucissement du dessin : ni linéaire, ni ressort — une demi-sinusoïde. */
private fun sinusoidale(p: Float): Float = (1f - cos(p * PI.toFloat())) / 2f

private fun paliers(t: Float, instants: FloatArray, valeurs: FloatArray): Float {
    if (t <= instants.first()) return valeurs.first()
    if (t >= instants.last()) return valeurs.last()
    for (i in 0 until instants.size - 1) {
        if (t in instants[i]..instants[i + 1]) {
            val p = sinusoidale(entre(instants[i], instants[i + 1], t))
            return valeurs[i] + (valeurs[i + 1] - valeurs[i]) * p
        }
    }
    return valeurs.last()
}

/** *Le logomark repose dans la pénombre, à peine visible.* */
private const val ATTENTE = 1.1f

/** *Une lueur traverse la montagne et déborde de la silhouette.* */
private const val BALAYAGE = 2.8f

/** *La lumière quitte le cadre, une rémanence chaude retombe.* */
private const val REPOS = 1.6f

private const val DEBUT_DU_BALAYAGE = ATTENTE
private const val FIN_DU_BALAYAGE = ATTENTE + BALAYAGE

/** La durée entière, en secondes. */
public const val OUVERTURE_TOTALE: Float = ATTENTE + BALAYAGE + REPOS
private const val TOTAL = OUVERTURE_TOTALE

private const val PART_DE_LARGEUR = 0.36f
private val PLAFOND_DU_LOGO = 225.dp

// Les valeurs du dessin, sur un fond sombre imposé. Elles ne passent pas par
// `ONTColors` parce qu'elles ne sont **pas** des jetons du design system : les
// y mêler donnerait à croire qu'on peut les employer ailleurs.
/** La montagne dans la pénombre — `#3a3527`. */
private val PENOMBRE = Color(0xFF3A3527)
/** L'or du logo — `#cdbe83`. */
private val OR = Color(0xFFCDBE83)
/** L'or clair de la bande — `#e9d68d`. */
private val ORCLAIR = Color(0xFFE9D68D)
/** Le cœur de la bande — `#fffaf0`. */
private val COEUR = Color(0xFFFFFAF0)
/** La traînée — `#fff6d8`. */
private val TRAINEE = Color(0xFFFFF6D8)
/** Son cœur — `#fffdf5`. */
private val TRAINEE_COEUR = Color(0xFFFFFDF5)
