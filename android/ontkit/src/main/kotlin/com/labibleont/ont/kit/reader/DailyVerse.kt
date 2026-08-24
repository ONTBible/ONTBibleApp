package com.labibleont.ont.kit.reader

import java.time.Instant
import java.time.ZoneId

/**
 * Un verset du vivier quotidien.
 *
 * Plat et sans arbre d'inline, contrairement à `Verse` : ce type est lu par un
 * widget, qui dispose d'une mémoire très serrée et doit se dessiner en quelques
 * dizaines de millisecondes. Y charger l'arbre complet d'un livre le ferait
 * tomber.
 *
 * Il ne porte que le **corps** de la traduction. Un verset du jour se lit d'une
 * traite : les gloses de l'ONT font parfois quarante mots.
 *
 * Les noms d'une lettre viennent du fichier — c'est un format serré, lu par un
 * widget. Les accesseurs longs sont là pour que le reste du code n'ait pas à
 * les subir.
 */
public data class DailyVerse(
    /** Le livre. */
    public val b: String,
    /** L'unité. */
    public val c: String,
    /** Le numéro du verset. */
    public val n: Int,
    /** Le renvoi affichable — « Bereshit 1:1 ». */
    public val r: String,
    /** Le texte. */
    public val t: String,
) {
    public val id: String get() = "$c#$n"
    public val bookId: String get() = b
    public val chapterId: String get() = c
    public val verse: Int get() = n
    public val reference: String get() = r
    public val text: String get() = t
}

/**
 * Le choix du verset du jour.
 *
 * ## Pourquoi c'est un calcul et non un tirage
 *
 * Trois endroits doivent tomber sur le **même** verset le même jour : l'app, le
 * widget — qui vit dans un autre processus — et la notification, préparée
 * parfois des jours à l'avance par le système. Un tirage au sort les ferait
 * diverger ; un serveur les ferait dépendre du réseau et coûterait de la
 * donnée. Une fonction pure de la date les accorde sans qu'ils se parlent.
 *
 * Et rien ne sort de l'appareil : ni requête, ni jeton, ni horaire de lecture.
 * Pour une app dont les annotations révèlent des convictions religieuses, c'est
 * la seule conception défendable.
 *
 * ## Un quatrième endroit : l'autre téléphone
 *
 * Le portage ajoute une contrainte que le Swift n'avait pas à énoncer. Un
 * lecteur qui a un iPhone et une tablette Android doit y lire le **même**
 * verset le même jour, sans quoi « le verset du jour » n'a plus de sens.
 *
 * C'est ce qui interdit d'écrire ici le calcul le plus naturel en Java —
 * `LocalDate.toEpochDay()`. Swift prend minuit **local**, le convertit en
 * secondes depuis 1970 et divise par 86 400 en tronquant : à l'est de
 * Greenwich, minuit local précède minuit UTC, et la troncature retire un jour.
 * `toEpochDay()` ne le retire pas. Les deux liseuses tomberaient sur deux
 * versets différents à Paris, et sur le même à Londres — le genre de défaut
 * qu'on ne reproduit pas au bureau.
 *
 * On réplique donc la troncature, telle quelle.
 */
public object DailySelection {

    /**
     * L'indice du verset du jour, dans un vivier de [count] éléments.
     *
     * ## Une permutation, pas un tirage
     *
     * La première version brassait le numéro du jour et prenait le reste.
     * C'était un tirage : sur 251 versets, deux jours d'un même mois tombaient
     * sur le même avec quatre chances sur cinq — le paradoxe des anniversaires.
     * Un « verset du jour » qui revient le 12 du mois n'en est pas un.
     *
     * On avance donc d'un **pas fixe premier avec la taille du vivier**. Un tel
     * pas engendre le groupe entier : il visite les 251 versets un par un avant
     * d'en revoir un seul. Le pas vaut environ 0,618 × la taille — le nombre
     * d'or, qui écarte au maximum deux positions consécutives. Deux jours
     * voisins restent donc éloignés dans le corpus, sans qu'on lise jamais deux
     * fois la même chose avant d'avoir tout lu.
     */
    public fun index(
        instant: Instant,
        count: Int,
        zone: ZoneId = ZoneId.systemDefault(),
    ): Int {
        if (count <= 1) return 0

        val minuit = instant.atZone(zone).toLocalDate().atStartOfDay(zone).toEpochSecond()
        // Division entière qui tronque vers zéro, comme `Int(Double)` en Swift.
        val numero = (minuit / 86_400L).toInt()
        // Le reste suit le signe du dividende dans les deux langages : une date
        // d'avant 1970 donnerait un indice négatif.
        val position = ((numero % count) + count) % count

        return (position.toLong() * step(count) % count).toInt()
    }

    /** Le pas d'avancement — premier avec [count], donc générateur du cycle. */
    internal fun step(count: Int): Int {
        if (count <= 2) return 1
        var pas = maxOf(1, (count * 0.618_033_988_749_895).toInt())
        while (pgcd(pas, count) != 1) pas += 1
        return pas
    }

    private fun pgcd(a: Int, b: Int): Int {
        var x = a
        var y = b
        while (y != 0) {
            val t = y
            y = x % y
            x = t
        }
        return x
    }

    /** Le verset du jour dans un vivier donné. */
    public fun verse(
        instant: Instant,
        pool: kotlin.collections.List<DailyVerse>,
        zone: ZoneId = ZoneId.systemDefault(),
    ): DailyVerse? {
        if (pool.isEmpty()) return null
        return pool[index(instant, pool.size, zone)]
    }
}
