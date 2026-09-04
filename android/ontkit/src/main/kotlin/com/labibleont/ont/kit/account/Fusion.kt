package com.labibleont.ont.kit.account

import com.labibleont.ont.kit.reader.Highlight
import com.labibleont.ont.kit.reader.ReadingPosition

/**
 * Ce qu'on garde quand deux appareils ont travaillé chacun de leur côté.
 *
 * ## Pourquoi c'est ici et non dans le service
 *
 * La règle d'arbitrage est **la** décision de la synchronisation. Écrite dans
 * le service HTTP, elle se relirait au milieu de la sérialisation et des codes
 * de retour, et ne s'éprouverait qu'en montant un faux serveur. Écrite ici,
 * elle est une fonction de deux listes vers une liste.
 *
 * ## La règle, et pourquoi elle ne peut pas être plus fine
 *
 * **Le plus récent gagne, par identifiant.** Pas de fusion champ par champ :
 * si un appareil change la couleur pendant qu'un autre écrit la note, il n'y a
 * aucun moyen de savoir laquelle des deux intentions est la bonne, et inventer
 * un mélange produirait un surlignage que personne n'a voulu.
 *
 * C'est aussi ce que le serveur applique — `position.updated_at > server.updated_at` —
 * et diverger de lui ferait osciller les deux côtés.
 *
 * ## Les pierres tombales ne sont pas un cas à part
 *
 * Un surlignage supprimé reste une ligne, marquée `deleted`, avec sa date. La
 * même règle la traite donc sans exception : une suppression récente efface une
 * modification ancienne, et une modification récente ressuscite une suppression
 * ancienne — ce qui est correct, puisque le lecteur l'a bien reposée.
 *
 * ## L'égalité va au serveur
 *
 * À date égale, on garde la version distante. Ce n'est pas arbitraire : c'est le
 * seul choix qui fait **converger** les appareils. Si chacun gardait la sienne,
 * deux téléphones à la même milliseconde resteraient différents pour toujours,
 * chacun se croyant à jour.
 */
public object Fusion {

    /**
     * Les marques des deux côtés, réconciliées.
     *
     * L'ordre de sortie suit les identifiants, pour que deux appels sur les
     * mêmes données rendent la même liste — un test qui comparerait des listes
     * dans un ordre de table de hachage passerait un jour sur deux.
     */
    public fun marques(
        locales: kotlin.collections.List<Highlight>,
        distantes: kotlin.collections.List<Highlight>,
    ): kotlin.collections.List<Highlight> {
        val par = LinkedHashMap<String, Highlight>()
        for (marque in locales) par[marque.id] = marque
        for (marque in distantes) {
            val presente = par[marque.id]
            // `>=` et non `>` : à égalité, la distante l'emporte. Voir plus haut.
            par[marque.id] = when {
                presente == null -> marque
                marque.updatedAt >= presente.updatedAt -> marque
                else -> presente
            }
        }
        return par.values.sortedBy { it.id }
    }

    /**
     * La position de lecture, entre deux.
     *
     * `null` d'un côté ne veut pas dire « efface » mais « je n'en ai pas » : un
     * appareil qui vient d'être installé n'a aucune position, et laisser son
     * absence l'emporter effacerait la reprise de l'autre.
     */
    public fun position(
        locale: ReadingPosition?,
        distante: ReadingPosition?,
    ): ReadingPosition? = when {
        locale == null -> distante
        distante == null -> locale
        distante.date >= locale.date -> distante
        else -> locale
    }
}
