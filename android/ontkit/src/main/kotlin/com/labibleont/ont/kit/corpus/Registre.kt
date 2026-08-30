package com.labibleont.ont.kit.corpus

/**
 * Le second nom d'une chose, selon le registre que le lecteur a choisi.
 *
 * ## Pourquoi cette règle vit dans le domaine
 *
 * Elle tient en trois lignes, et c'est précisément ce qui la rend dangereuse :
 * une règle courte se recopie. Sur iOS elle l'était — en privé dans un écran,
 * et **absente** d'un autre, si bien que le sélecteur de référence n'appliquait
 * le registre nulle part. Android portait la même duplication.
 *
 * Une règle de trois lignes recopiée dans les vues est une règle qu'un écran
 * finit par ne pas appliquer.
 */
public object Registre {

    /**
     * Ce qui s'écrit **sous** le nom principal, ou rien.
     *
     * Français reçu allumé, on montre le français ; éteint, on montre la glose
     * de l'ONT et, à défaut, le français — un livre sans glose n'a pas à
     * disparaître parce qu'on a changé de registre.
     *
     * Rend `null` quand la ligne se redoublerait. *Ketouvim* est « Écrits » des
     * deux côtés : répéter le même mot sous lui-même n'apprend rien et occupe
     * une ligne. **Ce n'est pas un défaut** — le site fait pareil.
     */
    public fun second(french: String?, glose: String?, francaisRecu: Boolean): String? {
        val choisi = if (francaisRecu) french else (glose ?: french)
        return choisi?.takeIf { it.isNotEmpty() }
    }

    /**
     * Ce sur quoi une recherche de livre doit porter — les deux registres.
     *
     * Un lecteur en glose doit retrouver le livre en tapant « actes », et un
     * lecteur en français reçu en tapant « gevurot ». Chercher dans le seul
     * registre affiché rendrait introuvable ce que l'autre nomme.
     */
    public fun cherchable(book: BookOutline): String =
        listOfNotNull(book.title, book.french, book.glose).joinToString(" ")
}
