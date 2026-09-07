package com.labibleont.ont.compte

import android.content.Context
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import com.labibleont.ont.kit.account.Fournisseur
import com.labibleont.ont.kit.account.Pkce

/**
 * Ouvrir la page du fournisseur, et rien de plus.
 *
 * ## Un onglet du système, jamais une WebView
 *
 * Le lecteur tape son mot de passe chez Google ou GitHub. Deux raisons de ne
 * pas l'accueillir chez nous :
 *
 * - **il doit voir la barre d'adresse.** C'est le seul moyen qu'il a de savoir
 *   à qui il donne ses identifiants ; une page qui ressemble à Google dans une
 *   WebView n'est pas distinguable d'une page qui l'imite ;
 * - **ses identifiants ne doivent pas pouvoir traverser notre code.** Une
 *   WebView nous laisserait techniquement les lire. Ne pas pouvoir est plus
 *   solide que ne pas vouloir.
 *
 * C'est le raisonnement d'`ASWebAuthenticationSession` sur iOS, et Apple refuse
 * les `WKWebView` maison pour exactement cette raison.
 *
 * L'onglet personnalisé apporte en plus la session du navigateur : un lecteur
 * déjà connecté à Google dans Chrome n'a rien à retaper.
 */
public class FluxDeConnexion(
    private val racineApi: String,
    private val clientGoogle: String,
    private val clientGitHub: String,
) {
    /**
     * L'adresse de retour déclarée chez le fournisseur.
     *
     * **Une URL HTTPS du backend**, et non `ont://` : Google et GitHub refusent
     * un schéma personnalisé comme adresse de retour. Le backend en expose une,
     * qui rebondit aussitôt vers l'app — il ne fait que faire suivre le code,
     * sans l'échanger.
     */
    public fun adresseDeRetour(fournisseur: Fournisseur): String =
        "$racineApi/auth/${fournisseur.cle}/callback"

    /**
     * L'URL d'autorisation, telle que le fournisseur l'attend.
     *
     * Séparée de l'ouverture pour rester lisible : c'est une chaîne de six
     * paramètres dont un seul manquant fait rendre une page d'erreur au lieu
     * d'une page de connexion.
     */
    public fun adresseDAutorisation(fournisseur: Fournisseur, defi: String): String {
        val base = when (fournisseur) {
            Fournisseur.GOOGLE -> "https://accounts.google.com/o/oauth2/v2/auth"
            Fournisseur.GITHUB -> "https://github.com/login/oauth/authorize"
        }
        val client = when (fournisseur) {
            Fournisseur.GOOGLE -> clientGoogle
            Fournisseur.GITHUB -> clientGitHub
        }
        val portee = when (fournisseur) {
            Fournisseur.GOOGLE -> "openid email"
            Fournisseur.GITHUB -> "read:user user:email"
        }
        return Uri.parse(base).buildUpon()
            .appendQueryParameter("client_id", client)
            .appendQueryParameter("redirect_uri", adresseDeRetour(fournisseur))
            .appendQueryParameter("response_type", "code")
            .appendQueryParameter("scope", portee)
            .appendQueryParameter("code_challenge", defi)
            .appendQueryParameter("code_challenge_method", "S256")
            .build()
            .toString()
    }

    /**
     * Tire un PKCE. **Rien d'autre.**
     *
     * Séparé de l'ouverture, et ce n'est pas une coquetterie : le vérificateur
     * doit être rangé **avant** que le lecteur ne parte au navigateur. Une
     * fonction qui ouvrirait puis rendrait le secret laisserait un intervalle,
     * si court soit-il, où le processus peut mourir avec lui — et l'échange
     * échouerait au retour sans rien dire de la cause.
     *
     * Une première version faisait exactement ça, en documentant le contraire.
     */
    public fun preparer(): Pkce = Pkce.tirer()

    /** Ouvre l'onglet du système sur la page du fournisseur. */
    public fun ouvrir(contexte: Context, fournisseur: Fournisseur, defi: String) {
        CustomTabsIntent.Builder()
            .setShowTitle(true)
            .build()
            .launchUrl(contexte, Uri.parse(adresseDAutorisation(fournisseur, defi)))
    }
}
