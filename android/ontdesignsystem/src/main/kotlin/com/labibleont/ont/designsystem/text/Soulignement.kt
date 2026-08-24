package com.labibleont.ont.designsystem.text

import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
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
 */
public fun Modifier.soulignerEnPointille(
    layout: () -> TextLayoutResult?,
    plages: () -> kotlin.collections.List<IntRange>,
    couleur: Color,
): Modifier = drawBehind {
    val mise = layout() ?: return@drawBehind
    val effet = PathEffect.dashPathEffect(
        // Un point et un blanc de même mesure : c'est ce qui se lit comme un
        // pointillé plutôt que comme un tiret.
        floatArrayOf(2.dpEnPx(density), 3.dpEnPx(density)),
        0f,
    )
    val epaisseur = 1.2f.dpEnPx(density)

    for (plage in plages()) {
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
