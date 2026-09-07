package com.labibleont.ont.kit.account

import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64

/**
 * Le couple vérificateur / défi de PKCE.
 *
 * ## La porte qu'il ferme, et qui est plus ouverte ici que sur iOS
 *
 * Le code d'autorisation revient à l'app par un schéma d'URL personnalisé —
 * `ont://auth/callback`. **Sur Android, n'importe quelle app installée peut
 * déclarer le même schéma** et se voir proposer l'intention, dans une feuille
 * de choix que le lecteur traversera sans lire. Elle intercepterait le code, le
 * présenterait à *notre* backend, et obtiendrait une session en son nom.
 *
 * iOS attribue un schéma à une seule app ; Android laisse l'ambiguïté. Le même
 * mécanisme y est donc plus nécessaire, pas moins.
 *
 * PKCE le referme : l'app tire un secret au hasard — le **vérificateur** —,
 * n'en envoie que l'empreinte — le **défi** — au fournisseur, et ne révèle le
 * secret qu'au moment de l'échange. Un code volé sans son vérificateur ne vaut
 * rien.
 *
 * ## Ce que la RFC impose, et qu'on ne peut pas approximer
 *
 * Le défi est le SHA-256 du vérificateur, en base64 **URL-safe et sans
 * remplissage** (RFC 7636 §4.2). Les trois conditions comptent : un `+` ou un
 * `/` casse l'URL d'autorisation, un `=` de remplissage fait échouer la
 * comparaison chez le fournisseur. Et le message rendu ne dira jamais laquelle
 * des trois est en cause — seulement `invalid_grant`.
 */
public class Pkce private constructor(
    /** Le secret, gardé jusqu'à l'échange. */
    public val verificateur: String,
    /** L'empreinte, envoyée avec la demande d'autorisation. */
    public val defi: String,
) {
    public companion object {
        /** La longueur du secret, en octets avant encodage. */
        private const val OCTETS: Int = 32

        /**
         * Tire un couple neuf.
         *
         * `SecureRandom` et non `Random` : le vérificateur **est** le secret.
         * Un générateur prévisible le rendrait devinable, ce qui reviendrait à
         * n'avoir pas de PKCE tout en croyant l'avoir posé — la pire des trois
         * situations, puisque rien ne la signale.
         */
        public fun tirer(alea: SecureRandom = SecureRandom()): Pkce {
            val octets = ByteArray(OCTETS)
            alea.nextBytes(octets)
            val verificateur = base64Url(octets)
            return Pkce(verificateur, defiPour(verificateur))
        }

        /**
         * Le défi d'un vérificateur donné.
         *
         * Séparé du tirage pour être éprouvable : un couple tiré au hasard ne
         * se compare à rien, alors qu'un vérificateur connu a un défi connu —
         * et la RFC en publie un, qu'on reprend tel quel dans les tests.
         */
        public fun defiPour(verificateur: String): String {
            val empreinte = MessageDigest.getInstance("SHA-256")
                .digest(verificateur.toByteArray(Charsets.US_ASCII))
            return base64Url(empreinte)
        }

        private fun base64Url(octets: ByteArray): String =
            Base64.getUrlEncoder().withoutPadding().encodeToString(octets)
    }
}
