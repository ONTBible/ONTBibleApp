package com.labibleont.ont.features.reading

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.horizontalDrag
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.labibleont.ont.designsystem.tokens.ONTColors
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sign
import kotlinx.coroutines.launch

/**
 * Passer d'une unité à la suivante d'un glissement horizontal.
 *
 * Porté de `ChapterSwipe.swift` — les proportions viennent de là, relevées au
 * pixel sur un croquis et sur un film de YouVersion, pas réinventées ici.
 *
 * ## Pourquoi horizontal
 *
 * La lecture défile verticalement. Un geste horizontal ne peut donc jamais être
 * confondu avec elle — c'est le seul axe libre.
 *
 * ## Ce qui est propre à Android, et que iOS n'avait pas à traiter
 *
 * Le geste de **retour depuis le bord** appartient au système. Un glissement
 * qui commence dans les [BORD_SYSTEME] premiers points est donc laissé au
 * système, et l'app n'y touche pas.
 *
 * On ne pose surtout pas `systemGestureExclusion` : il est plafonné à 200 dp
 * cumulés sur toute la hauteur de l'écran, partagés entre toutes les fenêtres
 * visibles — donc inutilisable pour une page entière — et il confisquerait le
 * geste le plus identitaire d'Android pour en servir un de moins.
 *
 * ## On ne garde pas trois unités sous la main
 *
 * Une unité se construit d'un coup. En garder trois vivantes triplerait ce prix
 * à chaque ouverture — et YouVersion ne rend pas la suivante pendant le geste
 * non plus : le texte courant glisse, et derrière il n'y a que le fond.
 */
@Composable
public fun GlissementDUnite(
    peutAllerAvant: Boolean,
    peutAllerApres: Boolean,
    uniteCourante: String?,
    onAvant: () -> Unit,
    onApres: () -> Unit,
    modifier: Modifier = Modifier,
    contenu: @Composable () -> Unit,
) {
    val densite = LocalDensity.current
    val haptique = LocalHapticFeedback.current
    val vue = LocalView.current
    val portee = rememberCoroutineScope()

    var taille by remember { mutableStateOf(IntSize.Zero) }
    val glisse = remember { Animatable(0f) }
    val creux = remember { Animatable(0f) }
    var arme by remember { mutableStateOf(false) }
    var sensArme by remember { mutableFloatStateOf(0f) }

    // Le deuxième des trois retours d'iOS : l'unité a changé pour de bon.
    //
    // iOS l'accroche à `trigger: courant.id` — un changement d'**état**, pas le
    // retour de l'appel. La distinction n'est pas théorique ici : `onAvant` et
    // `onApres` appellent `lecture.aller()`, qui lance une coroutine et rend la
    // main tout de suite. Vibrer à leur retour dirait « c'est arrivé » avant que
    // ce soit arrivé — et se tromperait complètement quand rien n'arrive.
    //
    // On saute la première composition : à l'ouverture de la liseuse, l'unité
    // n'a pas changé, elle est simplement là. `trigger:` de SwiftUI a la même
    // règle, et c'est pour la même raison.
    var uniteVue by remember { mutableStateOf(uniteCourante) }
    LaunchedEffect(uniteCourante) {
        if (uniteCourante != uniteVue) {
            uniteVue = uniteCourante
            haptique.performHapticFeedback(HapticFeedbackType.Confirm)
        }
    }

    val creuxMax = with(densite) { CREUX_MAX.dp.toPx() }
    val depassementMax = with(densite) { DEPASSEMENT_MAX.dp.toPx() }
    val jeu = with(densite) { JEU_DE_DESARMEMENT.dp.toPx() }
    val bordSysteme = with(densite) { BORD_SYSTEME.dp.toPx() }

    // Le seuil est aussi le plafond, et c'est ce qui rend le geste apprenable :
    // une limite qu'on **voit** enseigne où elle se trouve, un seuil invisible
    // se devine à l'usage ou jamais.
    //
    // Il ne peut pas être un simple pourcentage : le creux se mesure en points
    // de texte, donc en fixant le plafond en dur il se mettrait à mentir dès
    // que le lecteur agrandit son texte — c'est-à-dire précisément chez qui en
    // a besoin. Les 12 % relevés chez YouVersion restent le plancher.
    val seuil = max(taille.width * PLAFOND, creuxMax - with(densite) { 22.dp.toPx() } + with(densite) { 14.dp.toPx() })

    Box(
        modifier = modifier
            .onSizeChanged { taille = it }
            .pointerInput(peutAllerAvant, peutAllerApres, seuil) {
                awaitEachGesture {
                    val depart = awaitFirstDown(requireUnconsumed = false)

                    // Le bord appartient au système. On ne dispute pas.
                    val x = depart.position.x
                    if (x < bordSysteme || x > size.width - bordSysteme) return@awaitEachGesture

                    var cumul = 0f
                    horizontalDrag(depart.id) { evenement ->
                        cumul += evenement.positionChange().x
                        val sens = sign(cumul)
                        val ecart = abs(cumul)
                        val libre = if (sens < 0) peutAllerApres else peutAllerAvant

                        if (!libre) {
                            // Rien de ce côté : le doigt tire, la page résiste
                            // au quart et ne franchit jamais.
                            portee.launch {
                                glisse.snapTo(sens * min(ecart / 4f, seuil))
                            }
                            return@horizontalDrag
                        }

                        // Résisté au tiers au-delà du seuil : il faut trois
                        // fois plus de doigt pour gagner le dépassement. C'est
                        // ce qui fait sentir la butée, et surtout la marge dont
                        // le désarmement a besoin pour être une intention et
                        // non un tremblement.
                        val gagne =
                            if (ecart > seuil) min((ecart - seuil) / 3f, depassementMax) else 0f

                        portee.launch {
                            glisse.snapTo(sens * (min(ecart, seuil) + gagne))
                            creux.snapTo(creuxMax * min(ecart / seuil, 1f) + gagne)
                        }

                        if (!arme && ecart >= seuil) {
                            arme = true
                            sensArme = sens
                            haptique.performHapticFeedback(
                                HapticFeedbackType.GestureThresholdActivate,
                            )
                        } else if (arme && ecart < seuil - jeu) {
                            // Le jeu évite qu'un doigt posé pile sur le seuil le
                            // franchisse et le refranchisse à chaque
                            // micro-mouvement, en vibrant à chaque passage.
                            arme = false
                            desarmer(vue, haptique)
                        }
                        evenement.consume()
                    }

                    val partait = arme
                    val sens = sensArme
                    arme = false
                    portee.launch {
                        if (partait) {
                            if (sens < 0) onApres() else onAvant()
                        }
                        // On revient toujours : c'est l'unité qui change
                        // dessous, pas la page qui traverse l'écran.
                        glisse.animateTo(0f, tween(RETOUR_MS))
                    }
                    portee.launch { creux.animateTo(0f, tween(RETOUR_MS)) }
                }
            },
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                // Ce que la page découvre en se creusant : le dessous, dans
                // l'ombre. Le croquis n'a pas de zone vide.
                .background(ONTColors.nuit.copy(alpha = 0.10f * min(creux.value / creuxMax, 1f))),
        )
        Box(
            modifier = Modifier
                .fillMaxSize()
                .clip(Feuillet(creux.value, aDroite = glisse.value < 0f))
                .background(ONTColors.background(com.labibleont.ont.designsystem.theme.LocalReadingTheme.current)),
        ) {
            contenu()
        }
    }
}

/** Douze pour cent de la largeur — relevés sur YouVersion. */
private const val PLAFOND = 0.12f

/**
 * La profondeur du creux au plafond, en dp.
 *
 * Le croquis donne une profondeur de la moitié de la hauteur du ventre, lequel
 * fait 55 % de la page. Sur un téléphone tenu en main, cette proportion
 * littérale donnerait une découpe énorme : on garde le caractère du dessin — un
 * ventre franc — à une échelle qui tient dans une page qu'on lit.
 */
private const val CREUX_MAX = 96f

/** Ce que le pli et le texte gagnent encore au-delà du seuil. */
private const val DEPASSEMENT_MAX = 26f

/** De combien on redescend sous le seuil avant de désarmer. */
private const val JEU_DE_DESARMEMENT = 5f

/**
 * La bande de bord qu'on laisse au système.
 *
 * Le retour depuis le bord est le geste le plus identitaire d'Android. Un
 * glissement qui y commence lui appartient, et l'app s'en écarte plutôt que de
 * le disputer — c'est le contournement que la communauté recommande, et il
 * préserve le geste au lieu de le confisquer.
 */
private const val BORD_SYSTEME = 32f

private const val RETOUR_MS = 260

/**
 * Le contour de la page, dont un bord se creuse en son milieu.
 *
 * Trois choses relevées au pixel sur le croquis, et qui font le dessin :
 *
 * * le creux n'occupe que **55 %** de la hauteur — le bord reste droit en haut
 *   et en bas, la page ne cède qu'où le doigt tire ;
 * * son centre est à **42 %**, donc au-dessus du milieu. Une symétrie parfaite
 *   se lit comme une découpe ; ce décalage la dément ;
 * * le ventre est **large**, en plateau — pas une pointe, une matière pleine
 *   qui s'étire. C'est le rôle de [PLATEAU], qui pousse les points de contrôle
 *   loin le long de la courbe.
 */
private data class Feuillet(val creux: Float, val aDroite: Boolean) : Shape {

    override fun createOutline(
        size: androidx.compose.ui.geometry.Size,
        layoutDirection: LayoutDirection,
        density: Density,
    ): Outline {
        val bord = if (aDroite) size.width else 0f
        val dos = if (aDroite) 0f else size.width
        val vers = if (aDroite) -1f else 1f

        val demi = size.height * HAUTEUR_DU_VENTRE / 2f
        val milieu = size.height * CENTRE_DU_VENTRE
        val debut = milieu - demi
        val fin = milieu + demi
        val pointeX = bord + vers * creux

        val trace = Path().apply {
            moveTo(dos, 0f)
            lineTo(bord, 0f)
            lineTo(bord, debut)
            cubicTo(
                bord, debut + (milieu - debut) * PLATEAU,
                pointeX, milieu - (milieu - debut) * PLATEAU,
                pointeX, milieu,
            )
            cubicTo(
                pointeX, milieu + (fin - milieu) * PLATEAU,
                bord, fin - (fin - milieu) * PLATEAU,
                bord, fin,
            )
            lineTo(bord, size.height)
            lineTo(dos, size.height)
            close()
        }
        return Outline.Generic(trace)
    }
}

/** La part de la hauteur que le creux occupe. */
private const val HAUTEUR_DU_VENTRE = 0.55f

/** Où son centre se tient, en part de la hauteur totale. */
private const val CENTRE_DU_VENTRE = 0.42f

/** Ce qui donne au ventre son plateau. Plus bas, on retombe sur une pointe. */
private const val PLATEAU = 0.62f

/**
 * Le retour du **désarmement** — la page ne tournera plus.
 *
 * Compose enrobe `GestureThresholdActivate` mais pas son inverse, alors que la
 * plateforme le porte depuis l'API 34. On descend donc à la constante système,
 * qui est la seule à donner le geste symétrique de l'armement : franchir le
 * seuil se sentait, revenir en deçà était muet — et c'est justement le moment
 * où le lecteur a besoin de savoir qu'il vient d'annuler.
 *
 * En dessous de 34, on retombe sur le cran discret de Compose : moins juste
 * sémantiquement, mais présent. Rien du tout serait pire.
 */
private fun desarmer(vue: android.view.View, haptique: androidx.compose.ui.hapticfeedback.HapticFeedback) {
    if (android.os.Build.VERSION.SDK_INT >= 34) {
        vue.performHapticFeedback(android.view.HapticFeedbackConstants.GESTURE_THRESHOLD_DEACTIVATE)
    } else {
        haptique.performHapticFeedback(HapticFeedbackType.SegmentTick)
    }
}
