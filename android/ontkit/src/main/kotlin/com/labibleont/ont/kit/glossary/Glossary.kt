package com.labibleont.ont.kit.glossary

import com.labibleont.ont.kit.corpus.Block

/**
 * Une entrée du lexique : un intraduisible, toutes formes confondues.
 *
 * C'est l'équivalent ONT d'un numéro Strong, à ceci près qu'il n'a pas fallu
 * l'inventer — le glossaire du `CLAUDE.md` §2.5 et §3 *est* le lexique, et le
 * pipeline le dérive à chaque build.
 */
public data class GlossaryEntry(
    /** La clé de jointure avec `Inline.Term`. */
    public val lemma: String,
    /** La forme d'affichage — `chesed`, `El Elyon`, `She'ol`. */
    public val title: String,
    /**
     * Vrai si le terme est balisé dans le texte, donc touchable à la lecture.
     *
     * Faux pour le reste du vocabulaire fixé (§3) — *bara* → « orchestrer » —
     * traduit dans le corps, donc invisible au toucher mais consultable ici.
     */
    public val tagged: Boolean,
    public val forms: kotlin.collections.List<String>,
    public val hebrew: String?,
    /** La traduction ONT arrêtée, quand le terme en a une. */
    public val rendering: String?,
    /**
     * Le champ sémantique complet — ce que le terme signifie, et ce qu'il n'est
     * pas.
     */
    public val definition: kotlin.collections.List<Block>?,
    /** La note de balisage (§2.5) — règles de rendu, formes dérivées. */
    public val taggingNote: kotlin.collections.List<Block>?,
    /** Le premier emploi déclaré — `Bereshit 15:6`. */
    public val firstUse: String?,
    public val sourceSection: String?,
    public val count: Int,
    /** Occurrences dans le corps de la traduction (niveau 1). */
    public val bodyCount: Int,
    /** Occurrences dans les gloses (niveau 2). */
    public val glossCount: Int,
)

/**
 * Le niveau où une forme paraît (§2.1).
 *
 * La distinction n'est pas cosmétique : « où ce mot est dans le texte » et « où
 * on l'explique » ne se cherchent pas de la même façon.
 */
public enum class OccurrenceLevel(public val cle: String) {
    BODY("body"),
    GLOSS("gloss");

    public companion object {
        public fun depuis(cle: String?): OccurrenceLevel =
            entries.firstOrNull { it.cle == cle } ?: BODY
    }
}

/** Une occurrence d'un intraduisible. */
public data class Occurrence(
    public val bookId: String,
    public val chapterId: String,
    public val verse: Int?,
    public val form: String,
    public val level: OccurrenceLevel,
    public val snippet: String,
)
