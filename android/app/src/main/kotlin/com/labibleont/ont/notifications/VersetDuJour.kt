package com.labibleont.ont.notifications

import android.Manifest
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.labibleont.ont.MainActivity
import com.labibleont.ont.ONTApplication
import com.labibleont.ont.R
import com.labibleont.ont.data.bundle.AssetDailyVerseRepository
import com.labibleont.ont.kit.reader.DailySelection
import com.labibleont.ont.kit.reader.DailyVerseSchedule
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.util.concurrent.TimeUnit

/**
 * Le verset du jour, posé par l'appareil.
 *
 * ## Rien ne sort du téléphone
 *
 * Le verset est **calculé** à partir de la date, pas reçu d'un serveur. Ni
 * requête, ni jeton, ni horaire de lecture qui remonterait quelque part. Pour
 * une app dont les annotations révèlent des convictions religieuses — catégorie
 * particulière au sens de l'article 9 du RGPD — c'est la seule conception
 * défendable.
 *
 * C'est aussi ce qui garantit que l'app, la notification et le widget tombent
 * sur le **même** verset le même jour, sans se parler : ce sont trois appels à
 * la même fonction pure.
 */
public class VersetDuJourWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val vivier = AssetDailyVerseRepository(applicationContext).pool()
        val verset = DailySelection.verse(Instant.now(), vivier) ?: return Result.success()

        // Depuis Android 13, notifier demande une permission. Sans elle on ne
        // relance pas et on ne se plaint pas : le lecteur a refusé, c'est une
        // réponse.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ActivityCompat.checkSelfPermission(
                applicationContext,
                Manifest.permission.POST_NOTIFICATIONS,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            return Result.success()
        }

        val ouvrir = PendingIntent.getActivity(
            applicationContext,
            0,
            Intent(applicationContext, MainActivity::class.java)
                .setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val notification = NotificationCompat.Builder(
            applicationContext,
            ONTApplication.CANAL_VERSET_DU_JOUR,
        )
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(verset.reference)
            // Le corps seul, sans les gloses : un verset du jour se lit d'une
            // traite, et celles de l'ONT font parfois quarante mots.
            .setContentText(verset.text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(verset.text))
            .setContentIntent(ouvrir)
            .setAutoCancel(true)
            .build()

        val gestionnaire =
            applicationContext.getSystemService(NotificationManager::class.java)
        gestionnaire?.notify(NOTIFICATION_ID, notification)
        return Result.success()
    }

    public companion object {
        private const val NOTIFICATION_ID = 1
        private const val TRAVAIL = "verset-du-jour"

        /**
         * Programme — ou déprogramme — le rappel.
         *
         * `KEEP` serait faux ici : changer l'heure doit remplacer le travail
         * existant, pas le laisser en place. `UPDATE` fait exactement ça.
         *
         * Le premier délai vise la prochaine occurrence de l'heure choisie,
         * pas « dans 24 heures » : un lecteur qui règle 7 h 30 à 7 h 00 doit
         * recevoir son verset une demi-heure plus tard, pas le lendemain.
         */
        public fun programmer(context: Context, rappel: DailyVerseSchedule) {
            val manager = WorkManager.getInstance(context)
            if (!rappel.enabled) {
                manager.cancelUniqueWork(TRAVAIL)
                return
            }

            val zone = ZoneId.systemDefault()
            val maintenant = java.time.ZonedDateTime.now(zone)
            val heure = LocalTime.of(rappel.hour, rappel.minute)
            var cible = maintenant.with(heure)
            if (!cible.isAfter(maintenant)) {
                cible = cible.plusDays(1)
            }
            val delai = Duration.between(maintenant, cible)

            val travail = PeriodicWorkRequestBuilder<VersetDuJourWorker>(1, TimeUnit.DAYS)
                .setInitialDelay(delai.toMinutes(), TimeUnit.MINUTES)
                .setConstraints(Constraints.Builder().build())
                .build()

            manager.enqueueUniquePeriodicWork(
                TRAVAIL,
                ExistingPeriodicWorkPolicy.UPDATE,
                travail,
            )
        }

        /** Le verset qui tombera aujourd'hui — pour l'afficher avant l'heure. */
        public fun apercu(context: Context, jour: LocalDate = LocalDate.now()): String? {
            val vivier = AssetDailyVerseRepository(context).pool()
            val zone = ZoneId.systemDefault()
            val instant = jour.atStartOfDay(zone).toInstant()
            return DailySelection.verse(instant, vivier)?.let { "${it.reference} — ${it.text}" }
        }
    }
}
