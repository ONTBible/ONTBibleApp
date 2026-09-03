package com.labibleont.ont.data.account

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.labibleont.ont.kit.account.Session
import com.labibleont.ont.kit.ports.Reporter
import com.labibleont.ont.kit.ports.SilentReporter

/**
 * Où dorment les jetons.
 *
 * ## Pourquoi pas le fichier du lecteur
 *
 * `lecteur.json` porte les surlignages, les notes et les réglages en clair, et
 * c'est acceptable : ce sont ses données à lui, sur son appareil. Un jeton
 * d'accès n'est pas de cette nature — c'est **une clé qui ouvre son compte
 * depuis n'importe où**. Sur un appareil rooté ou sauvegardé en clair, le
 * premier ne coûte que la vie privée d'un lecteur ; le second donne son compte.
 *
 * `EncryptedSharedPreferences` chiffre clés et valeurs avec une clé maîtresse
 * que le Keystore garde — et sur la plupart des appareils, dans un composant
 * dédié dont elle ne sort jamais. C'est l'équivalent du trousseau d'iOS.
 *
 * On ne l'écrit pas soi-même. Un stockage de jetons est exactement le code
 * qu'on ne bricole pas.
 *
 * ## Ce qui arrive quand le coffre ne s'ouvre pas
 *
 * Il arrive qu'il ne s'ouvre pas : clé maîtresse invalidée par un changement
 * de verrouillage d'écran, sauvegarde restaurée sur un autre appareil, Keystore
 * en défaut. Le repli n'est pas de basculer en clair — ce serait troquer une
 * panne visible contre une fuite invisible. On **oublie la session** : le
 * lecteur se reconnecte, ce qui coûte un geste et ne perd rien, puisque ses
 * marques vivent dans `lecteur.json`.
 */
public class CoffreDeJetons(
    context: Context,
    private val rapporteur: Reporter = SilentReporter,
) {
    private val prefs: SharedPreferences? = runCatching {
        val cle = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            "compte",
            cle,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }.onFailure {
        // Sans cette remontée, un coffre qui ne s'ouvre jamais se présenterait
        // comme « le lecteur n'est jamais connecté » — un symptôme qu'on
        // chercherait du côté de l'authentification pendant des heures.
        rapporteur.report(it, "ouverture du coffre à jetons")
    }.getOrNull()

    /** La session gardée, ou `null` — jamais une exception. */
    public fun lire(): Session? {
        val p = prefs ?: return null
        val acces = p.getString(ACCES, null) ?: return null
        val rafraichissement = p.getString(RAFRAICHISSEMENT, null) ?: return null
        val expiration = p.getLong(EXPIRATION, 0L)
        if (expiration == 0L) return null
        return Session(acces, rafraichissement, expiration, creation = false)
    }

    public fun ecrire(session: Session) {
        prefs?.edit()
            ?.putString(ACCES, session.jetonDAcces)
            ?.putString(RAFRAICHISSEMENT, session.jetonDeRafraichissement)
            ?.putLong(EXPIRATION, session.expiration)
            ?.apply()
    }

    /**
     * Efface, et efface **vraiment**.
     *
     * `clear()` plutôt que trois `remove()` : le jour où un quatrième champ
     * s'ajoutera, une liste à recopier l'oubliera exactement une fois — et ce
     * qui resterait serait un morceau de jeton.
     */
    public fun effacer() {
        prefs?.edit()?.clear()?.apply()
    }

    private companion object {
        const val ACCES = "acces"
        const val RAFRAICHISSEMENT = "rafraichissement"
        const val EXPIRATION = "expiration"
    }
}
