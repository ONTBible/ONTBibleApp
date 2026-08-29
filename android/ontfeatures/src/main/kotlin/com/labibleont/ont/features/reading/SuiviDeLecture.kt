package com.labibleont.ont.features.reading

import androidx.compose.runtime.Stable

/**
 * Ce que la liseuse sait de l'endroit où le lecteur en est.
 *
 * ## Ce qu'il répare
 *
 * La position de reprise n'était écrite qu'au **toucher** d'un verset — donc en
 * le sélectionnant. Qui lit en faisant défiler, sans jamais rien désigner, ne
 * déplaçait jamais sa reprise : « Reprendre » pointait le dernier verset touché,
 * parfois d'une tout autre séance. C'était l'usage principal, pas un cas limite.
 *
 * ## Pourquoi au verset et non au bloc
 *
 * Un premier correctif retenait le premier verset du **bloc** en tête d'écran,
 * parce que le bloc est l'élément de liste. En prose continue, un bloc est une
 * section entière dans un seul `Text` : la reprise ramenait alors au début de la
 * section au lieu de l'endroit qu'on lisait. iOS a connu exactement ce défaut et
 * l'a réparé — tant que les blocs valaient un verset, il ne se voyait pas, et
 * c'est la fusion en prose qui l'a révélé.
 *
 * ## Là où Android peut faire mieux qu'iOS, et le fait
 *
 * iOS estime la part de hauteur de chaque verset **au prorata des signes
 * affichés**, faute de pouvoir demander sa mise en page au moteur de texte : une
 * approximation qui vaut à un verset près, et qui se trompe entre un verset
 * serré et un verset aéré.
 *
 * Compose rend cette mise en page dans `TextLayoutResult`. On lit donc les
 * bornes **réelles** de chaque verset au lieu de les estimer. Le résultat est le
 * même à l'usage, il est simplement exact.
 *
 * ## La garde d'ouverture
 *
 * Reprise d'iOS telle quelle : tant que le lecteur n'a rien fait défiler,
 * [aRetenir] rend `null`. Ouvrir une unité, la lire sans bouger et la quitter ne
 * déplace donc pas la position — elle reste là où la restauration l'avait posée,
 * ce qui est exactement ce qu'on veut.
 */
@Stable
public class SuiviDeLecture {

    /**
     * Les bornes verticales de chaque verset, en coordonnées de la racine.
     *
     * ## Une carte ordinaire, et il faut que ça le reste
     *
     * Ni `mutableStateMapOf`, ni aucun état observable : rien ici ne doit
     * déclencher de recomposition. [situer] est appelée à chaque mise en page
     * de chaque bloc visible, c'est-à-dire très souvent pendant un défilement.
     *
     * Rendre cette carte observable coûterait une recomposition par entrée et
     * par sortie de verset — le prix se paierait par image, sur le geste le
     * plus courant de l'app. Le défilement vient tout juste d'être ramené à
     * 10 ms par image ; ce serait le premier endroit où il repartirait.
     *
     * iOS a exactement la même fragilité, pour la même raison : son
     * `SuiviDeLecture` est une classe ordinaire et non `@Observable`, et son
     * calcul de parts — 0,27 ms pour trente versets — ne tourne aujourd'hui
     * qu'à l'évaluation du corps. Le rendre observable les facturerait par
     * image des deux côtés.
     */
    private val bornes = sortedMapOf<Int, ClosedFloatingPointRange<Float>>()

    private var aDefile = false

    /** Le lecteur a touché au défilement — la position peut désormais bouger. */
    public fun defile() {
        aDefile = true
    }

    /** Où se trouve ce verset à l'écran. Appelé à chaque mise en page. */
    public fun situer(verset: Int, haut: Float, bas: Float) {
        if (bas > haut) bornes[verset] = haut..bas
    }

    /**
     * Ce verset n'est plus composé — on ne sait plus où il est.
     *
     * Sans cet oubli, ses bornes se figent à leur dernière valeur connue, qui
     * est **dans** la fenêtre puisque c'est là qu'il était quand on l'a mesuré
     * pour la dernière fois. Il resterait donc « visible » pour toujours, et
     * comme on retient le plus petit numéro, le verset 1 gagnerait à chaque
     * fois — quel que soit l'endroit où le lecteur est descendu.
     *
     * iOS n'a pas ce problème : sa sonde signale l'entrée **et la sortie** du
     * champ. Ici, la sortie du champ n'est pas un événement — c'est l'absence
     * d'événements. Il faut donc la prendre là où elle se manifeste : quand le
     * composable est mis au rebut.
     */
    public fun oublier(versets: Iterable<Int>) {
        versets.forEach(bornes::remove)
    }

    /** À l'ouverture d'une autre unité. */
    public fun recommence() {
        bornes.clear()
        aDefile = false
    }

    /**
     * Le verset à retenir — `nil` tant que le lecteur n'a rien fait défiler.
     *
     * Le plus petit numéro dont au moins la moitié est dans la fenêtre, comme le
     * seuil d'iOS. Un verset qui chevauche le bord haut sans y être à moitié
     * n'est pas celui qu'on lit : c'est celui qu'on vient de quitter.
     */
    public fun aRetenir(fenetreHaut: Float, fenetreBas: Float): Int? {
        if (!aDefile) return null
        return bornes.entries.firstOrNull { (_, borne) ->
            val hauteur = borne.endInclusive - borne.start
            val visible = minOf(borne.endInclusive, fenetreBas) - maxOf(borne.start, fenetreHaut)
            hauteur > 0f && visible / hauteur >= SEUIL
        }?.key
    }

    private companion object {
        /** Le seuil d'iOS — `onScrollVisibilityChange(threshold: 0.5)`. */
        const val SEUIL = 0.5f
    }
}
