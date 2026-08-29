package com.labibleont.ont.designsystem.surfaces

import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Shader
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.platform.LocalDensity
import com.labibleont.ont.kit.reader.ReadingTheme
import kotlin.random.Random

/**
 * Le grain de la nuit — `grain-page` du site.
 *
 * ## Ce n'est pas un effet
 *
 * La webapp le documente comme une **nécessité technique** : un dégradé sombre
 * étalé sur une page se découpe en bandes, parce qu'un écran n'a que 256
 * valeurs par canal et que l'écart entre deux nuances de nuit est plus petit
 * que ça. Le bruit casse les bandes.
 *
 * La liseuse pose un aplat et non un dégradé, donc elle n'a pas ce défaut à
 * corriger. Ce qu'elle emprunte est le second effet, que le site mentionne en
 * passant : le grain donne **la matière d'un papier ancien**. C'est ce qui
 * distingue la nuit d'aubergine d'un simple fond sombre — sans lui, « mystique »
 * n'est qu'un thème sombre de plus.
 *
 * ## Une seule tuile, fabriquée une fois
 *
 * On tire un bruit monochrome dans une tuile de 128 points, **une fois pour la
 * vie de la composition**, et on la répète. La refaire à chaque image coûterait
 * un tirage par image de défilement, pour un résultat que l'œil ne distingue
 * pas.
 *
 * La tuile est tirée à l'échelle de la dalle : à 1× sur un écran 3×, le grain
 * devient un damier visible au lieu d'un bruit.
 */
public object ONTGrain {

    /**
     * 3,5 %, la valeur du site.
     *
     * Au-delà, on voit le bruit ; en deçà, on ne voit plus la matière.
     */
    public const val OPACITY: Float = 0.035f

    private const val COTE = 128

    /**
     * Pose le grain derrière le contenu.
     *
     * **Seulement sur la nuit.** Sur un parchemin, le grain se verrait comme
     * une salissure — le papier est déjà dans la couleur du fond.
     */
    @Composable
    public fun modifier(theme: ReadingTheme): Modifier {
        if (theme != ReadingTheme.MYSTIQUE) return Modifier

        val echelle = LocalDensity.current.density
        val tuile = remember(echelle) { tirer(echelle) }
        val shader = remember(tuile) {
            BitmapShader(tuile, Shader.TileMode.REPEAT, Shader.TileMode.REPEAT)
        }
        val peinture = remember(shader) {
            android.graphics.Paint().apply {
                this.shader = shader
                alpha = (OPACITY * 255).toInt()
            }
        }

        return Modifier.drawBehind { dessiner(peinture) }
    }

    private fun DrawScope.dessiner(peinture: android.graphics.Paint) {
        drawContext.canvas.nativeCanvas.drawRect(
            0f,
            0f,
            size.width,
            size.height,
            peinture,
        )
    }

    /**
     * Le bruit lui-même.
     *
     * Monochrome et **déterministe pour une échelle donnée** : deux écrans de
     * la même densité montrent le même grain, ce qui évite qu'un widget et
     * l'app posés côte à côte n'aient pas la même matière.
     */
    private fun tirer(echelle: Float): Bitmap {
        val cote = (COTE * echelle).toInt().coerceAtLeast(COTE)
        // Graine fixe : le grain doit être le même d'un lancement à l'autre.
        val alea = Random(20260824)
        val pixels = IntArray(cote * cote)
        for (i in pixels.indices) {
            // Un gris tiré uniformément. L'opacité de 3,5 % est ce qui le rend
            // à peine perceptible ; c'est elle qui règle la force, pas
            // l'amplitude du tirage.
            val v = alea.nextInt(256)
            pixels[i] = (0xFF shl 24) or (v shl 16) or (v shl 8) or v
        }
        return Bitmap.createBitmap(pixels, cote, cote, Bitmap.Config.ARGB_8888)
    }
}
