package com.labibleont.ont.designsystem.metrics

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * L'échelle d'espacement.
 *
 * ## Elle grandit avec le curseur d'accessibilité
 *
 * Les valeurs sont multipliées par `fontScale`, le réglage système de taille de
 * texte. Pour une liseuse — et pour un lectorat qui n'a pas vingt ans — une
 * grille en points fixes est un **défaut d'accessibilité**, pas un détail de
 * style : le texte grandit, les marges restent, et la page se serre jusqu'à ce
 * que les lignes se touchent.
 *
 * C'est le pendant des `@ScaledMetric` d'iOS. Compose ne les a pas : `sp` suit
 * le curseur, `dp` non. Il faut donc l'appliquer soi-même, et c'est le genre de
 * chose qu'on n'ajoute jamais après coup.
 *
 * N'employer ces jetons que là où on aurait écrit un nombre au jugé.
 */
public class ONTSpacing internal constructor(private val facteur: Float) {
    /** 4 — l'écart le plus serré : icône et libellé, intérieur d'une pastille. */
    public val xs: Dp get() = 4.dp * facteur

    /** 8 — un groupe lié : un titre au-dessus de son sous-titre. */
    public val s: Dp get() = 8.dp * facteur

    /** 12 — marges d'une ligne, intérieur d'une carte. */
    public val m: Dp get() = 12.dp * facteur

    /** 16 — la marge par défaut d'une vue. */
    public val l: Dp get() = 16.dp * facteur

    /** 22 — les marges latérales d'une page de lecture. */
    public val page: Dp get() = 22.dp * facteur

    /** 24 — séparation entre sections. */
    public val xl: Dp get() = 24.dp * facteur

    /** 32 — respiration en tête d'écran. */
    public val xxl: Dp get() = 32.dp * facteur

    /**
     * Une mesure quelconque, mise à l'échelle.
     *
     * Pour ce qui ne se met pas en jetons : le côté d'une icône, le minimum
     * d'une case. Le corps **et** le cadre qui le contient, toujours ensemble —
     * un symbole qui grandit dans une pastille figée en déborde.
     */
    public operator fun invoke(points: Int): Dp = points.dp * facteur
}

/**
 * L'échelle d'espacement, mesurée sur le texte qu'elle accompagne.
 *
 * ## Pourquoi pas `fontScale`
 *
 * On multipliait les `dp` par `LocalDensity.current.fontScale`. C'était juste
 * jusqu'à Android 14, qui a rendu la mise à l'échelle du texte **non
 * linéaire** — et pas d'une seule façon : le facteur dépend de la taille.
 * Mesuré sur `ONT-Pixel9`, curseur système au maximum :
 *
 * ```
 * fontScale=2.00  |  11sp ×2.000  13sp ×1.923  16sp ×1.750  22sp ×1.591  34sp ×1.222
 * fontScale=1.50  |  11sp ×1.500  13sp ×1.538  16sp ×1.438  22sp ×1.227  34sp ×1.000
 * ```
 *
 * Un petit texte grossit pleinement, un grand titre presque pas — à 1,5, un
 * titre de 34 sp ne bouge pas d'un point. C'est délibéré : au bout du curseur,
 * ce qui doit devenir lisible est le corps, pas les titres, et l'échelle
 * typographique se comprime.
 *
 * Conséquence : `fontScale` annonce 2,0 quand le corps ne grossit que de 1,75.
 * Des marges multipliées par 2,0 autour d'un texte grossi de 1,75 se
 * désaccordent de 14 % — précisément au réglage employé par ceux qui montent
 * le curseur parce qu'ils ne voient pas autrement. La documentation d'Android
 * le dit sans détour : `fontScale` n'est plus qu'indicatif.
 *
 * ## Ce qu'on fait à la place
 *
 * On ne modélise pas la courbe — ni logarithme, ni table recopiée, qui
 * divergeraient à la première révision d'Android. **On demande.**
 * `taille.sp.toDp()` fait passer la conversion réelle, courbe comprise, et le
 * rapport obtenu est le facteur exact appliqué à ce texte-là.
 *
 * Sous Android 14 la conversion est linéaire, et le rapport rend `fontScale` :
 * aucun test de version à écrire.
 *
 * @param taille la taille du texte, en `sp`, que cet espacement entoure.
 */
@Composable
@ReadOnlyComposable
public fun ontSpacingPour(taille: Float): ONTSpacing {
    val densite = LocalDensity.current
    val rendu = with(densite) { taille.sp.toDp().value }
    return ONTSpacing(rendu / taille)
}

/**
 * L'échelle d'espacement du mobilier.
 *
 * Calée sur 16 sp — `bodyLarge`, le corps du mobilier. Une page de lecture
 * doit employer [ontSpacingPour] avec la taille choisie par le lecteur : ses
 * marges accompagnent son texte à lui, qui peut être à deux fois cette
 * taille-ci.
 */
public val ontSpacing: ONTSpacing
    @Composable @ReadOnlyComposable
    get() = ontSpacingPour(16f)

/** Les rayons de courbure. */
public object ONTRadius {
    /** Pastilles et étiquettes. */
    public val pill: Dp = 999.dp

    /** Surlignage d'un verset — juste assez pour adoucir l'angle. */
    public val highlight: Dp = 6.dp

    /** Blocs secondaires. */
    public val block: Dp = 18.dp

    /** Cartes de premier plan. */
    public val card: Dp = 22.dp
}

/** La largeur de lecture. */
public object ONTLayout {
    /**
     * Au-delà, une ligne devient trop longue pour que l'œil retrouve le début
     * de la suivante. Vaut surtout sur tablette, où rien ne limiterait sinon.
     */
    public val readingWidth: Dp = 700.dp

    /**
     * La largeur d'une **page** — listes, cartes, réglages.
     *
     * Plus large que la mesure du texte suivi, et c'est délibéré : une liste ne
     * se lit pas comme une phrase. L'œil n'y court pas d'un bout à l'autre, il
     * saute d'un intitulé à sa valeur.
     */
    public val pageWidth: Dp = 850.dp

    /**
     * La largeur d'une carte — celle qu'elle a sur téléphone.
     *
     * Étalée sur la colonne d'une tablette, la carte du verset passait d'un
     * rapport de 1,56 à 3,4 — une bande, où le verset ne tenait plus que sur
     * deux lignes traversant l'écran. Elle garde donc sa mesure d'un appareil à
     * l'autre, ce qui la maintient aussi jumelle de la pastille du widget.
     */
    public val cardWidth: Dp = 362.dp
}
