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
 * Comment une unité se nomme devant le lecteur — le seul endroit où le mot se
 * décide.
 *
 * ## Pourquoi ça vit dans le domaine
 *
 * Le calcul tient en une ligne, et c'est précisément ce qui le rend dangereux :
 * une règle courte se recopie. Sur iOS elle l'était — le sommaire disait
 * « Chapitre 2 » quand le sélecteur disait encore « Bereshit 2 », et la pastille
 * de l'écran de lecture ne suivait ni l'un ni l'autre.
 *
 * Android ne l'avait recopiée nulle part : il ne l'avait pas du tout. Le réglage
 * du français reçu **annonçait** « Parashah 7 » dans son texte d'aide, et aucun
 * écran ne le produisait. Une déclaration sans la chose.
 *
 * ## Ce que l'écart dit
 *
 * « Chapitre » est la division de Stephen Langton, XIIIᵉ siècle, que le §2.3 du
 * vault écarte comme « administrative médiévale — souvent arbitraire ». La
 * **parashah** est la division native de l'hébreu, attestée à Qumrân, et elle
 * *ouvre* : le scribe laisse le reste de la ligne blanc.
 *
 * Le réglage ne change donc pas un mot contre un autre, il fait passer d'un
 * découpage à l'autre. C'est le projet lui-même, rendu touchable.
 */
public object LibelleDUnite {

    /** « Chapitre 7 » ou « Parashah 7 ». */
    public fun rang(n: Int, francaisRecu: Boolean): String =
        if (francaisRecu) "Chapitre $n" else "Parashah $n"

    /**
     * Le nom de l'unité, seul — « chapitre » ou « parashah ».
     *
     * En minuscules : c'est un nom commun, et il paraît le plus souvent au
     * milieu d'une phrase. Les rares points d'appel qui ouvrent une ligne avec
     * le capitalisent eux-mêmes.
     */
    public fun nom(francaisRecu: Boolean): String =
        if (francaisRecu) "chapitre" else "parashah"

    /**
     * Le pluriel — « chapitres » ou **« parashiot »**.
     *
     * Le pluriel de *parashah* n'est pas régulier : il ne prend pas le `s`
     * français mais la marque hébraïque `-ot`, et le §2.5 du vault le fixe
     * ainsi. Écrire « parashahs » franciserait un intraduisible, ce qui est
     * exactement ce que le réglage cherche à défaire.
     */
    public fun noms(francaisRecu: Boolean): String =
        if (francaisRecu) "chapitres" else "parashiot"

    /**
     * « Tout le chapitre » / « Toute la parashah » — le nom **et son genre**.
     *
     * Le genre voyage avec le mot, sinon le point d'appel doit l'accorder
     * lui-même — et il l'oubliera le jour où un troisième registre s'ajoutera.
     * Android écrivait « Toute l'unité », un troisième mot qui n'appartient à
     * aucun des deux registres et ne dit rien au lecteur de ce qu'il a choisi.
     */
    public fun toutLe(francaisRecu: Boolean): String =
        if (francaisRecu) "Tout le chapitre" else "Toute la parashah"

    /**
     * « Bereshit · Chapitre 7 » — le livre **et** le rang.
     *
     * Réservé aux écrans où rien d'autre ne dit dans quel livre on est. Sur
     * iOS c'est la pastille de renvoi ; ici c'est le titre de la barre du haut,
     * qui ne portait que le nom du livre — « Bereshit », sans jamais dire
     * laquelle de ses unités on lisait.
     */
    public fun situe(livre: String, rang: Int, francaisRecu: Boolean): String =
        "$livre · ${rang(rang, francaisRecu)}"
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

    /**
     * Le nom de l'unité dans le registre choisi.
     *
     * Une introduction garde son titre : elle n'a pas de rang à traduire, et
     * sans ce cas l'écran annoncerait « Chapitre 0 ».
     */
    public fun label(francaisRecu: Boolean): String =
        if (n > 0) LibelleDUnite.rang(n, francaisRecu) else title
}

/**
 * La fiche d'un **Shem** — un porteur de nom.
 *
 * Elle a la tenue d'une fiche d'intraduisible sans en être une. Le §2.10 veut
 * qu'elle dise le sens de la racine, ce que le nom met sur les épaules de qui le
 * porte, et ce qui reste à venir — d'où les titres de section, que les fiches de
 * concepts n'ont pas.
 */
public data class ShemEntry(
    /** La clé de jointure avec `Inline.Shem.lemma`. */
    public val lemma: String,
    /** La forme d'affichage, avec sa casse et son apostrophe — `Na'amah`. */
    public val title: String,
    public val definition: kotlin.collections.List<Block>,
)

/** La forme allégée d'une unité dans l'arborescence de navigation. */
public data class ChapterStub(
    public val id: String,
    public val n: Int,
    public val title: String,
    public val status: Status,
    public val verseCount: Int,
    public val reference: String?,
) {
    /**
     * Le nom de l'unité dans le registre choisi — voir [Chapter.label].
     *
     * Écrit sur les deux formes plutôt qu'une seule : le sélecteur ne connaît
     * que le stub, l'écran de lecture ne connaît que l'unité pleine, et leur
     * faire converger vers un même type coûterait plus que la ligne recopiée.
     */
    public fun label(francaisRecu: Boolean): String =
        if (n > 0) LibelleDUnite.rang(n, francaisRecu) else title
}

/** Un livre — un des 70 slots de `corpus-order.md`. */
public data class BookOutline(
    public val id: String,
    /** Le numéro global 01–70, continu sur tout le corpus. */
    public val slot: Int,
    /** Le nom hébreu translittéré — le vrai titre du livre (§2.6). */
    public val title: String,
    /** Le nom français, repère pour le lecteur occidental. */
    public val french: String,
    /**
     * Le nom du livre **dans le registre de l'ONT** — « les gevurot de YHWH
     * par ses neviim » pour ce que le français reçu appelle « Actes des
     * Apôtres ».
     *
     * Il manquait au domaine alors que le corpus le porte sur vingt-quatre
     * livres et que le site l'affiche depuis toujours. Le mapping le jetait
     * donc, et l'app rendait le français quel que soit le registre : un lecteur
     * qui l'avait éteint voyait quand même « Actes des Apôtres » là où
     * ontbible.com disait autre chose.
     */
    public val glose: String?,
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
 * Un conteneur de livres — les *Eduyot*, les *Trei Asar*, les deux *Igerot*.
 *
 * **Nommé en français, et pas `Group`** : Compose porte déjà un `Group` —
 * `androidx.compose.ui.graphics.vector.Group` — et une vue qui importerait les
 * deux deviendrait ambiguë. iOS a la même collision avec le `Group` de SwiftUI,
 * et le site l'appelle déjà `Conteneur` : les trois parlent la même langue.
 *
 * Il existait dans les données sous forme d'un identifiant porté par chaque
 * livre, et **aucune interface ne l'affichait**. Les vingt-et-une *Igerot* se
 * lisaient comme une liste plate, alors que leur ordre porte un argument.
 */
public data class Conteneur(
    public val id: String,
    public val title: String,
    public val french: String,
    public val glose: String? = null,
    /**
     * La ligne de sens qui **précède** ce conteneur, quand la coupure est une
     * rupture et non un rangement. Le *Ḥurban* est le seul à en porter une :
     * une césure marquée partout ne marquerait plus rien.
     */
    public val rupture: String? = null,
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
    /**
     * Le pont de navigation — le mot que le lecteur cherche. Les
     * intraduisibles y sont **rendus** : *Torah* devient « la Loi ».
     */
    public val french: String? = null,
    /**
     * Ce que le nom ONT veut dire, quand ça n'est pas déjà le pont. Les
     * intraduisibles y **restent en hébreu** : « la Fondation ».
     */
    public val glose: String? = null,
    public val order: Int,
    /** Dans l'ordre où leurs livres paraissent. Vide pour la plupart. */
    public val groups: kotlin.collections.List<Conteneur> = emptyList(),
    public val books: kotlin.collections.List<BookOutline>,
)

/** Un corpus — la *Kenesset* ou la *Berit Hadashah*. */
public data class Corpus(
    public val id: String,
    public val title: String,
    /** Le pont de navigation — voir [Mode.french]. */
    public val french: String? = null,
    /** Ce que le nom ONT veut dire — voir [Mode.glose]. */
    public val glose: String? = null,
    public val order: Int,
    public val modes: kotlin.collections.List<Mode>,
)
