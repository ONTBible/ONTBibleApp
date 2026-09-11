package com.labibleont.ont.kit.ports

/**
 * Le port de remontée d'erreurs.
 *
 * Une interface, pour que ni le domaine ni les écrans ne dépendent de Sentry —
 * seul le point d'assemblage le connaît. C'est la même règle que pour le corpus
 * et le stockage : les modules déclarent ce dont ils ont besoin, pas comment
 * c'est fait.
 *
 * **Ce qu'on ne remonte jamais.** Les annotations d'un lecteur de Bible
 * révèlent des convictions religieuses — catégorie particulière au sens de
 * l'article 9 du RGPD. Le texte d'une note, le contenu d'un verset et la liste
 * des passages surlignés ne doivent jamais quitter l'appareil par ce canal. Les
 * implémentations expurgent ; les appelants n'ont pas à y penser, mais ne
 * doivent pas non plus glisser ces valeurs dans un message.
 */
public interface Reporter {
    /** Remonte une erreur, avec le contexte de l'endroit où elle s'est produite. */
    public fun report(error: Throwable, context: String)

    /**
     * Dépose une miette de contexte, rattachée au prochain événement.
     *
     * Bon marché — pas de pile d'appels, pas d'envoi immédiat. À préférer pour
     * tracer un enchaînement.
     */
    public fun breadcrumb(message: String)
}

/**
 * Le rapporteur par défaut : il ne fait rien.
 *
 * Sert aux tests, aux aperçus, et à toute construction où l'observabilité n'a
 * pas de sens. Un module qui n'a pas reçu de rapporteur ne doit jamais planter
 * pour autant.
 */
public object SilentReporter : Reporter {
    override fun report(error: Throwable, context: String) {}
    override fun breadcrumb(message: String) {}
}

/**
 * Une erreur dépouillée de son message, pour ce qui a touché des données du
 * lecteur.
 *
 * ## Le défaut qu'elle ferme
 *
 * Le message d'une erreur de décodage **porte le fichier**. Mesuré :
 *
 *     Unexpected JSON token at offset 61: Trailing comma …
 *     JSON input: {"highlights":[{"note":"ce passage m'a bouleversé hier soir"},]}
 *
 * La note du lecteur, mot pour mot, dans ce que la remontée d'erreurs envoie.
 * C'est de la donnée de catégorie particulière au sens de l'article 9 — et elle
 * sortait par le canal même qu'on avait écrit pour la protéger.
 *
 * ## Ce qu'on garde, et pourquoi
 *
 * Le **type** de l'erreur et sa **pile d'appels** : ils disent où et quoi, sans
 * rien dire du contenu. Une pile d'appels ne porte que des noms de fonctions et
 * des numéros de ligne, qui sont à nous.
 *
 * Le message, lui, est écrit par la bibliothèque qui a échoué, et rien ne
 * garantit ce qu'il contient. On ne l'expurge pas — on ne l'emporte pas.
 * Choisir ce qu'on garde est plus sûr que deviner ce qu'on retire.
 */
public class ErreurSansContenu(
    origine: Throwable,
) : Exception("${origine::class.simpleName ?: "erreur"} — message retiré") {
    init {
        stackTrace = origine.stackTrace
    }
}
