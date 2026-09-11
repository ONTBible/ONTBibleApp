package com.labibleont.ont.designsystem.text

import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.TextLayoutResult

/**
 * Le pointillé de désignation, tracé sous le texte.
 *
 * ## Pourquoi il faut le dessiner
 *
 * iOS pose `Text.LineStyle(pattern: .dot)` sur la plage du verset et n'a plus
 * rien à faire. Compose n'a que `TextDecoration.Underline` — plein, sans motif.
 * Un trait plein serait une autre marque : il pèse autant qu'un surlignage,
 * alors que le pointillé **désigne** sans marquer.
 *
 * On le trace donc soi-même, à partir de la mise en page du texte. C'est ce qui
 * lui permet de suivre les retours à la ligne : une plage qui court sur quatre
 * lignes reçoit quatre segments, chacun borné au début et à la fin réels du
 * texte sur sa ligne — pas à la largeur du bloc.
 *
 * ## Sous le texte, jamais sous le numéro
 *
 * L'appelant exclut le numéro de verset de la plage. Il est en exposant : un
 * pointillé qui le rejoindrait ferait un décroché à chaque début de verset.
 * C'est la même règle que côté iOS, où seul le corps est souligné.
 *
 * ## Des valeurs, pas des lambdas
 *
 * Les deux premiers paramètres étaient des lambdas, appelées **dans** le
 * `drawBehind`. Lire un état depuis la phase de dessin l'y abonne — et comme
 * `onTextLayout` réécrit la mise en page à chaque passe, chaque image devenait :
 * la mise en page écrit, le dessin lit, le dessin s'invalide, et les glyphes
 * d'un texte haut de plusieurs écrans sont réenregistrés en entier.
 *
 * En recevant des **valeurs**, la lecture se fait là où le modificateur est
 * construit — en composition, qui est rare — et la phase de dessin ne s'abonne
 * plus à rien. Mesuré sur un Galaxy S20+ en défilant Bereshit 1 avec une
 * sélection active : 53 ms par image avec les lambdas, 16 ms avec les valeurs.
 */
public fun Modifier.soulignerEnPointille(
    layout: TextLayoutResult?,
    plages: kotlin.collections.List<IntRange>,
    couleur: Color,
): Modifier = drawBehind { pointille(layout, plages, couleur) }

/**
 * Le tracé lui-même, détaché du modificateur.
 *
 * Un `drawBehind` posé sur la chaîne du `Text` partage son nœud de dessin :
 * l'invalider réenregistre aussi **les glyphes**, et sur un texte haut de
 * plusieurs écrans ça coûte des dizaines de millisecondes par image. Un
 * `Canvas` frère a son propre nœud — le pointillé se redessine seul, sans
 * emporter le texte avec lui.
 *
 * Les deux formes existent parce que les deux cas diffèrent : en mode blocs,
 * chaque verset est un petit `Text` et le modificateur suffit ; en prose
 * continue, le texte est immense et il faut séparer.
 */
public fun DrawScope.pointille(
    layout: TextLayoutResult?,
    plages: kotlin.collections.List<IntRange>,
    couleur: Color,
) {
    val mise = layout ?: return
    val effet = PathEffect.dashPathEffect(
        // Un point et un blanc de même mesure : c'est ce qui se lit comme un
        // pointillé plutôt que comme un tiret.
        floatArrayOf(2.dpEnPx(density), 3.dpEnPx(density)),
        0f,
    )
    val epaisseur = 1.2f.dpEnPx(density)

    for (plage in plages) {
        if (plage.isEmpty()) continue
        val debut = plage.first.coerceIn(0, mise.layoutInput.text.length)
        val fin = plage.last.coerceIn(0, mise.layoutInput.text.length)
        if (debut >= fin) continue

        val premiereLigne = mise.getLineForOffset(debut)
        val derniereLigne = mise.getLineForOffset(fin)

        for (ligne in premiereLigne..derniereLigne) {
            val gauche = if (ligne == premiereLigne) {
                mise.getHorizontalPosition(debut, usePrimaryDirection = true)
            } else {
                mise.getLineLeft(ligne)
            }
            val droite = if (ligne == derniereLigne) {
                mise.getHorizontalPosition(fin, usePrimaryDirection = true)
            } else {
                mise.getLineRight(ligne)
            }
            if (droite <= gauche) continue

            // Juste sous la ligne de base, pas sous le bas de la ligne : entre
            // les deux il y a l'interligne, et un pointillé posé là flotterait
            // loin du texte qu'il désigne.
            val y = mise.getLineBaseline(ligne) + epaisseur * 2.5f

            drawLine(
                color = couleur,
                start = Offset(gauche, y),
                end = Offset(droite, y),
                strokeWidth = epaisseur,
                pathEffect = effet,
                cap = Stroke.DefaultCap,
            )
        }
    }
}

private fun Float.dpEnPx(density: Float): Float = this * density
private fun Int.dpEnPx(density: Float): Float = this * density

/**
 * Les plages d'un texte composé qui portent une **référence biblique**.
 *
 * ## Pourquoi elles se relisent au lieu d'être portées
 *
 * `ONTTextRenderer.compose` rend une `AnnotatedString`, et rien d'autre : c'est
 * ce qui lui permet d'être appelé depuis une quinzaine d'endroits sans qu'aucun
 * n'ait à savoir ce qu'il y a dedans. Lui faire rendre une paire — le texte et
 * ses plages — aurait obligé les quinze à défaire cette paire, y compris les
 * douze qui ne dessinent aucun pointillé.
 *
 * L'information voyage donc **dans** la chaîne, par l'étiquette du lien que la
 * référence pose déjà. Rien à ajouter à la composition, rien à changer aux
 * appelants qui ne s'en servent pas.
 *
 * Le pointillé s'arrête au fragment de la référence : il souligne « *Genèse*
 * 9:27 » et pas la phrase qui l'accueille.
 */
public fun AnnotatedString.plagesDeReference(): kotlin.collections.List<IntRange> =
    getLinkAnnotations(0, length).mapNotNull { plage ->
        val lien = plage.item as? LinkAnnotation.Clickable ?: return@mapNotNull null
        if (!lien.tag.startsWith(ONTTextRenderer.TAG_REFERENCE)) return@mapNotNull null
        (plage.start until plage.end).takeIf { !it.isEmpty() }
    }

/**
 * Le pointillé **ambre** des références, tracé sous un texte déjà composé.
 *
 * Séparé du pointillé de désignation parce que les deux ne portent ni la même
 * couleur ni le même sens : l'un est une propriété du texte — « ceci mène
 * ailleurs » —, l'autre un geste du lecteur qui vise un verset. Ils peuvent se
 * croiser sur la même ligne, et alors chacun garde sa teinte.
 */
public fun DrawScope.pointilleDesReferences(
    layout: TextLayoutResult?,
    texte: AnnotatedString,
    couleur: Color,
) {
    pointille(layout, texte.plagesDeReference(), couleur)
}

/** La forme modificateur, pour les textes qui n'ont pas de `Canvas` frère. */
public fun Modifier.soulignerLesReferences(
    layout: TextLayoutResult?,
    texte: AnnotatedString,
    couleur: Color,
): Modifier = soulignerEnPointille(layout, texte.plagesDeReference(), couleur)
