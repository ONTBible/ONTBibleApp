package com.labibleont.ont.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.provideContent
import androidx.glance.action.actionStartActivity
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.labibleont.ont.MainActivity
import com.labibleont.ont.data.bundle.AssetDailyVerseRepository
import com.labibleont.ont.designsystem.tokens.ONTColors
import com.labibleont.ont.kit.reader.DailySelection
import java.time.Instant

/**
 * Le verset du jour sur l'écran d'accueil.
 *
 * ## Ce qu'iOS fait payer cher, Android le donne
 *
 * Un widget qui affiche du texte, se rafraîchit tout seul et ouvre l'app d'un
 * appui — sans extension séparée, sans cible de build à part, sans profil de
 * provisionnement. C'est le même code Kotlin que l'app, et il lit les mêmes
 * assets.
 *
 * ## Le budget mémoire est la vraie contrainte
 *
 * Un widget vit dans le processus du lanceur et dispose d'une allocation très
 * serrée. Le dépasser ne montre pas d'erreur : le widget affiche **du vide**,
 * et personne ne sait pourquoi.
 *
 * D'où le port séparé : `DailyVerseRepository` ne charge que `daily.json`,
 * 60 Ko de versets plats sans arbre d'inline. Passer par `CorpusRepository`
 * obligerait à décoder *Bereshit* — 750 Ko — pour afficher trois lignes.
 *
 * ## Le verset est le même que dans l'app, sans qu'ils se parlent
 *
 * `DailySelection` est une fonction pure de la date. L'app, la notification et
 * ce widget vivent dans trois processus qui ne communiquent pas ; ils tombent
 * pourtant sur le même verset le même jour, parce qu'ils font le même calcul.
 * Un tirage au sort ou un serveur les feraient diverger.
 */
public class VersetDuJourWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val vivier = AssetDailyVerseRepository(context).pool()
        val verset = DailySelection.verse(Instant.now(), vivier)

        provideContent {
            GlanceTheme {
                Contenu(
                    reference = verset?.reference,
                    texte = verset?.text,
                )
            }
        }
    }

    @Composable
    private fun Contenu(reference: String?, texte: String?) {
        // Le bordeaux de la marque en fond, l'or dessus : c'est la règle du
        // site, dont le bouton principal est `bg-or text-nuit`. Un widget ne
        // suit pas le thème de lecture — il est posé sur l'écran d'accueil du
        // lecteur, où il doit se reconnaître d'un coup d'œil.
        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .background(ONTColors.burgundy)
                .padding(16.dp)
                .clickable(actionStartActivity<MainActivity>()),
            verticalAlignment = Alignment.Vertical.CenterVertically,
        ) {
            if (reference == null || texte == null) {
                Text(
                    "La Bible ONT",
                    style = TextStyle(
                        color = ColorProvider(ONTColors.gold),
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Medium,
                    ),
                )
                return@Column
            }

            Text(
                reference,
                style = TextStyle(
                    color = ColorProvider(ONTColors.gold),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                ),
            )
            Spacer(GlanceModifier.height(6.dp))
            Text(
                texte,
                // Le corps seul, sans les gloses : un widget se lit d'un coup
                // d'œil, et celles de l'ONT font parfois quarante mots. Le
                // vivier ne porte d'ailleurs que le corps, pour cette raison.
                style = TextStyle(
                    color = ColorProvider(ONTColors.nuitEncre),
                    fontSize = 15.sp,
                ),
                maxLines = 6,
            )
        }
    }
}

/** Ce que le système instancie. */
public class VersetDuJourWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = VersetDuJourWidget()
}
