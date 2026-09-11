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
/**
 * Ce qu'une translittération de niveau 3 ouvre.
 *
 * **Deux destinations, et elles ne se confondent pas** : une entrée de
 * glossaire vit dans `glossary.json`, une fiche de Shem dans `shemot.json`, et
 * ce sont deux rappels distincts côté liseuse.
 *
 * Un type plutôt qu'un lemme et une sorte : il n'y a rien à tenir ensemble, le
 * lemme ne s'écrit pas sans dire où il mène. Et le `when` qu'il impose est
 * exhaustif — une troisième destination casserait la compilation au lieu de
 * s'oublier.
 */
public sealed interface CibleDuNiveauTrois {
    public data class Term(public val lemma: String) : CibleDuNiveauTrois

    public data class Shem(public val lemma: String) : CibleDuNiveauTrois
}

/**
 * Où une **référence biblique** mène, quand le corpus porte le passage visé.
 *
 * ## Résolue par le pipeline, jamais par la liseuse
 *
 * Les unités ONT ne coïncident pas avec les chapitres reçus : seule la table
 * des plages de tout le corpus sait que « Genèse 7:11 » tombe dans `bereshit-7`.
 * Cette table n'existe qu'au pipeline, et la reconstruire ici reviendrait à
 * l'écrire trois fois — iOS, Android, le site — à partir d'une chaîne
 * d'affichage qui n'a jamais été un format de données.
 *
 * **Nul est le cas ordinaire, et il est honnête** : 208 des 915 références du
 * corpus visent des livres que personne n'a traduits.
 */
public data class CibleDeLaReference(
    /** Le livre qui porte l'unité — `bereshit`. */
    public val livre: String,
    /** L'unité à ouvrir — `bereshit-7`. */
    public val unite: String,
    /**
     * Le verset à rejoindre en arrivant, **dans la numérotation de l'unité**.
     *
     * Nul quand la référence vise un chapitre entier, et nul aussi quand le
     * compte des versets ne confirme pas le calcul : mieux vaut ouvrir la bonne
     * unité sans rien viser que d'en viser un faux.
     */
    public val verset: Int? = null,
)

/**
 * Ce qu'une référence vise à l'intérieur du chapitre qu'elle nomme.
 *
 * **Un type somme, et pas deux nullables.** « premier verset nul, dernier
 * verset 33 » serait une plage sans début — personne ne l'écrira, et c'est
 * justement pour ça que ça finirait par arriver. Ici l'état illégal est
 * irreprésentable, et le `when` des liseuses devient exhaustif.
 *
 * Il fait aussi disparaître une convention tacite : `Genèse 3` et `Genèse 3:1`
 * ne se distinguaient que par la nullité d'un champ.
 */
public sealed interface PorteeDeLaReference {

    /** `Genèse 3` — l'unité entière, pas un verset. */
    public data object Chapitre : PorteeDeLaReference

    /** `Genèse 3:24` — un verset. */
    public data class Verset(public val n: Int) : PorteeDeLaReference

    /** `Genèse 1:11-12` — une plage. La navigation vise son ouverture. */
    public data class Plage(
        public val premier: Int,
        public val dernier: Int,
    ) : PorteeDeLaReference
}

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
     * Un renvoi d'une **chuqqah** vers une autre.
     *
     * Un Shem désigne un **porteur** — quelqu'un. Un renvoi désigne un
     * **énoncé**. Les confondre ferait croire au lecteur qu'il touche un nom
     * propre, et l'amènerait sur un texte qui n'en est pas un.
     *
     * Le pipeline lit `((cible|libellé))` et non `[[…]]`, parce que ce dernier
     * devient un Shem **sans regarder la cible** : le vault porte des renvois
     * vers des porteurs pas encore écrits, et distinguer sur la cible ferait
     * sortir en Shem tout renvoi vers une chuqqah non encore écrite.
     *
     * `cible` peut ne désigner aucune chuqqah existante : le corpus s'écrit, et
     * un renvoi mort dit « ce n'est pas encore écrit », jamais « introuvable ».
     */
    public data class Renvoi(public val value: String, public val cible: String) : Inline

    /**
     * Une **référence biblique** — « *Genèse* 9:27 », « *Bereshit* 17 ».
     *
     * ## Ce qui la sépare du [Renvoi]
     *
     * Un [Renvoi] mène d'une chuqqah à une autre : il désigne un **énoncé**, et
     * sa cible est un identifiant que le vault écrit à la main. Une référence
     * désigne un **passage** du corpus, et son libellé est une notation que des
     * siècles de lecture ont fixée. Les confondre ferait promettre une chuqqah
     * là où il y a un chapitre.
     *
     * ## Le nom du livre dit la numérotation
     *
     * Deux systèmes coexistent et c'est [livre] qui les sépare : « Genèse 9:25 »
     * est le verset 25 du chapitre 9 de la Genèse reçue, « *Bereshit* 9:8 » est
     * le verset ⁸ de l'unité ONT n° 9. Ce sont le même verset, et la forme
     * double est permise. Une notation qui repose sur le contexte se lit juste
     * tant qu'on connaît le contexte ; un nom se lit seul.
     *
     * @param value ce qui s'affiche, tel que le texte l'écrit.
     * @param livre le nom **affiché** — « Genèse », « Bereshit ». Ce n'est pas
     *   un identifiant : celui-là vit dans [cible].
     * @param systeme `"recu"` ou `"ont"`.
     * @param cible où l'on va, **quand on peut y aller**. Voir
     *   [CibleDeLaReference] : nul est le cas ordinaire.
     */
    public data class Reference(
        public val value: String,
        public val livre: String,
        public val systeme: String,
        public val chapitre: Int,
        public val portee: PorteeDeLaReference,
        public val cible: CibleDeLaReference? = null,
    ) : Inline

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
        /**
         * La fiche que la translittération ouvre, **quand elle en ouvre une**.
         *
         * Le lecteur est sur le mot hébreu : c'est le moment où il veut sa
         * fiche, et l'appareil s'arrêtait au corps du texte.
         *
         * **`null` est le cas ordinaire**, et il est honnête. Le pipeline ne
         * résout que l'exact — un lemme, une forme déclarée au §2.5, un Shem
         * publié — et laisse inerte tout ce qui demanderait de deviner : une
         * règle morphologique qui se trompe ne rend pas le mot inerte, elle le
         * rend touchable **vers la mauvaise fiche**.
         */
        public val cible: CibleDuNiveauTrois? = null,
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
            // Un renvoi aussi : la phrase le nomme, et un partage ne doit pas
            // laisser un trou là où le lecteur a lu un mot.
            is Inline.Renvoi -> append(node.value)
            // Une référence aussi : « comme en *Genèse* 4:25 » perd son sens si
            // le syntagme disparaît d'un extrait, d'une recherche ou d'un
            // partage.
            is Inline.Reference -> append(node.value)
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
