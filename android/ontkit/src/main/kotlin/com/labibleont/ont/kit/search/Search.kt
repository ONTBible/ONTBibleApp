package com.labibleont.ont.kit.search

import com.labibleont.ont.kit.glossary.OccurrenceLevel
import java.text.Normalizer

/** Ce qu'une entrée d'index représente. */
public enum class SearchKind(public val cle: String) {
    VERSE("verse"),
    HEADING("heading"),
    PROSE("prose");

    public companion object {
        public fun depuis(cle: String?): SearchKind =
            entries.firstOrNull { it.cle == cle } ?: VERSE
    }
}

/**
 * Une entrée de l'index de recherche, telle que le pipeline l'émet.
 *
 * Les noms d'une lettre viennent du fichier — c'est un format serré, chargé en
 * entier au lancement. Les accesseurs longs évitent que le reste du code les
 * subisse.
 */
public data class SearchRecord(
    public val b: String,
    public val c: String,
    public val v: Int,
    public val k: SearchKind,
    /** Le corps de la traduction, plié. */
    public val t: String,
    /** Les gloses seules, pliées. */
    public val g: String,
    /** L'hébreu dénudé de son niqqud et de ses te'amim. */
    public val h: String,
    /** Les lemmes d'intraduisibles présents. */
    public val l: kotlin.collections.List<String>,
    /** Le corps tel qu'il s'affiche, pour l'extrait. */
    public val x: String,
) {
    public val bookId: String get() = b
    public val chapterId: String get() = c
    public val verse: Int? get() = if (v == 0) null else v
}

/**
 * Où chercher — les niveaux du texte, en question de recherche.
 *
 * « Où le texte dit-il **chesed** » et « où l'explique-t-on » sont deux
 * questions distinctes (§2.1), et l'une ne doit pas noyer l'autre.
 */
public enum class SearchScope(public val label: String) {
    BODY("Dans le texte"),
    GLOSS("Dans les gloses"),
    ALL("Partout"),
}

public data class SearchHit(
    public val record: SearchRecord,
    /** Là où la correspondance a été trouvée. */
    public val level: OccurrenceLevel,
    public val score: Int,
    /** L'extrait à afficher. */
    public val snippet: String,
) {
    public val id: String get() = "${record.c}-${record.v}-${level.cle}"
}

/**
 * Le moteur de recherche.
 *
 * Volontairement sans index inversé : à l'échelle du corpus — quelques dizaines
 * de milliers d'entrées une fois les 70 slots rédigés — un balayage de
 * sous-chaînes sur des chaînes déjà pliées prend quelques millisecondes. Un
 * index inversé ajouterait de la complexité sans gain mesurable, et interdirait
 * la recherche par sous-chaîne au milieu d'un mot, qui est précisément ce qu'on
 * veut pour l'hébreu et les formes construites.
 */
public object SearchEngine {

    private val MARQUES = Regex("\\p{M}")
    private val ESPACES = Regex("\\s+")
    private val PONCTUATION_HEBRAIQUE = setOf('־', '׀', '׃', '׆', '׳', '״')

    /**
     * Plie une chaîne latine pour la comparaison.
     *
     * ## Elle est copiée du pipeline, pas du Swift
     *
     * `search.rs::fold` est la source : c'est lui qui a plié l'index, et une
     * requête qui plierait autrement ne le rencontrerait jamais. On reprend
     * donc **son** enchaînement, dans **son** ordre — décomposer, retirer les
     * marques, mettre en minuscules, normaliser l'apostrophe, réduire les
     * espaces :
     *
     *     décomposition NFD  →  \p{M} retirées  →  minuscules
     *       →  ’ et ʼ deviennent '  →  \s+ deviennent un espace  →  élagage
     *
     * L'ordre compte. Mettre en minuscules avant de décomposer donnerait le
     * même résultat sur du français et un résultat différent sur le grec final
     * sigma ou le turc sans point — le genre d'écart qui ne se voit jamais
     * pendant les essais.
     */
    public fun fold(input: String): String {
        val decompose = Normalizer.normalize(input, Normalizer.Form.NFD)
        val sansMarques = MARQUES.replace(decompose, "")
        val minuscules = sansMarques.lowercase()
        val normalisees = minuscules.map { c ->
            when (c) {
                '’', 'ʼ' -> '\''
                else -> c
            }
        }.joinToString("")
        return ESPACES.replace(normalisees, " ").trim()
    }

    /**
     * Dénude l'hébreu : consonnes seules, sans niqqud ni te'amim.
     *
     * C'est ce qui permet à une saisie au clavier hébreu ordinaire — sans
     * voyelles, comme on écrit l'hébreu tous les jours — de rencontrer un texte
     * biblique intégralement vocalisé. Sans ça, taper חסד ne trouverait jamais
     * חֶסֶד.
     */
    public fun stripHebrew(input: String): String {
        val sansMarques = MARQUES.replace(input, "")
        val sansPonctuation = sansMarques.filter { it !in PONCTUATION_HEBRAIQUE }
        return ESPACES.replace(sansPonctuation, " ").trim()
    }

    public fun isHebrew(input: String): Boolean =
        input.any { it.code in 0x0590..0x05FF }

    /**
     * Cherche dans l'index.
     *
     * [lemmas] — les lemmes du glossaire, pour que taper « chesed » trouve
     * aussi les passages où le terme ne paraît qu'en hébreu.
     */
    public fun search(
        query: String,
        records: kotlin.collections.List<SearchRecord>,
        scope: SearchScope,
        lemmas: Set<String> = emptySet(),
        limit: Int = 300,
    ): kotlin.collections.List<SearchHit> {
        val raw = query.trim()
        if (raw.length < 2) return emptyList()

        // Une requête en écriture hébraïque se compare à la forme dénudée.
        val hebrewNeedle = if (isHebrew(raw)) stripHebrew(raw) else null
        val needle = fold(raw)
        val lemmaNeedle = if (lemmas.contains(needle)) needle else null

        val hits = mutableListOf<SearchHit>()

        for (record in records) {
            if (hebrewNeedle != null) {
                if (!record.h.contains(hebrewNeedle)) continue
                hits.add(hit(record, OccurrenceLevel.BODY, 500))
                continue
            }

            var matched = false

            if (scope != SearchScope.GLOSS) {
                val found = record.t.indexOf(needle)
                if (found >= 0) {
                    // Un mot entier vaut mieux qu'un fragment, et un début de
                    // verset mieux qu'un milieu.
                    var score = 300
                    if (record.t.startsWith(needle)) score += 60
                    if (isWordBoundary(record.t, found, found + needle.length)) score += 40
                    if (record.k == SearchKind.HEADING) score += 30
                    hits.add(hit(record, OccurrenceLevel.BODY, score))
                    matched = true
                }
            }

            if (scope != SearchScope.BODY && record.g.contains(needle)) {
                hits.add(hit(record, OccurrenceLevel.GLOSS, 150))
                matched = true
            }

            // Le lemme rattrape les passages où le terme n'est qu'en hébreu.
            if (!matched && lemmaNeedle != null && record.l.contains(lemmaNeedle)) {
                hits.add(hit(record, OccurrenceLevel.BODY, 100))
            }
        }

        return hits
            .sortedWith(compareByDescending<SearchHit> { it.score }.thenBy { it.record.c })
            .take(limit)
    }

    private fun hit(record: SearchRecord, level: OccurrenceLevel, score: Int): SearchHit =
        SearchHit(record = record, level = level, score = score, snippet = record.x)

    /** Vrai si la correspondance commence et finit sur une frontière de mot. */
    private fun isWordBoundary(text: String, debut: Int, fin: Int): Boolean {
        val avant = debut == 0 || !text[debut - 1].isLetter()
        val apres = fin >= text.length || !text[fin].isLetter()
        return avant && apres
    }
}
