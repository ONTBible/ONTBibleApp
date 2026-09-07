package com.labibleont.ont.kit.account

/**
 * Par qui le lecteur se connecte.
 *
 * **Pas d'Apple ici**, et ce n'est pas un oubli. Sur iOS, « Continuer avec
 * Apple » passe par l'interface native du système — Face ID, aucun navigateur,
 * aucune redirection — et la revue de l'App Store l'exige dès qu'un autre
 * fournisseur est proposé. Sur Android il faudrait le faire par le web, ce qui
 * en ferait un troisième bouton offrant moins que les deux autres.
 *
 * La valeur de [cle] est celle que le backend attend dans `/auth/{provider}`.
 * Elle n'est **pas** dérivée du nom de la constante : le jour où l'un des deux
 * bougerait, le compilateur ne dirait rien et la connexion répondrait
 * « fournisseur inconnu ».
 */
public enum class Fournisseur(public val cle: String, public val libelle: String) {
    GOOGLE("google", "Google"),
    GITHUB("github", "GitHub"),
}

/**
 * Une session ouverte.
 *
 * ## Les noms viennent du fil, pas de Kotlin
 *
 * Le backend écrit en `snake_case` littéral, sans aucun `rename` — le
 * `CLAUDE.md` de la racine en fait un contrat. C'est la couche de données qui
 * porte les `@SerialName` ; ce type-ci est celui du domaine, et il nomme les
 * choses comme on en parle.
 *
 * ## `expiration` plutôt que la durée reçue
 *
 * Le backend rend `expires_in`, une durée en secondes. La garder telle quelle
 * obligerait chaque appelant à savoir *depuis quand* elle court — et l'un d'eux
 * l'oublierait. On la résout une fois, à la réception.
 */
public data class Session(
    public val jetonDAcces: String,
    public val jetonDeRafraichissement: String,
    /** L'instant où le jeton d'accès cesse de valoir, en millisecondes epoch. */
    public val expiration: Long,
    /** Vrai quand cette connexion vient de créer le compte. */
    public val creation: Boolean,
) {
    /**
     * Le jeton est-il encore bon dans [marge] millisecondes ?
     *
     * La marge n'est pas une précaution de confort : une requête part avec un
     * jeton valide et arrive après son expiration si l'on vise l'instant pile.
     * Le défaut serait rare, non reproductible, et se présenterait comme une
     * déconnexion inexplicable.
     */
    public fun valide(maintenant: Long, marge: Long = 60_000): Boolean =
        maintenant + marge < expiration
}

/** Ce qui peut mal se passer, du point de vue du lecteur. */
public sealed interface EchecDeConnexion {
    /** Le lecteur a fermé la page — ce n'est pas une erreur. */
    public data object Annulee : EchecDeConnexion

    /** Le fournisseur a refusé, ou n'a pas répondu ce qu'on attendait. */
    public data object Refusee : EchecDeConnexion

    /** Le réseau, ou le backend, n'a pas répondu. */
    public data object Injoignable : EchecDeConnexion
}
