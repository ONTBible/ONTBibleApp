package com.labibleont.ont.designsystem.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ProvidableCompositionLocal
import androidx.compose.runtime.compositionLocalOf
import com.labibleont.ont.designsystem.tokens.ONTColors
import com.labibleont.ont.kit.reader.ReadingTheme

/**
 * Le thème de lecture en cours, disponible partout sans le passer de main en
 * main.
 *
 * Un `CompositionLocal` plutôt qu'un paramètre sur chaque composable : le thème
 * traverse tous les écrans et n'est jamais une décision locale. Le passer
 * explicitement obligerait chaque fonction intermédiaire à le déclarer, y
 * compris celles qui ne s'en servent pas — et la première qui l'oublierait
 * ferait retomber sa branche sur le parchemin sans rien dire.
 */
public val LocalReadingTheme: ProvidableCompositionLocal<ReadingTheme> =
    compositionLocalOf { ReadingTheme.PARCHMENT }

/**
 * La peau de l'app.
 *
 * ## Ce que Material reçoit, et ce qu'il ne reçoit pas
 *
 * Material 3 sert ici de **mécanique** — feuilles du bas, ondulations,
 * dimensions de touche, retour prédictif. Sa palette, en revanche, est
 * entièrement remplacée par la nôtre : `colorScheme` est construit à partir
 * d'[ONTColors], jamais de `dynamicColorScheme`.
 *
 * C'est le refus assumé de **Material You**. La couleur dynamique repeindrait
 * l'app aux teintes du fond d'écran du lecteur ; ces couleurs-ci viennent du
 * logo et de `main.css` du site, et les trois dépôts les partagent. Un lecteur
 * qui ouvre l'ONT doit y trouver l'ONT.
 */
@Composable
public fun ONTTheme(
    theme: ReadingTheme = ReadingTheme.PARCHMENT,
    content: @Composable () -> Unit,
) {
    val fond = ONTColors.background(theme)
    val encre = ONTColors.ink(theme)
    val marque = ONTColors.brandInk(theme)
    val surface = ONTColors.surface(theme)

    // On part du schéma de la bonne clarté pour que les composants Material
    // qu'on ne surcharge pas — ondulations, états désactivés — tombent du bon
    // côté, puis on impose les rôles qui portent la marque.
    val base = if (theme.isDark) darkColorScheme() else lightColorScheme()
    val schema = base.copy(
        primary = marque,
        onPrimary = ONTColors.onBrand(theme),
        secondary = ONTColors.accent(theme),
        background = fond,
        onBackground = encre,
        surface = surface,
        onSurface = encre,
        surfaceVariant = surface,
        onSurfaceVariant = ONTColors.inkSoft(theme),
        outline = ONTColors.separator(theme),
        error = ONTColors.accentuation(theme),
    )

    CompositionLocalProvider(LocalReadingTheme provides theme) {
        MaterialTheme(colorScheme = schema, content = content)
    }
}
