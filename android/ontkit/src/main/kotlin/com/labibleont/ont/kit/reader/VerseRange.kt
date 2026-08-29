package com.labibleont.ont.kit.reader

/**
 * Le renvoi d'une sélection de versets — « 1-3, 7 ».
 *
 * Dans le domaine et non dans la fonctionnalité de lecture, parce que la forme
 * est lue **et** écrite : l'écran la produit pour l'afficher et la partager, le
 * routeur la relit dans un lien reçu. Deux implémentations d'un même format
 * finiraient par diverger, et le jour où elles divergent un lien partagé
 * n'ouvre plus le bon passage.
 *
 * Vit hors de la vue, et c'est le résultat d'un plantage côté iOS : la première
 * version calculait l'intervalle dans le corps de la barre d'actions, avec un
 * accès au premier élément d'un tableau supposé non vide. Quand le lecteur
 * désélectionnait son dernier verset, la barre sortante était réévaluée avec
 * une sélection déjà vide — index hors limites, app fermée.
 *
 * La leçon n'est pas « ajouter un garde » mais « sortir le calcul de la vue » :
 * ici il s'éprouve en trois lignes, y compris le cas vide.
 */
public object VerseRange {

    /**
     * « 1-3, 7 » plutôt que « 1, 2, 3, 7 ».
     *
     * Rend une chaîne vide pour une sélection vide — un renvoi qui ne renvoie
     * à rien.
     */
    public fun label(verses: Set<Int>): String {
        val numbers = verses.sorted()
        val first = numbers.firstOrNull() ?: return ""

        val groups = mutableListOf<String>()
        var start = first
        var previous = first

        for (n in numbers.drop(1)) {
            if (n == previous + 1) {
                previous = n
                continue
            }
            groups.add(borne(start, previous))
            start = n
            previous = n
        }
        groups.add(borne(start, previous))
        return groups.joinToString(", ")
    }

    /** Le renvoi complet, titre du chapitre compris — « Bereshit 1:1-3, 7 ». */
    public fun reference(verses: Set<Int>, chapterTitle: String): String {
        val intervals = label(verses)
        return if (intervals.isEmpty()) chapterTitle else "$chapterTitle:$intervals"
    }

    private fun borne(start: Int, end: Int): String =
        if (start == end) "$start" else "$start-$end"

    /**
     * L'opération inverse : « 1-3, 7 » redevient {1, 2, 3, 7}.
     *
     * Tolérante par construction. Un renvoi arrive d'une URL, donc de
     * l'extérieur : « 3-1 » se lit à l'endroit, un morceau illisible est ignoré
     * plutôt que de faire échouer tout le lien, et un intervalle absurde est
     * borné. Le pire cas rend un ensemble vide, jamais une erreur — un lien à
     * moitié compris vaut mieux qu'un lien mort.
     */
    public fun parse(raw: String): Set<Int> {
        // Une borne haute : `?v=1-99999999` ne doit pas allouer des millions
        // d'entiers parce que quelqu'un a bricolé l'adresse.
        val plafond = 400

        val verses = mutableSetOf<Int>()
        for (morceau in raw.split(",")) {
            val bornes = morceau.split("-").mapNotNull { it.trim().toIntOrNull() }
            when (bornes.size) {
                1 -> verses.add(bornes[0])
                2 -> {
                    val bas = minOf(bornes[0], bornes[1])
                    val haut = maxOf(bornes[0], bornes[1])
                    if (haut - bas >= plafond) continue
                    verses.addAll(bas..haut)
                }
                else -> continue
            }
        }
        return verses.filter { it > 0 }.toSet()
    }
}
