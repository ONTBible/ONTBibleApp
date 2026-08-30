package com.labibleont.ont.kit.corpus

/**
 * Un nœud du texte ONT.
 *
 * Le CLAUDE.md §2.1 pose trois niveaux, et tout l'enjeu de la liseuse est de ne
 * jamais les aplatir :
 *
 * - **niveau 1** — le corps de la traduction : [Text], et [Term] pour les
 *   intraduisibles qui restent en hébreu translittéré ;
 * - **niveau 2** — [Gloss], la voix du projet, qui explicite ce que le lecteur
 *   hébreu comprenait sans qu'on le lui dise ;
 * - **niveau 3** — [Translit], la paire translittération + hébreu, et [Hebrew]
 *   pour une séquence hébraïque isolée.
 *
 * Les garder distincts, c'est ce qui rend les trois interrupteurs de lecture
 * gratuits : masquer un niveau, c'est ne pas émettre ses nœuds.
 *
 * ## Ce type ne sait pas lire du JSON
 *
 * Il n'a ni annotation de sérialisation ni constructeur depuis un décodeur.
 * Côté Swift, `Inline` a longtemps porté son propre `init(from:)` — le domaine
 * savait donc lire le JSON du pipeline, et un champ renommé dans le vault se
 * propageait jusqu'au cœur de l'app. C'est la dépendance à l'envers.
 *
 * La forme du fichier vit dans `ontdata`, sous le nom `schema.Inline`, engendré
 * depuis `schema.rs` à chaque build ; `SchemaMapping.kt` traduit vers ce
 * type-ci. Le `when` de cette traduction est exhaustif, donc **un type de nœud
 * ajouté au pipeline casse la compilation de l'app** au lieu de disparaître
 * silencieusement du texte.
 */
public sealed interface Inline {

    /** Le corps de la traduction. */
    public data class Text(public val value: String) : Inline

    /** Un intraduisible. [lemma] est la clé qui ouvre sa fiche de lexique. */
    public data class Term(public val value: String, public val lemma: String) : Inline

    /**
     * Un **Shem** — un nom propre, balisé `[[Ainsi]]` dans le vault.
     *
     * Ce n'est pas un intraduisible : `chesed` est en hébreu parce que « bonté »
     * rate quelque chose, `Avraham` est simplement **non traduit**. Les
     * confondre promettrait une fiche de concept là où il y a un porteur.
     *
     * Ce n'est pas un lien non plus. Le pipeline émet un type propre pour que
     * les liseuses n'aient jamais à reconnaître un nom à la forme de son
     * `href` — une règle qui casse au premier `Na'amah` ou `Tuval-Qayin`.
     *
     * [value] s'affiche, [lemma] ouvre la fiche.
     */
    public data class Shem(public val value: String, public val lemma: String) : Inline

    /**
     * `(*chasdo* / חַסְדּוֹ)`.
     *
     * Les deux parts sont séparées parce qu'elles ne se composent pas de la
     * même façon : latine italique d'un côté, fonte hébraïque et direction RTL
     * de l'autre.
     */
    public data class Translit(
        public val translit: String,
        public val hebrew: String,
    ) : Inline

    /** Une séquence en écriture hébraïque rencontrée hors d'un [Translit]. */
    public data class Hebrew(public val value: String) : Inline

    /** Niveau 2 — la voix du projet. */
    public data class Gloss(public val children: kotlin.collections.List<Inline>) : Inline

    /**
     * Une **accentuation** — ni corps ordinaire, ni intraduisible.
     *
     * La troisième catégorie, née d'un défaut : des mots mis en gras pour
     * insister se retrouvaient déclarés intraduisibles, donc affichés en or et
     * touchables, ouvrant une fiche de lexique vide. L'intention était juste,
     * il lui manquait sa marque.
     *
     * Elle porte sa propre couleur et **ne se touche pas** : elle n'a pas de
     * fiche, et un mot qui répond au doigt sans rien avoir à dire est pire
     * qu'un mot qui ne répond pas.
     */
    public data class Accentuation(public val children: kotlin.collections.List<Inline>) : Inline

    public data class Emphasis(public val children: kotlin.collections.List<Inline>) : Inline

    public data class Link(
        public val children: kotlin.collections.List<Inline>,
        public val href: String,
    ) : Inline

    /**
     * Une coupure de ligne signifiante — le bloc de référence d'une feuille
     * d'introduction empile ses champs ainsi.
     */
    public data object LineBreak : Inline
}

/**
 * Le texte nu, pour un titre, un résumé ou une recherche.
 *
 * Par défaut ne rend que le corps de la traduction — c'est la voix du texte,
 * sans l'appareil.
 *
 * ## Pourquoi il faut replier les espaces
 *
 * Un nœud éteint disparaît, mais **pas les espaces de ses voisins**. « Quand
 * Elohim ⟨hébreu⟩ commença » rendait « Quand Elohim⎵⎵commença » dès que le
 * niveau 3 s'éteignait. Invisible en lecture, où la mise en page absorbe le
 * doublon ; visible dès qu'on pose du texte nu dans une liste ou sur une carte
 * de partage.
 *
 * Le repli est celui d'iOS, porté tel quel — [replier].
 */
public fun kotlin.collections.List<Inline>.plainText(
    gloss: Boolean = false,
    level3: Boolean = false,
): String = replier(brut(gloss, level3))

/** Ce qui ne prend jamais d'espace devant, en français. */
private val SANS_ESPACE_DEVANT = setOf('.', ',', ')', ']', '\u2026')

/**
 * Replie les espaces surnuméraires, sans toucher aux retours à la ligne.
 *
 * Un retour à la ligne est une décision de mise en page du traducteur — la
 * seconde ligne d'un parallélisme, l'ouverture d'un discours. Le fondre dans un
 * espace effacerait ce que le texte dit de sa propre forme.
 */
private fun replier(texte: String): String = buildString(texte.length) {
    var espaceEnAttente = false
    for (caractere in texte) {
        when (caractere) {
            ' ', '\t' ->
                // Retenue, pas écrite : c'est ce qui suit qui décide si elle
                // sert d'espace ou si elle se perd contre un retour à la ligne.
                espaceEnAttente = isNotEmpty()

            '\n' -> {
                espaceEnAttente = false
                while (isNotEmpty() && last() == ' ') deleteCharAt(length - 1)
                append(caractere)
            }

            else -> {
                // La règle vaut quelle que soit l'origine de l'espace : une
                // omission en laisse, mais un espace avant un point serait faux
                // même écrit à la main.
                if (espaceEnAttente && last() != '\n' && caractere !in SANS_ESPACE_DEVANT) {
                    append(' ')
                }
                espaceEnAttente = false
                append(caractere)
            }
        }
    }
}

private fun kotlin.collections.List<Inline>.brut(
    gloss: Boolean,
    level3: Boolean,
): String = buildString {
    for (node in this@brut) {
        when (node) {
            is Inline.Text -> append(node.value)
            // Un Shem est du corps de texte : le nom **est** ce que la phrase
            // dit. L'éteindre laisserait la phrase sans sujet — au contraire de
            // l'appareil, qu'on retire sans rien perdre.
            is Inline.Term -> append(node.value)
            is Inline.Shem -> append(node.value)
            is Inline.Hebrew -> if (level3) append(node.value)
            is Inline.Translit ->
                if (level3) append("(${node.translit} / ${node.hebrew})")
            is Inline.Gloss ->
                if (gloss) append(node.children.brut(gloss, level3))
            is Inline.Emphasis -> append(node.children.brut(gloss, level3))
            is Inline.Accentuation -> append(node.children.brut(gloss, level3))
            is Inline.Link -> append(node.children.brut(gloss, level3))
            Inline.LineBreak -> append('\n')
        }
    }
}

/** Tous les intraduisibles de l'arbre, dans l'ordre du texte. */
public val kotlin.collections.List<Inline>.lemmas: kotlin.collections.List<String>
    get() = flatMap { node ->
        when (node) {
            is Inline.Term -> listOf(node.lemma)
            // Les Shemot n'y entrent pas : `lemmas` alimente le lexique des
            // **intraduisibles**, et un nom propre n'en est pas un. Les mêler
            // ferait promettre une fiche de concept là où il y a un porteur.
            is Inline.Shem -> emptyList()
            is Inline.Gloss -> node.children.lemmas
            is Inline.Emphasis -> node.children.lemmas
            is Inline.Accentuation -> node.children.lemmas
            is Inline.Link -> node.children.lemmas
            else -> emptyList()
        }
    }
