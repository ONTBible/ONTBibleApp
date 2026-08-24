package com.labibleont.ont.kit.corpus

/** L'état d'une unité dans le flux de validation (CLAUDE.md §12). */
public enum class Status(public val cle: String) {
    /** Fait référence. Seules ces unités voyagent dans la distribution. */
    LOCKED("locked"),

    /** Rédigée, en attente de la relecture de l'auteur. */
    BROUILLON("brouillon");

    public companion object {
        public fun depuis(cle: String?): Status =
            entries.firstOrNull { it.cle == cle } ?: LOCKED
    }
}

/**
 * Le sous-titre de référence — `*(Genèse / בְּרֵאשִׁית 18:1-33)*`.
 *
 * Le nom français n'est qu'un pont de navigation pour le lecteur occidental
 * (§2.6) ; le renvoi biblique est la seule trace de la numérotation d'origine.
 */
public data class Subtitle(
    public val french: String,
    public val hebrew: String,
    public val reference: String?,
)

/** Le pied d'une unité — version, verrouillage, décisions terminologiques. */
public data class Footer(
    public val version: String?,
    public val locked: Boolean,
    public val notes: kotlin.collections.List<Block>,
)

/** Ce qu'une unité est : un chapitre fonctionnel ou une feuille d'introduction. */
public enum class ChapterKind(public val cle: String) {
    CHAPTER("chapter"),
    INTRO("intro");

    public companion object {
        public fun depuis(cle: String?): ChapterKind =
            entries.firstOrNull { it.cle == cle } ?: CHAPTER
    }
}

/**
 * Une unité ONT : un chapitre fonctionnel, ou la feuille d'introduction d'un
 * livre (§2.7).
 *
 * « Unité » et non « chapitre biblique » : un bloc se clôt quand une fonction
 * cosmique est accomplie, pas quand un numéro de Langton change (§2.3).
 */
public data class Chapter(
    public val id: String,
    public val bookId: String,
    public val kind: ChapterKind,
    public val n: Int,
    public val title: String,
    public val titleNodes: kotlin.collections.List<Inline> = emptyList(),
    public val subtitle: Subtitle? = null,
    public val status: Status = Status.LOCKED,
    public val blocks: kotlin.collections.List<Block> = emptyList(),
    public val footer: Footer? = null,
    public val verseCount: Int = 0,
    public val lemmas: kotlin.collections.List<String> = emptyList(),
) {
    /** Tous les versets de l'unité, à plat. */
    public val verses: kotlin.collections.List<Verse>
        get() = blocks.filterIsInstance<Block.Verses>().flatMap { it.verses }
}

/** La forme allégée d'une unité dans l'arborescence de navigation. */
public data class ChapterStub(
    public val id: String,
    public val n: Int,
    public val title: String,
    public val status: Status,
    public val verseCount: Int,
    public val reference: String?,
)

/** Un livre — un des 70 slots de `corpus-order.md`. */
public data class BookOutline(
    public val id: String,
    /** Le numéro global 01–70, continu sur tout le corpus. */
    public val slot: Int,
    /** Le nom hébreu translittéré — le vrai titre du livre (§2.6). */
    public val title: String,
    /** Le nom français, repère pour le lecteur occidental. */
    public val french: String,
    public val hebrew: String?,
    public val groupId: String?,
    /** Vrai tant qu'aucun texte n'a été rédigé pour ce slot. */
    public val empty: Boolean,
    public val intro: ChapterStub?,
    public val chapters: kotlin.collections.List<ChapterStub>,
) {
    public val verseCount: Int
        get() = chapters.sumOf { it.verseCount }
}

/** Le contenu complet d'un livre. */
public data class Book(
    public val id: String,
    public val slot: Int,
    public val title: String,
    public val french: String,
    public val hebrew: String?,
    public val corpusId: String,
    public val modeId: String,
    public val groupId: String?,
    public val chapters: kotlin.collections.List<Chapter>,
    public val intro: Chapter?,
    public val empty: Boolean,
)

/**
 * Un mode fonctionnel — Torah, Nevi'im, Ketouvim, Nistarot (§1).
 *
 * Ce ne sont pas des divisions canoniques mais des modes distincts d'engagement
 * avec le réel : institution, lecture dans l'histoire, habitation intérieure,
 * traversée architecturale.
 */
public data class Mode(
    public val id: String,
    public val title: String,
    public val order: Int,
    public val books: kotlin.collections.List<BookOutline>,
)

/** Un corpus — la *Kenesset* ou la *Berit Hadashah*. */
public data class Corpus(
    public val id: String,
    public val title: String,
    public val order: Int,
    public val modes: kotlin.collections.List<Mode>,
)
