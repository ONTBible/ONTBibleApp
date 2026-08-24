package com.labibleont.ont

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build

/**
 * L'application, et la racine de composition.
 *
 * Elle déclare les canaux de notification au démarrage — c'est le seul moment
 * où Android accepte de les créer, et les recréer est sans effet, donc c'est
 * aussi sans risque.
 */
public class ONTApplication : Application() {

    override fun onCreate() {
        super.onCreate()
        declarerLesCanaux()
    }

    /**
     * Deux canaux, et c'est la réponse d'Android à un problème qu'iOS pose.
     *
     * Sur iOS, le verset du jour et les parutions demandent **la même**
     * autorisation système : le lecteur qui n'en veut qu'un doit couper les
     * deux, ou tout garder. La liseuse a dû construire deux écrans de réglage
     * pour rendre la distinction lisible.
     *
     * Ici, ce sont deux canaux. Le lecteur les règle séparément depuis les
     * réglages du système, coupe l'un sans l'autre, choisit un son pour l'un et
     * le silence pour l'autre. On n'a rien à construire — il faut seulement les
     * déclarer, et ne pas les confondre.
     *
     * La différence de nature justifie la séparation : le verset du jour est
     * **local**, posé par l'appareil à une heure choisie ; une parution est
     * **poussée** par le serveur quand un livre paraît.
     */
    private fun declarerLesCanaux() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val gestionnaire = getSystemService(NotificationManager::class.java) ?: return

        gestionnaire.createNotificationChannel(
            NotificationChannel(
                CANAL_VERSET_DU_JOUR,
                "Verset du jour",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Un passage chaque matin, à l'heure que vous choisissez."
            },
        )

        gestionnaire.createNotificationChannel(
            NotificationChannel(
                CANAL_PARUTIONS,
                "Parutions",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Quand un livre ou un chapitre paraît."
            },
        )
    }

    public companion object {
        /** Local, posé par l'appareil à l'heure choisie par le lecteur. */
        public const val CANAL_VERSET_DU_JOUR: String = "verset-du-jour"

        /** Poussé par le serveur quand le corpus s'enrichit. */
        public const val CANAL_PARUTIONS: String = "parutions"
    }
}
