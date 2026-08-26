package com.labibleont.ont

import android.provider.Settings
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.zIndex
import com.labibleont.ont.designsystem.surfaces.ONTSplash
import com.labibleont.ont.designsystem.surfaces.OUVERTURE_TOTALE
import android.app.Activity
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import com.labibleont.ont.designsystem.theme.LocalReadingTheme

/**
 * Pose l'ouverture par-dessus l'app, le temps qu'elle dure.
 *
 * ## Pourquoi une enveloppe plutôt qu'un écran de plus
 *
 * L'app se monte **derrière** pendant que l'ouverture joue. Elle a donc fini de
 * charger le corpus quand la montagne s'efface, et le lecteur ne subit pas deux
 * attentes l'une après l'autre. L'inverse — jouer puis monter — aurait rallongé
 * le démarrage de toute la durée de l'animation.
 *
 * ## Une fois par lancement, pas une fois par ouverture
 *
 * Aucun drapeau, aucun enregistrement. La composition n'est montée qu'une fois
 * par lancement de processus : revenir de l'arrière-plan ne rejoue rien, une app
 * tuée puis rouverte rejoue. Le système le donne tout seul.
 *
 * ## Ce qu'on n'a pas fait, et pourquoi
 *
 * On ne touche pas à la barre d'état. iOS la masque, parce qu'elle y restait
 * réglée sur le thème de lecture et se retrouvait en icônes sombres sur la
 * nuit. Ici, `ONTTheme` règle déjà la polarité des barres sur le thème — mais
 * l'ouverture est **toujours** sombre, quel que soit ce thème, donc les icônes
 * seraient sombres sur la nuit pendant cinq secondes.
 *
 * On les force donc en clair le temps de l'ouverture, et on les rend au thème
 * ensuite. Masquer eût été plus simple, mais fait sauter la mise en page à
 * l'apparition — et le lecteur voit alors l'app tressaillir juste au moment où
 * elle devait se poser.
 */
@Composable
internal fun AvecOuverture(contenu: @Composable () -> Unit) {
    var ouverte by remember { mutableStateOf(true) }
    val contexte = LocalContext.current

    // L'équivalent Android du « réduire le mouvement » d'iOS. Le lecteur qui
    // l'a demandé voit la montagne, pas le balayage — et il la voit moins
    // longtemps : l'attente et la rémanence n'ont plus rien à accompagner.
    val mouvementReduit = remember {
        Settings.Global.getFloat(
            contexte.contentResolver,
            Settings.Global.ANIMATOR_DURATION_SCALE,
            1f,
        ) == 0f
    }
    val duree = if (mouvementReduit) 1.2f else OUVERTURE_TOTALE

    // Le minutage est porté par une seule valeur qui va de 0 à 1 : c'est
    // `ONTSplash` qui sait ce qu'elle veut dire, et l'enveloppe n'a pas à
    // connaître les trois temps du dessin.
    //
    // `Animatable` et non `animateFloatAsState` : le second part **de** sa
    // cible et ne bouge que si elle change. Ici la cible est fixe — c'est le
    // temps qui passe —, donc il n'aurait rien animé du tout et le balayage
    // serait resté figé sur sa dernière image.
    //
    // Linéaire, délibérément : les trois courbes du dessin sont dans
    // `ONTSplash`, et une seconde en superposerait une quatrième.
    val avancement = remember { Animatable(0f) }

    // Les icônes de barre suivent le thème de lecture — `ONTTheme` s'en charge.
    // Mais l'ouverture est **toujours** sombre, quel que soit ce thème : sur le
    // parchemin, elles seraient donc sombres sur la nuit pendant cinq secondes.
    //
    // On les force en clair le temps de l'ouverture, et `ONTTheme` les reprend
    // ensuite — il suffit que la valeur redevienne celle du thème pour qu'elle
    // se réapplique.
    val vue = LocalView.current
    val themeDeLecture = LocalReadingTheme.current
    LaunchedEffect(ouverte, themeDeLecture) {
        val fenetre = (vue.context as? Activity)?.window ?: return@LaunchedEffect
        val controleur = WindowCompat.getInsetsController(fenetre, vue)
        // **Et on la rend.** `ONTTheme` ne repose la polarité que lorsque le
        // thème change ; il ne sait pas que l'ouverture vient de finir. Poser
        // sans rendre laissait donc les icônes blanches sur le parchemin — le
        // défaut même que `cdae6b8` avait corrigé, réintroduit par en dessous.
        val fondSombre = ouverte || themeDeLecture.isDark
        controleur.isAppearanceLightStatusBars = !fondSombre
        controleur.isAppearanceLightNavigationBars = !fondSombre
    }

    Box(Modifier.fillMaxSize()) {
        contenu()

        AnimatedVisibility(
            visible = ouverte,
            enter = androidx.compose.animation.EnterTransition.None,
            // Elle se dissout, elle ne glisse pas : ce qui s'efface est une
            // lumière, pas une page.
            exit = fadeOut(tween(450)),
            modifier = Modifier.zIndex(1f),
        ) {
            ONTSplash(
                avancement = avancement.value,
                mouvementReduit = mouvementReduit,
                modifier = Modifier
                    .fillMaxSize()
                    // Un appui l'écarte. Elle dure cinq secondes et demie, ce
                    // qui est long quand on ouvre l'app pour vérifier un
                    // verset : celui qui la connaît doit pouvoir passer outre
                    // sans que celui qui la découvre soit privé de la voir.
                    //
                    // Sans halo ni ondulation — une lueur qui se fait
                    // éclabousser par un cercle de pression cesse d'être une
                    // lueur.
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { ouverte = false }
                    .semantics { contentDescription = "Passer l'ouverture" },
            )
        }
    }

    LaunchedEffect(Unit) {
        avancement.animateTo(1f, tween((duree * 1000).toInt(), easing = LinearEasing))
        ouverte = false
    }
}
