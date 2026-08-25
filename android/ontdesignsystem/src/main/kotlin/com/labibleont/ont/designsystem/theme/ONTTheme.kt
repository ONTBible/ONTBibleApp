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
 *
 * ## Ce refus est daté, et la porte reste ouverte
 *
 * Gloire l'a tranché le 25 août 2026 : on garde le refus **pour l'instant**,
 * et le lecteur pourra choisir plus tard. C'est le seul des chemins possibles
 * qui soit réversible — rester au refus ne ferme rien, tandis qu'ouvrir puis
 * refermer oblige à retrouver des ratios de contraste qu'on aura cessé de
 * mesurer.
 *
 * Si ce choix est un jour offert, il ne portera **pas** sur la surface de
 * lecture. Le parchemin et la nuit ne sont pas de la décoration : ce sont des
 * conditions de lecture, dont les contrastes sont mesurés plus bas dans ce
 * fichier. Une palette dérivée d'un fond d'écran est imprévisible par
 * construction — elle annulerait ces mesures sans que rien ne le signale, et
 * c'est un texte qu'on lit des heures.
 *
 * L'écriture ci-dessous s'y prête déjà : le schéma part de `darkColorScheme()`
 * ou `lightColorScheme()` puis surcharge. Un jour, la base pourra venir de
 * `dynamicColorScheme` sans que la liste des surcharges bouge — c'est
 * exactement ce qu'il faudrait pour n'ouvrir que le mobilier.
 *
 * ## Ce que Material reçoit désormais en plus
 *
 * `typography` et `shapes`, qui manquaient. Sans elles, tout composant Material
 * posé dans l'app repartait des valeurs de la bibliothèque — Roboto et les
 * arrondis par défaut — pendant qu'un design system complet dormait à côté.
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

    // On part du schéma de la bonne clarté pour que ce qu'on ne surcharge pas —
    // ondulations, états désactivés — tombe du bon côté, puis on impose **tous**
    // les rôles que Material peint.
    //
    // ## Pourquoi la liste est aussi longue
    //
    // Surcharger `primary` et `surface` ne suffit pas, et le défaut ne se voit
    // que sur un écran de réglages : les curseurs, les puces de choix et les
    // pastilles de sélection tirent leur fond des rôles `…Container`, restés au
    // **lavande** par défaut de Material. Du lavande dans une app dont la
    // palette vient d'un logo bordeaux et or.
    //
    // On ne peut pas les laisser tomber « à peu près juste » : un rôle non
    // défini n'est pas neutre, il porte une couleur inventée par la
    // bibliothèque. La règle est donc la même que pour `ONTColors` — une teinte
    // qui n'est pas la nôtre est une teinte qu'on n'a pas choisie.
    val base = if (theme.isDark) darkColorScheme() else lightColorScheme()
    val doux = ONTColors.inkSoft(theme)
    val schema = base.copy(
        primary = marque,
        onPrimary = ONTColors.onBrand(theme),
        primaryContainer = marque,
        onPrimaryContainer = ONTColors.onBrand(theme),
        inversePrimary = ONTColors.accent(theme),

        secondary = ONTColors.accent(theme),
        onSecondary = ONTColors.onBrand(theme),
        // Le fond d'une puce choisie : l'or très dilué, qui reste dans la
        // famille du parchemin au lieu d'y poser une autre matière.
        secondaryContainer = ONTColors.accent(theme).copy(alpha = 0.22f),
        onSecondaryContainer = encre,

        tertiary = ONTColors.accentuation(theme),
        onTertiary = ONTColors.onBrand(theme),
        tertiaryContainer = ONTColors.accentuation(theme).copy(alpha = 0.20f),
        onTertiaryContainer = encre,

        background = fond,
        onBackground = encre,
        surface = surface,
        onSurface = encre,
        surfaceVariant = surface,
        onSurfaceVariant = doux,
        surfaceTint = marque,
        inverseSurface = encre,
        inverseOnSurface = fond,

        surfaceContainerLowest = fond,
        surfaceContainerLow = fond,
        surfaceContainer = surface,
        surfaceContainerHigh = surface,
        surfaceContainerHighest = surface,
        surfaceDim = fond,
        surfaceBright = surface,

        outline = ONTColors.separator(theme),
        outlineVariant = ONTColors.separator(theme),
        scrim = ONTColors.nuit.copy(alpha = 0.6f),

        error = ONTColors.accentuation(theme),
        onError = ONTColors.onBrand(theme),
        errorContainer = ONTColors.accentuation(theme).copy(alpha = 0.20f),
        onErrorContainer = encre,
    )

    CompositionLocalProvider(LocalReadingTheme provides theme) {
        MaterialTheme(
            colorScheme = schema,
            typography = ONTChromeTypography,
            shapes = ONTShapes,
            content = content,
        )
    }
}
