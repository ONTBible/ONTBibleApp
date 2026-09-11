package com.labibleont.ont.designsystem.text

import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.BaselineShift
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import com.labibleont.ont.designsystem.tokens.ONTColors
import com.labibleont.ont.designsystem.typography.ONTTypography
import com.labibleont.ont.kit.corpus.CibleDuNiveauTrois
import com.labibleont.ont.kit.corpus.Inline
import com.labibleont.ont.kit.corpus.Verse
import androidx.compose.ui.graphics.Color

/**
 * Le rendu du texte ONT — les trois niveaux en typographie.
 *
 * Transforme un arbre `List<Inline>` en `AnnotatedString`. Toutes les décisions
 * visuelles viennent d'[ONTTypography] : ce fichier ne contient pas une seule
 * taille ni une seule couleur en dur, donc changer de fonte ou ajouter un thème
 * ne demande pas d'y revenir.
 *
 * ## Les intraduisibles se **touchent**
 *
 * Ils portent une [LinkAnnotation.Clickable] : les toucher ouvre leur fiche. On
 * préfère le toucher à l'appui long de Bible Strong parce qu'ici les cibles
 * sont rares et identifiées — pas besoin de distinguer le geste de la sélection
 * de texte.
 *
 * `LinkAnnotation` plutôt qu'une annotation de chaîne : Compose en tire seul le
 * traitement d'accessibilité, donc un lecteur d'écran annonce le terme comme
 * actionnable. Une annotation nue aurait laissé un mot doré muet pour qui ne
 * voit pas l'or.
 */
public object ONTTextRenderer {

    /** L'étiquette portée par le lien d'un intraduisible. */
    public const val TAG_TERME: String = "ont:term"

    /** L'étiquette portée par le lien d'un **Shem** — un nom propre. */
    public const val TAG_SHEM: String = "ont:shem"

    /**
     * Le renvoi d'une chuqqah vers une autre.
     *
     * L'étiquette porte la **cible**, jamais le libellé : `((amar|dire))`
     * affiche « dire » et mène à `amar`.
     */
    public const val TAG_RENVOI: String = "ont:renvoi"

    /**
     * La **référence biblique** — « *Genèse* 9:27 », « *Bereshit* 17 ».
     *
     * L'étiquette ne sert pas qu'à l'accessibilité : c'est par elle que la
     * couche de dessin retrouve les plages à souligner en pointillé, puisque
     * Compose n'a pas de soulignement à motif par fragment. Voir
     * [plagesDeReference].
     */
    public const val TAG_REFERENCE: String = "ont:reference"

    /** L'étiquette portée par le lien d'un verset, en lecture continue. */
    public const val TAG_VERSET: String = "ont:verse"

    /**
     * Compose un fragment de texte ONT.
     *
     * [onTerme] reçoit le lemme touché. Nul quand le fragment ne doit pas être
     * actionnable — un extrait de recherche, un texte partagé.
     */
    public fun compose(
        nodes: kotlin.collections.List<Inline>,
        typo: ONTTypography,
        showGloss: Boolean,
        showLevel3: Boolean,
        onTerme: ((String) -> Unit)? = null,
        onShem: ((String) -> Unit)? = null,
        onRenvoi: ((String) -> Unit)? = null,
        /**
         * Ce qu'on fait d'une référence touchée.
         *
         * Elle reçoit le **nœud entier**, et non sa cible : une référence sans
         * cible doit répondre elle aussi — l'auteur a arbitré que l'apparence
         * ne se scinde pas —, et c'est le nom du livre qu'elle porte qui
         * permet de dire *pourquoi* elle ne mène nulle part. Passer la seule
         * cible aurait rendu ce message impossible à écrire.
         */
        onReference: ((Inline.Reference) -> Unit)? = null,
    ): AnnotatedString = buildAnnotatedString {
        val prepares = nodes.prepared(showGloss = showGloss, showLevel3 = showLevel3)
        ajouter(
            prepares, typo, inGloss = false,
            onTerme = onTerme, onShem = onShem, onRenvoi = onRenvoi, onReference = onReference,
        )
    }

    /**
     * Compose un verset, précédé de son numéro en exposant.
     *
     * Le numéro est **à part** du corps, et c'est ce qui permet de l'épargner
     * quand le verset est désigné : le pointillé se trace sous la ligne, et il
     * ferait un décroché à chaque début de verset s'il rejoignait un exposant.
     */
    public fun composeVerse(
        verse: Verse,
        typo: ONTTypography,
        showGloss: Boolean,
        showLevel3: Boolean,
        onTerme: ((String) -> Unit)? = null,
        onShem: ((String) -> Unit)? = null,
        onRenvoi: ((String) -> Unit)? = null,
        /** Voir [compose] — le nœud entier, pas sa seule cible. */
        onReference: ((Inline.Reference) -> Unit)? = null,
        onVerset: ((Int) -> Unit)? = null,
        /** Le fond du surlignage posé par le lecteur, s'il y en a un. */
        fond: androidx.compose.ui.graphics.Color? = null,
        /**
         * Vrai quand un autre verset est désigné : celui-ci s'efface.
         *
         * Employé en **prose continue**, où il n'y a pas de composable par
         * verset. En mode blocs, l'appelant préfère `Modifier.alpha`, qui fait
         * la même chose plus simplement puisqu'il tient un composable.
         */
        estompe: Boolean = false,
        /**
         * Le fond sur lequel le texte se pose — nécessaire pour estomper.
         *
         * Il n'est pas déduit du thème : la carte bordeaux du Qahal n'a pas le
         * fond de la page, et un estompage calculé sur le mauvais fond se
         * verrait comme un halo.
         */
        fondDuTheme: androidx.compose.ui.graphics.Color =
            ONTColors.background(typo.theme),
    ): AnnotatedString = buildAnnotatedString {
        val corps = buildAnnotatedString {
            append(numeroDeVerset(verse.n, typo))
            append(
                compose(
                    verse.nodes, typo, showGloss, showLevel3,
                    onTerme, onShem, onRenvoi, onReference,
                ),
            )
        }

        // ## L'estompage se calcule, il ne s'applique pas
        //
        // Le procédé vient de Bible Strong : on n'éclaire pas le verset
        // désigné, on efface les autres.
        //
        // `SpanStyle` n'a pas d'opacité — seulement une couleur — et poser une
        // couleur unique par-dessus écraserait les teintes des trois niveaux :
        // l'or des intraduisibles, l'encre douce des gloses, tout deviendrait
        // une seule couleur passée.
        //
        // Mais estomper à l'opacité **est** un mélange au fond : afficher une
        // couleur à 32 % sur un fond revient exactement à afficher le mélange
        // des deux dans cette proportion. On calcule donc le mélange pour
        // chaque fragment, et le résultat est identique au pixel près — les
        // rapports entre les trois niveaux sont conservés, parce qu'ils sont
        // mêlés au même fond dans la même proportion.
        //
        // C'est ce qui permet à la prose continue d'estomper comme le mode
        // blocs, alors qu'elle n'a pas de composable par verset : tous les
        // versets y sont dans un seul texte pour que les lignes se lient.
        val enveloppe = SpanStyle(
            background = fond ?: androidx.compose.ui.graphics.Color.Unspecified,
        )

        val rendu = if (estompe) corps.estompeSur(fondDuTheme) else corps

        if (onVerset == null) {
            withStyle(enveloppe) { append(rendu) }
        } else {
            // Le lien le plus **intérieur** l'emporte : toucher un
            // intraduisible ouvre sa fiche, toucher ailleurs désigne le verset.
            withLink(
                LinkAnnotation.Clickable(
                    tag = "$TAG_VERSET/${verse.n}",
                    styles = TextLinkStyles(
                        style = SpanStyle(textDecoration = TextDecoration.None),
                    ),
                    linkInteractionListener = { onVerset(verse.n) },
                ),
            ) {
                withStyle(enveloppe) { append(rendu) }
            }
        }
    }

    /**
     * Le numéro de verset, en exposant.
     *
     * `BaselineShift` est un multiple de la taille du fragment, là où iOS pose
     * un décalage absolu. On convertit plutôt que de choisir une valeur qui
     * « rendrait bien » : les deux liseuses doivent poser le chiffre à la même
     * hauteur, sinon la comparaison de captures ne veut plus rien dire.
     */
    public fun numeroDeVerset(n: Int, typo: ONTTypography): AnnotatedString =
        buildAnnotatedString {
            val tailleDuChiffre = typo.size * 0.62f
            withStyle(
                typo.verseNumber.copy(
                    baselineShift = BaselineShift(typo.verseBaselineOffset / tailleDuChiffre),
                ),
            ) {
                append("$n ")
            }
        }

    /**
     * Compose le corps seul — ce qu'on partage, ou ce qu'on met en exergue.
     *
     * Les deux niveaux d'appareil sont éteints : un verset partagé doit se lire
     * d'une traite, et les gloses de l'ONT font parfois quarante mots.
     */
    public fun composeBare(
        nodes: kotlin.collections.List<Inline>,
        typo: ONTTypography,
        ink: androidx.compose.ui.graphics.Color? = null,
    ): AnnotatedString {
        val base = compose(nodes, typo, showGloss = false, showLevel3 = false)
        if (ink == null) return base

        // ## Écraser les couleurs, et non les poser dessous
        //
        // Envelopper le texte dans un `SpanStyle(color = ink)` ne suffit pas :
        // les fragments intérieurs portent déjà la leur — l'encre du corps,
        // l'or des intraduisibles — et un fragment intérieur l'emporte sur son
        // enveloppe. Le corps du verset restait donc à l'encre sombre, posée
        // sur un aplat bordeaux, illisible ; seuls les intraduisibles se
        // voyaient, parce que leur or coïncidait avec ce qu'on voulait.
        //
        // Le Swift écrit `output.foregroundColor = ink`, qui **remplace** la
        // couleur de tous les fragments. On fait pareil : on force la couleur
        // de chaque fragment, et on ajoute un fragment de pleine étendue pour
        // le texte qu'aucun ne couvre.
        //
        // Le reste des attributs survit — graisse, italique, fonte hébraïque —
        // parce qu'on ne remplace que la couleur.
        @Suppress("DEPRECATION")
        return AnnotatedString(
            text = base.text,
            spanStyles = listOf(
                AnnotatedString.Range(SpanStyle(color = ink), 0, base.text.length),
            ) + base.spanStyles.map { it.copy(item = it.item.copy(color = ink)) },
            paragraphStyles = base.paragraphStyles,
        )
    }

    // ── La composition ──────────────────────────────────────────────────

    private fun AnnotatedString.Builder.ajouter(
        nodes: kotlin.collections.List<Inline>,
        typo: ONTTypography,
        inGloss: Boolean,
        onTerme: ((String) -> Unit)?,
        onShem: ((String) -> Unit)?,
        onRenvoi: ((String) -> Unit)?,
        onReference: ((Inline.Reference) -> Unit)?,
        /**
         * La teinte d'une accentuation englobante, s'il y en a une.
         *
         * ## Pourquoi elle descend au lieu d'être posée au-dessus
         *
         * `withStyle` empile : le style du parent est **sous** celui des
         * enfants, et un enfant qui fixe sa propre couleur l'écrase. Or
         * `Inline.Text` pose `corpus`, qui fixe l'encre — donc une accentuation
         * peinte au niveau du parent était repeinte en noir par son propre
         * contenu, aussitôt.
         *
         * Le symptôme trompait : l'italique d'une emphase **survivait**, parce
         * que `corpus` ne touche pas au style de fonte. On voyait donc une
         * mise en forme fonctionner et l'autre non, au même endroit, ce qui ne
         * ressemblait pas à un défaut d'empilement.
         *
         * iOS n'a pas ce problème parce qu'il **repeint après coup** : il
         * compose les enfants, puis parcourt les plages obtenues et leur impose
         * la couleur. Compose ne construit pas ainsi ; la teinte doit donc
         * voyager vers le bas.
         */
        accentuation: Color? = null,
    ) {
        for (node in nodes) {
            when (node) {
                is Inline.Text -> {
                    val base = if (inGloss) typo.gloss else typo.corpus
                    withStyle(
                        if (accentuation == null) {
                            base
                        } else {
                            base.copy(color = accentuation, fontWeight = FontWeight.SemiBold)
                        },
                    ) { append(node.value) }
                }

                is Inline.Term -> {
                    // Dans une glose, l'intraduisible garde sa couleur d'or mais
                    // prend la taille de la glose : il appartient au niveau 2 le
                    // temps de cette parenthèse.
                    val style = if (inGloss) {
                        typo.term.copy(fontSize = typo.gloss.fontSize)
                    } else {
                        typo.term
                    }
                    if (onTerme == null) {
                        withStyle(style) { append(node.value) }
                    } else {
                        withLink(
                            LinkAnnotation.Clickable(
                                tag = "$TAG_TERME/${node.lemma}",
                                // **Sans soulignement.** Compose souligne les
                                // liens par défaut, et ce serait une marque de
                                // plus sur un texte qui en porte déjà trois :
                                // l'or dit l'intraduisible, les crochets la
                                // glose, les parenthèses le niveau 3. Un
                                // soulignement en surplus ferait ressembler le
                                // corps de la traduction à une page web.
                                //
                                // C'est aussi ce que fait la liseuse iOS —
                                // l'or seul, et le pointillé réservé à la
                                // désignation d'un verset, qui est un geste du
                                // lecteur et non une propriété du texte.
                                styles = TextLinkStyles(
                                    style = SpanStyle(textDecoration = TextDecoration.None),
                                ),
                                linkInteractionListener = { onTerme(node.lemma) },
                            ),
                        ) {
                            withStyle(style) { append(node.value) }
                        }
                    }
                }

                is Inline.Shem -> {
                    // Même règle que l'intraduisible dans une glose : le Shem
                    // garde sa terre brûlée et prend la taille du niveau 2.
                    val style = if (inGloss) {
                        typo.shem.copy(fontSize = typo.gloss.fontSize)
                    } else {
                        typo.shem
                    }
                    if (onShem == null) {
                        withStyle(style) { append(node.value) }
                    } else {
                        withLink(
                            LinkAnnotation.Clickable(
                                tag = "$TAG_SHEM/${node.lemma}",
                                // Sans soulignement, pour la même raison que
                                // l'intraduisible : la teinte dit déjà la
                                // couche, et un trait de plus ferait ressembler
                                // le corps de la traduction à une page web.
                                styles = TextLinkStyles(
                                    style = SpanStyle(textDecoration = TextDecoration.None),
                                ),
                                linkInteractionListener = { onShem(node.lemma) },
                            ),
                        ) {
                            withStyle(style) { append(node.value) }
                        }
                    }
                }

                is Inline.Renvoi -> {
                    // **Coloré et touchable, comme sur iOS.**
                    //
                    // Il ne l'était pas : la teinte disait « ceci mène
                    // ailleurs » et le doigt n'obtenait rien. Une couleur qui
                    // promet ce qu'on ne tient pas est pire qu'une couleur
                    // absente — le lecteur croit avoir mal visé, et recommence.
                    //
                    // C'était la seule divergence de comportement entre les
                    // deux liseuses. La session iOS l'avait laissée
                    // délibérément plutôt que de faire descendre un rappel dans
                    // six signatures d'un fichier qui n'est pas le sien.
                    val style = if (inGloss) {
                        typo.renvoi.copy(fontSize = typo.gloss.fontSize)
                    } else {
                        typo.renvoi
                    }
                    if (onRenvoi == null) {
                        withStyle(style) { append(node.value) }
                    } else {
                        withLink(
                            LinkAnnotation.Clickable(
                                tag = "$TAG_RENVOI/${node.cible}",
                                // Sans soulignement, comme l'intraduisible et
                                // le Shem : la teinte dit déjà la couche.
                                styles = TextLinkStyles(
                                    style = SpanStyle(textDecoration = TextDecoration.None),
                                ),
                                // **La cible, pas le libellé.** `((amar|dire))`
                                // affiche « dire » et mène à `amar` ; passer ce
                                // qu'on lit mènerait à une chuqqah qui n'existe
                                // pas.
                                linkInteractionListener = { onRenvoi(node.cible) },
                            ),
                        ) {
                            withStyle(style) { append(node.value) }
                        }
                    }
                }

                is Inline.Reference -> {
                    // **L'ambre du renvoi, et le pointillé de la désignation.**
                    //
                    // Arbitré à l'écran par l'auteur, les trois candidats côte
                    // à côte dans le vrai thème et la vraie fonte : « ambre
                    // plus pointillé c'est bien ».
                    //
                    // *L'ambre seule* confondait la référence avec le renvoi de
                    // chuqqah. *Le pointillé seul*, à l'encre du corps, passait
                    // sous les jambages du « B » et du « 4 » et se lisait comme
                    // un défaut de rendu. Les deux marques disent chacune une
                    // moitié : l'ambre, « ceci mène ailleurs dans le corpus » ;
                    // le pointillé, « et c'est une désignation de verset ».
                    //
                    // ## Le pointillé n'est pas posé ici, et il ne peut pas l'être
                    //
                    // iOS écrit `piece.underlineStyle = .init(pattern: .dot)`
                    // et n'a plus rien à faire. Compose n'a que
                    // `TextDecoration.Underline` — plein, sans motif —, et un
                    // trait plein serait **une autre marque** : il pèse autant
                    // qu'un surlignage là où le pointillé désigne sans marquer.
                    //
                    // C'est le même manque que `Soulignement.kt` a déjà résolu
                    // pour la désignation d'un verset : le motif se **dessine**,
                    // à partir de la mise en page du texte, donc après la
                    // composition. L'étiquette du lien porte l'information
                    // jusque-là — voir [plagesDeReference].
                    val style = if (inGloss) {
                        typo.renvoi.copy(fontSize = typo.gloss.fontSize)
                    } else {
                        typo.renvoi
                    }
                    if (onReference == null) {
                        withStyle(style) { append(node.value) }
                    } else {
                        // **Toujours un lien, résolue ou non.** L'apparence ne
                        // se scinde pas — l'auteur l'a arbitré —, et poser la
                        // couleur sans la destination serait la marque d'un
                        // geste qui n'existe pas. Les références qui ne mènent
                        // nulle part répondent par un message qui nomme le
                        // livre : un toucher sans réponse se lit comme une
                        // panne de l'app, pas comme un état de la traduction.
                        withLink(
                            LinkAnnotation.Clickable(
                                // L'étiquette dit **où l'on va**, ou qu'on ne
                                // va nulle part. C'est aussi ce que la couche
                                // de dessin filtre pour tracer le pointillé.
                                tag = "$TAG_REFERENCE/${node.cible?.unite ?: "?"}",
                                // Sans soulignement plein : le pointillé, tracé
                                // par-dessous, est la marque voulue.
                                styles = TextLinkStyles(
                                    style = SpanStyle(textDecoration = TextDecoration.None),
                                ),
                                linkInteractionListener = { onReference(node) },
                            ),
                        ) {
                            withStyle(style) { append(node.value) }
                        }
                    }
                }

                is Inline.Hebrew ->
                    hebreu(node.value, if (inGloss) typo.hebrewSmall else typo.hebrew)

                is Inline.Translit -> {
                    // **La part latine se touche, l'hébreu non.** L'hébreu se
                    // compose en RTL : une zone tactile à cheval sur la barre
                    // oblique traverserait deux directions d'écriture.
                    //
                    // **Ce qui ouvre prend la couleur de sa destination** —
                    // l'or d'un intraduisible, la terre brûlée d'un Shem —, ce
                    // qui n'ouvre pas garde le gris de l'apparat. Sur 2086
                    // translittérations, 829 répondent et 1257 non ; sans la
                    // couleur, le lecteur devrait essayer sur chacune pour
                    // savoir sur laquelle essayer.
                    val cible = node.cible
                    val style = when (cible) {
                        is CibleDuNiveauTrois.Term ->
                            typo.translit.copy(color = typo.term.color)
                        is CibleDuNiveauTrois.Shem ->
                            typo.translit.copy(color = typo.shem.color)
                        null -> typo.translit
                    }
                    val ouvrir: (() -> Unit)? = when (cible) {
                        is CibleDuNiveauTrois.Term -> onTerme?.let { { it(cible.lemma) } }
                        is CibleDuNiveauTrois.Shem -> onShem?.let { { it(cible.lemma) } }
                        null -> null
                    }
                    val etiquette = when (cible) {
                        is CibleDuNiveauTrois.Term -> "$TAG_TERME/${cible.lemma}"
                        is CibleDuNiveauTrois.Shem -> "$TAG_SHEM/${cible.lemma}"
                        null -> null
                    }

                    withStyle(typo.apparatus) { append("(") }
                    if (ouvrir == null || etiquette == null) {
                        withStyle(style) { append(node.translit) }
                    } else {
                        withLink(
                            LinkAnnotation.Clickable(
                                tag = etiquette,
                                // Sans soulignement, comme l'intraduisible et
                                // le Shem : la teinte dit déjà la couche.
                                styles = TextLinkStyles(
                                    style = SpanStyle(textDecoration = TextDecoration.None),
                                ),
                                linkInteractionListener = { ouvrir() },
                            ),
                        ) {
                            withStyle(style) { append(node.translit) }
                        }
                    }
                    withStyle(typo.apparatus) { append(" / ") }
                    hebreu(node.hebrew, typo.hebrewSmall)
                    withStyle(typo.apparatus) { append(")") }
                }

                is Inline.Gloss -> {
                    withStyle(typo.apparatus) { append("[") }
                    ajouter(
                        node.children, typo, inGloss = true,
                        onTerme = onTerme, onShem = onShem, onRenvoi = onRenvoi,
                        onReference = onReference, accentuation = accentuation,
                    )
                    withStyle(typo.apparatus) { append("]") }
                }

                is Inline.Accentuation ->
                    // Aucun lien, délibérément : une accentuation n'a pas de
                    // fiche de lexique, et un mot qui répond au doigt sans rien
                    // avoir à dire est pire qu'un mot qui ne répond pas.
                    //
                    // La couleur et la graisse se posent **par-dessus** les
                    // styles des enfants, sans les écraser : une accentuation
                    // peut contenir de l'hébreu, dont la fonte doit survivre.
                    ajouter(
                        node.children,
                        typo,
                        inGloss,
                        onTerme,
                        onShem,
                        onRenvoi,
                        onReference,
                        accentuation = ONTColors.accentuation(typo.theme),
                    )

                is Inline.Emphasis ->
                    withStyle(SpanStyle(fontStyle = FontStyle.Italic)) {
                        ajouter(node.children, typo, inGloss, onTerme, onShem, onRenvoi, onReference, accentuation)
                    }

                // Le lien du vault ne mène nulle part dans la liseuse : on en
                // garde le texte, pas la cible.
                is Inline.Link ->
                    ajouter(node.children, typo, inGloss, onTerme, onShem, onRenvoi, onReference, accentuation)

                Inline.LineBreak -> append("\n")
            }
        }
    }

    /**
     * Le texte mêlé au fond, dans la proportion de l'estompage.
     *
     * Chaque fragment garde sa graisse, son italique et sa fonte ; seule sa
     * couleur est mêlée. Un fragment de pleine étendue couvre ce qu'aucun autre
     * ne couvre — sans lui, le texte non stylé garderait sa couleur pleine et
     * ressortirait au milieu de ce qui s'efface.
     */
    private fun AnnotatedString.estompeSur(
        fond: androidx.compose.ui.graphics.Color,
    ): AnnotatedString {
        fun melanger(c: androidx.compose.ui.graphics.Color) =
            androidx.compose.ui.graphics.lerp(fond, c, ONTColors.DIMMED_OPACITY)

        @Suppress("DEPRECATION")
        return AnnotatedString(
            text = text,
            spanStyles = spanStyles.map { plage ->
                val couleur = plage.item.color
                if (couleur == androidx.compose.ui.graphics.Color.Unspecified) {
                    plage
                } else {
                    plage.copy(item = plage.item.copy(color = melanger(couleur)))
                }
            },
            paragraphStyles = paragraphStyles,
        )
    }

    /**
     * Une séquence hébraïque, isolée du texte latin qui l'entoure.
     *
     * Les marques d'isolation Unicode — FSI (U+2068) et PDI (U+2069) —
     * empêchent l'algorithme bidirectionnel d'emporter la ponctuation française
     * voisine dans le sens droite-à-gauche. Sans elles, une parenthèse fermante
     * saute de l'autre côté du mot, et le lecteur voit « )חסד » au lieu de
     * « (חסד) ».
     */
    private fun AnnotatedString.Builder.hebreu(valeur: String, style: SpanStyle) {
        withStyle(style) { append("⁨$valeur⁩") }
    }
}
