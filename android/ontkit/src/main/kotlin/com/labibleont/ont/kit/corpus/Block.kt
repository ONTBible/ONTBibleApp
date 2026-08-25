package com.labibleont.ont.kit.corpus

/**
 * Un verset ONT.
 *
 * [n] est la numérotation **interne** à l'unité (CLAUDE.md §2.2) : elle repart
 * de 1 à chaque unité fonctionnelle et ne correspond pas au numéro biblique.
 * Le renvoi biblique vit dans le sous-titre du chapitre.
 */
public data class Verse(
    public val n: Int,
    public val nodes: kotlin.collections.List<Inline>,
)

/** Un bloc de mise en page. */
public sealed interface Block {

    public data class Heading(
        public val level: Int,
        public val nodes: kotlin.collections.List<Inline>,
    ) : Block

    public data class Verses(public val verses: kotlin.collections.List<Verse>) : Block

    public data class Paragraph(public val nodes: kotlin.collections.List<Inline>) : Block

    public data class List(
        public val ordered: Boolean,
        public val items: kotlin.collections.List<kotlin.collections.List<Inline>>,
    ) : Block

    public data class Quote(public val nodes: kotlin.collections.List<Inline>) : Block

    public data class Table(
        public val headers: kotlin.collections.List<kotlin.collections.List<Inline>>,
        public val rows: kotlin.collections.List<
            kotlin.collections.List<kotlin.collections.List<Inline>>,
            >,
    ) : Block

    public data object Rule : Block
}

/**
 * Les blocs de versets consécutifs, réunis en un seul.
 *
 * ## Pourquoi le mode « versets à la suite » ne faisait rien
 *
 * La prose continue se fabrique dans la vue, en composant **un bloc** en un
 * seul texte. Elle ne peut donc lier que ce que le bloc contient déjà — et le
 * corpus, lui, découpe surtout au verset : 504 blocs d'un seul verset contre
 * 109 qui en groupent deux à six. Là où le corpus groupait, le mode marchait ;
 * partout ailleurs — Bereshit 11 en entier — il rendait exactement la même
 * chose que le mode blocs.
 *
 * Rien ne le signalait : le réglage s'enregistrait, la branche s'exécutait, le
 * rendu ne changeait pas d'un pixel.
 *
 * Réunir ici plutôt que dans la vue, parce que c'est une question de **texte**
 * et non d'affichage : le découpage du corpus sert le mode d'étude, où chaque
 * verset se tient seul. La lecture suivie demande l'autre découpage, et rien
 * n'oblige à ce que le premier soit le seul que le domaine sache produire.
 *
 * Les titres coupent, et c'est voulu : « Les toledot de Shem » ouvre une
 * section, la prose ne doit pas l'enjamber. Tout ce qui n'est pas un verset
 * traverse sans changement.
 *
 * On accumule dans un tampon plutôt que de reconstruire le dernier bloc à
 * chaque tour : recopier tout ce qui précède à chaque verset ajouté serait
 * quadratique, et refait à chaque recomposition — c'est-à-dire à chaque appui.
 */
public fun kotlin.collections.List<Block>.fusingConsecutiveVerses(): kotlin.collections.List<Block> {
    val resultat = ArrayList<Block>(size)
    val tampon = ArrayList<Verse>()

    fun vider() {
        if (tampon.isEmpty()) return
        resultat.add(Block.Verses(tampon.toList()))
        tampon.clear()
    }

    for (bloc in this) {
        if (bloc is Block.Verses) {
            tampon.addAll(bloc.verses)
        } else {
            vider()
            resultat.add(bloc)
        }
    }
    vider()
    return resultat
}

/**
 * Le verset en tête de ce qui est affiché, à partir du bloc visible en premier.
 *
 * ## Pourquoi cette règle vit ici
 *
 * Elle sert à **retenir où l'on en est**, et c'était le trou : Android
 * n'enregistrait la position qu'au moment où le lecteur *tapait* un verset pour
 * le sélectionner. Lire un chapitre d'un bout à l'autre sans rien toucher ne
 * retenait rien — la carte « Reprendre » ne pouvait donc quasiment jamais
 * paraître. iOS retient au défilement, à l'ouverture et au balayage ; le
 * portage avait gardé le commentaire qui dit « ce fichier est touché à chaque
 * défilement » sans jamais câbler le défilement.
 *
 * On repart du premier bloc visible et on descend jusqu'au premier qui porte
 * des versets : un intertitre ou une note en haut de l'écran ne doit pas effacer
 * la position, il doit laisser parler ce qui suit.
 *
 * Rend `null` quand plus rien ne porte de verset — la fin d'un chapitre qui
 * s'achève sur une note. L'appelant garde alors la dernière position connue,
 * plutôt que d'en inventer une.
 */
public fun kotlin.collections.List<Block>.versetEnTete(premierBlocVisible: Int): Int? =
    drop(premierBlocVisible.coerceAtLeast(0))
        .firstNotNullOfOrNull { bloc ->
            (bloc as? Block.Verses)?.verses?.firstOrNull()?.n
        }
