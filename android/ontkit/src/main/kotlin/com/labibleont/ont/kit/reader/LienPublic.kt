package com.labibleont.ont.kit.reader

/**
 * L'adresse publique d'un passage, pour le partage.
 *
 * ## Ce que c'était avant
 *
 * Le partage Android ne portait **aucun lien** : le destinataire recevait le
 * texte et la référence, et rien qui mène au passage. iOS en pose un depuis
 * toujours — c'est lui qui produit la carte d'aperçu avec la vignette de la
 * marque qu'on voit dans une conversation.
 *
 * L'écart n'avait pas été relevé parce qu'il ne se voit pas depuis l'app : le
 * texte partagé y semble complet. Il ne manque quelque chose que **chez le
 * destinataire**, qui n'a aucun moyen d'ouvrir ce qu'on lui cite.
 *
 * ## Pourquoi le domaine est écrit ici et pas ailleurs
 *
 * `AndroidManifest.xml` le porte déjà, mais pour un tout autre usage : y
 * déclarer quels liens l'app **reçoit**. Le lire de là pour composer un lien
 * qu'on **émet** mêlerait deux rôles qui n'ont aucune raison de rester
 * identiques — le jour où l'app accepterait `labibleont.com` en plus, elle se
 * mettrait à partager des adresses de redirection.
 *
 * [ontbible.com porte le projet][https://ontbible.com] ; `labibleont.com`
 * redirige et ne s'écrit jamais dans un partage.
 */
public object LienPublic {

    private const val BASE: String = "https://ontbible.com"

    /**
     * L'adresse d'une unité, avec ses versets désignés s'il y en a.
     *
     * Le paramètre `?v=` prend la même écriture que [VerseRange.label] — celle
     * du site, celle des liens profonds, celle du chapeau de page. Une seule
     * écriture de l'ensemble, pour qu'on ne se demande jamais laquelle fait foi.
     *
     * Le tri et la déduplication viennent de [VerseRange] : deux personnes qui
     * désignent le même passage dans un ordre différent produisent le **même**
     * lien, donc le même aperçu et la même entrée de cache.
     */
    public fun passage(livreId: String, uniteId: String, versets: Set<Int> = emptySet()): String {
        val chemin = "$BASE/fr/lire/$livreId/$uniteId"
        if (versets.isEmpty()) return chemin
        val parametre = VerseRange.label(versets).replace(" ", "")
        return "$chemin?v=$parametre"
    }
}
