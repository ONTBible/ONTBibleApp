package com.labibleont.ont.kit.ports

import com.labibleont.ont.kit.account.Fournisseur
import com.labibleont.ont.kit.account.Session

/**
 * Le port du compte.
 *
 * Le domaine et les écrans ne connaissent que cette interface : ni OAuth, ni
 * Custom Tabs, ni stockage chiffré ne remontent jusqu'à eux. C'est la même
 * règle que pour le corpus et le rapporteur — un module déclare ce dont il a
 * besoin, jamais comment c'est fait.
 */
public interface AccountRepository {

    /** La session en cours, ou `null` si personne n'est connecté. */
    public fun session(): Session?

    /**
     * Ouvre une session avec le code rendu par le fournisseur.
     *
     * Le vérificateur PKCE accompagne le code : le backend le fait suivre au
     * fournisseur, qui refuse l'échange s'il ne correspond pas au défi envoyé
     * plus tôt.
     */
    public suspend fun ouvrir(
        fournisseur: Fournisseur,
        code: String,
        adresseDeRetour: String,
        verificateur: String,
    ): Session

    /**
     * Rend une session neuve à partir du jeton long.
     *
     * Rend `null` quand le jeton long lui-même n'est plus bon : le lecteur doit
     * alors se reconnecter, et c'est le seul cas où on le lui demande.
     */
    public suspend fun rafraichir(): Session?

    /** Ferme la session et oublie les jetons. */
    public fun fermer()
}
