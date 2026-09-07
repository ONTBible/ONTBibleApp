package com.labibleont.ont.kit.account

/**
 * Ce que le fournisseur renvoie à l'app, lu sans rien supposer.
 *
 * ## Pourquoi c'est un type du domaine et non trois lignes dans l'activité
 *
 * L'adresse arrive **du dehors**. Elle peut avoir été fabriquée par une autre
 * app qui a déclaré le même schéma, tronquée, ou porter une erreur du
 * fournisseur au lieu d'un code. Une lecture faite au fil de l'eau dans un
 * `when` finirait par traiter « pas de code » et « code vide » différemment,
 * sans que personne l'ait décidé.
 *
 * Ici, une adresse qui n'est pas un retour d'autorisation rend `null`, et une
 * qui en est un rend soit un code, soit un refus. Il n'y a pas de quatrième cas.
 */
public sealed interface RetourDAutorisation {

    /** Le fournisseur a accordé : voici le code à échanger. */
    public data class Accorde(
        public val fournisseur: Fournisseur,
        public val code: String,
    ) : RetourDAutorisation

    /**
     * Le fournisseur a refusé, ou le lecteur a fermé la page.
     *
     * Les deux arrivent par le même chemin et se distinguent mal : `access_denied`
     * est ce que Google rend quand on ferme l'onglet comme quand on refuse
     * l'autorisation. On ne prétend donc pas les séparer.
     */
    public data object Refuse : RetourDAutorisation

    public companion object {
        /** Le chemin que le backend fait suivre à l'app. */
        private const val PREFIXE: String = "ont://auth/callback"

        /**
         * Lit une adresse reçue, ou rend `null` si ce n'en est pas une.
         *
         * `null` ne veut pas dire « mal formée » mais **« ce n'est pas pour
         * moi »** : l'app reçoit aussi des liens de lecture par le même canal,
         * et confondre les deux ferait avaler un renvoi biblique par le flux de
         * connexion.
         */
        public fun lire(adresse: String?): RetourDAutorisation? {
            val brute = adresse?.trim() ?: return null
            if (!brute.startsWith(PREFIXE)) return null

            val parametres = parametres(brute.substringAfter('?', ""))
            val fournisseur = parametres["provider"]
                ?.let { cle -> Fournisseur.entries.firstOrNull { it.cle == cle } }
            val code = parametres["code"]

            // L'ordre compte : une adresse qui porte une erreur **et** un code
            // est un refus. Lire le code d'abord ferait tenter un échange que le
            // fournisseur a déjà décliné.
            if (parametres.containsKey("error")) return Refuse
            if (fournisseur == null || code.isNullOrEmpty()) return Refuse
            return Accorde(fournisseur, code)
        }

        /**
         * Découpe une chaîne de requête.
         *
         * Écrit à la main plutôt que par `Uri.parse` : ce fichier vit dans un
         * module JVM pur, donc éprouvable sans appareil — et c'est justement le
         * genre de lecture qu'on veut pouvoir malmener avec des entrées
         * tordues.
         */
        private fun parametres(requete: String): Map<String, String> =
            requete.split('&')
                .filter { it.isNotEmpty() }
                .mapNotNull { morceau ->
                    val nom = morceau.substringBefore('=')
                    val valeur = morceau.substringAfter('=', "")
                    if (nom.isEmpty()) null else nom to decoder(valeur)
                }
                .toMap()

        /** Décodage de pourcentage, et le `+` qui vaut une espace. */
        private fun decoder(valeur: String): String {
            if ('%' !in valeur && '+' !in valeur) return valeur
            val sortie = StringBuilder(valeur.length)
            var i = 0
            while (i < valeur.length) {
                val c = valeur[i]
                when {
                    c == '+' -> { sortie.append(' '); i++ }
                    c == '%' && i + 2 < valeur.length -> {
                        val octet = valeur.substring(i + 1, i + 3).toIntOrNull(16)
                        if (octet == null) { sortie.append(c); i++ } else { sortie.append(octet.toChar()); i += 3 }
                    }
                    else -> { sortie.append(c); i++ }
                }
            }
            return sortie.toString()
        }
    }
}
