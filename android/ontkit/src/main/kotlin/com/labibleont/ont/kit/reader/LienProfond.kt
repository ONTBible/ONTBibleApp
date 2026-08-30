package com.labibleont.ont.kit.reader

/**
 * Ce qu'une adresse `ont://` demande d'ouvrir.
 *
 * ## Dans le domaine, et pas dans l'activité
 *
 * Une URL arrive de l'extérieur — d'une notification, d'un widget, d'une
 * conversation, ou de quelqu'un qui l'a retapée à la main. La comprendre est
 * une règle du projet, pas une affaire de plateforme : iOS et Android doivent
 * lire le même lien de la même façon, sinon un passage partagé depuis un
 * téléphone n'ouvre pas le même endroit sur l'autre.
 *
 * Et c'est ici que ça s'éprouve sans appareil.
 */
public sealed interface LienProfond {

    /** `ont://read` — la liseuse, là où elle en était. */
    public data object Lecture : LienProfond

    /** `ont://read/{livre}` — le livre, sa table des unités. */
    public data class Livre(val livreId: String) : LienProfond

    /**
     * `ont://read/{livre}/{unité}` — une unité, éventuellement à un verset près.
     *
     * @param versets les versets désignés. Vide veut dire « l'unité entière »,
     *   ce qui est le cas de tous les liens partagés avant que le paramètre
     *   n'existe.
     */
    public data class Unite(
        val livreId: String,
        val uniteId: String,
        val versets: Set<Int> = emptySet(),
        /**
         * `ont://share/…` — ouvrir **et** lever la feuille de partage.
         *
         * C'est le retour du partage : on revient sur le passage désigné avec
         * la feuille déjà levée, plutôt que d'obliger à refaire le geste.
         */
        val partager: Boolean = false,
    ) : LienProfond

    public companion object {
        /** Le schéma interne — widget, notification, fiche de lexique. */
        public const val SCHEMA: String = "ont"

        /**
         * L'hôte des liens **publics**, ceux qui circulent réellement.
         *
         * Un `ont://` collé dans une conversation n'est pas cliquable et ne
         * mène nulle part pour qui n'a pas l'app. Le lien qu'on partage est
         * donc une adresse web, que le site sait servir de son côté :
         *
         *     https://ontbible.com/fr/lire/bereshit/bereshit-1?v=1-3
         *
         * Le segment de langue est **ignoré**. Il existe pour épargner une
         * migration le jour d'une édition anglaise, et un lien d'une autre
         * langue doit ouvrir le même passage plutôt que de ne rien faire.
         */
        public const val HOTE: String = "ontbible.com"

        /**
         * Lit une adresse, ou rend `null`.
         *
         * ## Tolérante, comme [VerseRange.parse]
         *
         * Une adresse vient toujours du dehors. Elle peut avoir été tronquée
         * par une messagerie, recopiée à la main, ou fabriquée. On ne lève donc
         * jamais : ce qui se comprend est rendu, le reste est ignoré.
         *
         * `null` ne signifie pas « adresse malformée » mais « rien à ouvrir » —
         * l'appelant lance alors l'app normalement, ce qui est toujours mieux
         * qu'un écran vide.
         *
         * Le paramètre `v` réemploie [VerseRange.parse] plutôt que d'analyser
         * les intervalles ici : c'est la même grammaire que celle affichée dans
         * un renvoi — « Bereshit 1:1-3, 7 » —, et deux implémentations d'un
         * même format finiraient par diverger.
         */
        public fun lire(adresse: String): LienProfond? {
            val nette = adresse.trim()
            val corps = when {
                nette.startsWith("$SCHEMA://") -> nette.removePrefix("$SCHEMA://")
                else -> web(nette) ?: return null
            }

            val chemin = corps.substringBefore('?')
            val requete = corps.substringAfter('?', "")

            val segments = chemin.split('/')
                .map { decoder(it) }
                .filter { it.isNotBlank() }

            val verbe = segments.firstOrNull()
            if (verbe != "read" && verbe != "share") return null

            val livre = segments.getOrNull(1) ?: return Lecture
            val unite = segments.getOrNull(2) ?: return Livre(livre)
            return Unite(livre, unite, versetsDe(requete), partager = verbe == "share")
        }

        /**
         * Ramène une adresse web à la forme interne, ou rend `null`.
         *
         * `https://ontbible.com/fr/lire/bereshit/bereshit-1` devient
         * `read/bereshit/bereshit-1` — le segment de langue tombe, quel qu'il
         * soit, et `lire` reprend la main sans savoir d'où venait l'adresse.
         */
        private fun web(adresse: String): String? {
            val sansSchema = adresse
                .removePrefix("https://")
                .removePrefix("http://")
                .takeIf { it != adresse }
                ?: return null

            val hote = sansSchema.substringBefore('/').removePrefix("www.")
            if (!hote.equals(HOTE, ignoreCase = true)) return null

            val reste = sansSchema.substringAfter('/', "")
            val chemin = reste.substringBefore('?')
            val requete = reste.substringAfter('?', "")

            val segments = chemin.split('/').map { decoder(it) }.filter { it.isNotBlank() }
            // Le verbe est « lire » sur le site, « read » à l'intérieur. La
            // langue le précède et ne nous regarde pas.
            val i = segments.indexOfFirst { it == "lire" || it == "read" }
            if (i < 0) return null

            val suite = segments.drop(i + 1).joinToString("/")
            val base = if (suite.isEmpty()) "read" else "read/$suite"
            return if (requete.isEmpty()) base else "$base?$requete"
        }

        /** Écrit l'adresse d'un passage — l'inverse exact de [lire]. */
        public fun ecrire(
            livreId: String,
            uniteId: String,
            versets: Set<Int> = emptySet(),
        ): String {
            val base = "$SCHEMA://read/$livreId/$uniteId"
            val renvoi = VerseRange.label(versets)
            // L'espace de « 1-3, 7 » n'a rien à faire dans une adresse : il
            // s'encoderait en `%20` et rendrait le lien illisible dans une
            // conversation, où on le voit avant de le toucher.
            return if (renvoi.isEmpty()) base else "$base?v=${renvoi.replace(" ", "")}"
        }

        private fun versetsDe(requete: String): Set<Int> =
            requete.split('&')
                .firstOrNull { it.startsWith("v=") }
                ?.removePrefix("v=")
                ?.let { VerseRange.parse(decoder(it)) }
                .orEmpty()

        /**
         * Le décodage minimal des séquences `%XX`.
         *
         * Écrit ici plutôt que pris à la plateforme : `ontkit` est un module
         * JVM pur, sans Android ni Foundation. Une virgule encodée en `%2C` par
         * une messagerie doit redevenir une virgule, sans quoi « 1-3,7 » se
         * perd en route.
         */
        private fun decoder(brut: String): String {
            if ('%' !in brut) return brut
            val sortie = StringBuilder(brut.length)
            var i = 0
            while (i < brut.length) {
                val c = brut[i]
                if (c == '%' && i + 2 < brut.length) {
                    val octet = brut.substring(i + 1, i + 3).toIntOrNull(16)
                    if (octet != null) {
                        sortie.append(octet.toChar())
                        i += 3
                        continue
                    }
                }
                sortie.append(c)
                i++
            }
            return sortie.toString()
        }
    }
}
