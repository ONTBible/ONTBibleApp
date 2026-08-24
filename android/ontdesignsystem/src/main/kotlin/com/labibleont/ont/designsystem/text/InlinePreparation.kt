package com.labibleont.ont.designsystem.text

import com.labibleont.ont.kit.corpus.Inline

/**
 * Retire les niveaux éteints, puis resserre les blancs qu'ils laissent.
 *
 * Sans ce nettoyage, éteindre les gloses laisse « se laissa voir    par lui ».
 * Les données restent fidèles à la source ; c'est l'affichage qui recolle.
 */
public fun kotlin.collections.List<Inline>.prepared(
    showGloss: Boolean,
    showLevel3: Boolean,
): kotlin.collections.List<Inline> {
    val kept = mutableListOf<Inline>()

    for (node in this) {
        when (node) {
            is Inline.Gloss -> {
                if (!showGloss) continue
                kept.add(Inline.Gloss(node.children.prepared(showGloss, showLevel3)))
            }
            is Inline.Translit -> if (showLevel3) kept.add(node)
            is Inline.Hebrew -> if (showLevel3) kept.add(node)
            is Inline.Emphasis ->
                kept.add(Inline.Emphasis(node.children.prepared(showGloss, showLevel3)))
            is Inline.Accentuation ->
                // Une accentuation survit à l'extinction des niveaux : elle
                // appartient au corps, pas à l'appareil critique. Mais ses
                // enfants sont nettoyés — elle peut contenir une glose.
                kept.add(Inline.Accentuation(node.children.prepared(showGloss, showLevel3)))
            is Inline.Link ->
                kept.add(Inline.Link(node.children.prepared(showGloss, showLevel3), node.href))
            else -> kept.add(node)
        }
    }

    return kept.mergingText().tighteningWhitespace()
}

/** Fusionne les nœuds de texte devenus voisins après un retrait. */
internal fun kotlin.collections.List<Inline>.mergingText(): kotlin.collections.List<Inline> {
    val sortie = mutableListOf<Inline>()
    for (node in this) {
        val dernier = sortie.lastOrNull()
        if (node is Inline.Text && dernier is Inline.Text) {
            sortie[sortie.size - 1] = Inline.Text(dernier.value + node.value)
        } else {
            sortie.add(node)
        }
    }
    return sortie
}

private val BLANCS = Regex(" {2,}")

/**
 * Resserre les espaces, en respectant la typographie française.
 *
 * On rabat les blancs multiples et l'espace devant `, . …` — mais **pas** celui
 * qui précède `: ; ! ?` ni le guillemet fermant, que le français exige et que le
 * texte source porte déjà correctement.
 */
internal fun kotlin.collections.List<Inline>.tighteningWhitespace(): kotlin.collections.List<Inline> {
    val sortie = map { node ->
        if (node !is Inline.Text) {
            node
        } else {
            var resserre = BLANCS.replace(node.value, " ")
            resserre = PONCTUATION_COLLEE.replace(resserre) { it.groupValues[1] }
            Inline.Text(resserre)
        }
    }.toMutableList()

    val premier = sortie.firstOrNull()
    if (premier is Inline.Text) {
        val elague = premier.value.trimStart(' ')
        if (elague.isEmpty()) sortie.removeAt(0) else sortie[0] = Inline.Text(elague)
    }
    return sortie
}

private val PONCTUATION_COLLEE = Regex(" +([,.…])")
