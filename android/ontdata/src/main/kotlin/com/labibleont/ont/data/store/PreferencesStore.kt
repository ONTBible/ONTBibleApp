package com.labibleont.ont.data.store

import android.content.Context
import com.labibleont.ont.kit.ports.PreferencesRepository
import com.labibleont.ont.kit.reader.DailyVerseSchedule
import com.labibleont.ont.kit.reader.ReadingFont
import com.labibleont.ont.kit.reader.ReadingPreferences
import com.labibleont.ont.kit.reader.ReadingTheme

/**
 * Les réglages du lecteur, sur son appareil.
 *
 * ## Relecture tolérante, délibérément
 *
 * Chaque champ est lu avec sa valeur de départ en secours. Un réglage
 * enregistré avant l'arrivée d'un champ se relit donc sans erreur, et surtout
 * **sans effacer les autres** : les réglages sont chez le lecteur, une clé
 * absente ne doit pas les remettre tous à zéro.
 *
 * C'est la même règle que côté iOS, où `ReadingPreferences` porte un décodeur
 * écrit à la main pour cette seule raison.
 *
 * ## Pourquoi pas DataStore
 *
 * DataStore est asynchrone, et ces valeurs sont lues pendant la composition —
 * à chaque recomposition du texte. Un flux qui n'a pas encore émis rendrait le
 * parchemin par défaut le temps d'une image, et le lecteur verrait son thème
 * clignoter à chaque ouverture. `SharedPreferences` est synchrone et tient en
 * mémoire après la première lecture.
 */
public class PreferencesStore(context: Context) : PreferencesRepository {

    private val prefs = context.getSharedPreferences("reglages-de-lecture", Context.MODE_PRIVATE)

    override var preferences: ReadingPreferences
        get() {
            val d = ReadingPreferences.DEFAUT
            return ReadingPreferences(
                showGloss = prefs.getBoolean(GLOSE, d.showGloss),
                showLevel3 = prefs.getBoolean(NIVEAU3, d.showLevel3),
                textSize = prefs.getFloat(TAILLE, d.textSize.toFloat()).toDouble(),
                lineSpacing = prefs.getFloat(INTERLIGNE, d.lineSpacing.toFloat()).toDouble(),
                theme = ReadingTheme.depuis(prefs.getString(THEME, null)),
                bodyFont = ReadingFont.depuis(prefs.getString(FONTE, null)),
                continuous = prefs.getBoolean(CONTINU, d.continuous),
                daily = DailyVerseSchedule.borne(
                    enabled = prefs.getBoolean(RAPPEL_ACTIF, d.daily.enabled),
                    hour = prefs.getInt(RAPPEL_HEURE, d.daily.hour),
                    minute = prefs.getInt(RAPPEL_MINUTE, d.daily.minute),
                ),
            )
        }
        set(value) {
            prefs.edit().apply {
                putBoolean(GLOSE, value.showGloss)
                putBoolean(NIVEAU3, value.showLevel3)
                putFloat(TAILLE, value.textSize.toFloat())
                putFloat(INTERLIGNE, value.lineSpacing.toFloat())
                putString(THEME, value.theme.cle)
                putString(FONTE, value.bodyFont.cle)
                putBoolean(CONTINU, value.continuous)
                putBoolean(RAPPEL_ACTIF, value.daily.enabled)
                putInt(RAPPEL_HEURE, value.daily.hour)
                putInt(RAPPEL_MINUTE, value.daily.minute)
            }.apply()
        }

    private companion object {
        // Les clés portent les noms du Swift : c'est ce que la synchronisation
        // de compte fait voyager d'un appareil à l'autre.
        const val GLOSE = "showGloss"
        const val NIVEAU3 = "showLevel3"
        const val TAILLE = "textSize"
        const val INTERLIGNE = "lineSpacing"
        const val THEME = "theme"
        const val FONTE = "bodyFont"
        const val CONTINU = "continuous"
        const val RAPPEL_ACTIF = "dailyEnabled"
        const val RAPPEL_HEURE = "dailyHour"
        const val RAPPEL_MINUTE = "dailyMinute"
    }
}
