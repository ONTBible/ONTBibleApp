package com.labibleont.ont.designsystem.metrics

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

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

/** L'échelle d'espacement du moment, suivant le curseur système. */
public val ontSpacing: ONTSpacing
    @Composable @ReadOnlyComposable
    get() = ONTSpacing(LocalDensity.current.fontScale)

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
