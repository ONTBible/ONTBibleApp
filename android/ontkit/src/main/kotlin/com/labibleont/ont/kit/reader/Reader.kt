package com.labibleont.ont.kit.reader

import java.time.Instant

/**
 * Une couleur de surlignage.
 *
 * Le domaine ne connaît que le **nom** de la teinte, jamais sa valeur : la
 * couleur réelle est une décision de présentation, elle vit dans le design
 * system. C'est ce qui permet de retoucher la palette sans migrer les données
 * déjà enregistrées, et de la décliner par thème.
 */
public enum class HighlightColor(public val cle: String, public val label: String) {
    GOLD("gold", "Or"),
    OLIVE("olive", "Olive"),
    SKY("sky", "Ciel"),
    ROSE("rose", "Rose"),
    VIOLET("violet", "Violet");

    public companion object {
        public fun depuis(cle: String?): HighlightColor =
            entries.firstOrNull { it.cle == cle } ?: GOLD
    }
}

/**
 * Un surlignage, posé sur un verset.
 *
 * La granularité est le **verset**, pas la plage de caractères : c'est l'unité
 * que le lecteur retient et cite, et la seule qui résiste à une révision du
 * texte. Un décalage de caractères deviendrait faux dès qu'une glose change ;
 * un numéro de verset, non.
 */
public data class Highlight(
    public val id: String,
    public val bookId: String,
    public val chapterId: String,
    public val verse: Int,
    public val color: HighlightColor,
    public val note: String? = null,
    public val updatedAt: Instant = Instant.now(),
    /**
     * Une **pierre tombale**, et non une absence.
     *
     * Supprimer physiquement un surlignage ne se synchronise pas : l'appareil
     * qui efface n'a plus rien à envoyer, et celui qui reçoit ne voit qu'un
     * objet manquant — indistinguable d'un objet qu'il n'a pas encore. Il le
     * renvoie donc, et le surlignage ressuscite au prochain échange.
     *
     * On garde donc la ligne, marquée. C'est ce que le serveur attend déjà :
     * son `Highlight` porte `deleted` depuis le premier jour.
     */
    public val deleted: Boolean = false,
) {
    /** La clé d'un verset — `bereshit-18#19`. */
    public val key: String get() = key(chapterId, verse)

    public companion object {
        public fun key(chapterId: String, verse: Int): String = "$chapterId#$verse"
    }
}

/** Où le lecteur en était. */
public data class ReadingPosition(
    public val bookId: String,
    public val chapterId: String,
    public val chapterTitle: String,
    public val verse: Int,
    public val date: Instant = Instant.now(),
)

/**
 * Le verset à marquer dans une unité donnée — `null` si ce n'est pas celle
 * qu'on lit.
 *
 * **La position mémorisée est celle du lecteur, pas celle de l'écran ouvert.**
 * Sans ce test, ouvrir *Bereshit* 2 pendant qu'on lit *Bereshit* 18 allumerait
 * le verset 12 au hasard — un repère faux est pire qu'aucun repère, parce qu'on
 * s'y fie.
 *
 * Ici plutôt que dans le sélecteur : c'est une règle sur la position, et une
 * règle dans une vue ne s'éprouve qu'en dessinant la vue.
 */
public fun ReadingPosition?.versetDans(chapterId: String): Int? =
    this?.takeIf { it.chapterId == chapterId }?.verse

/**
 * La fonte du corps.
 *
 * Un choix laissé au lecteur, pas arbitré une fois pour toutes : ce qui est
 * confortable dépend de la vue, de l'âge, de l'habitude, et personne ne lit une
 * Bible de la même manière. L'app en propose sept ; elle en impose une par
 * défaut, ce qui n'est pas la même chose.
 *
 * Toutes sont sous licence OFL et embarquées, sauf [GEORGIA] — livrée par le
 * système sur iOS. **Sur Android elle n'existe pas** : le système fournit Noto
 * Serif. Le domaine nomme un choix, pas un fichier de fonte ; c'est au design
 * system de dire à quoi ce choix correspond sur chaque plateforme, et c'est
 * précisément pourquoi ce nom-ci reste ici tel quel.
 */
public enum class ReadingFont(
    public val cle: String,
    public val label: String,
    /** Ce que la fonte apporte, en une ligne — de quoi choisir sans être typographe. */
    public val note: String,
) {
    LITERATA("literata", "Literata", "Dessinée pour la lecture longue à l'écran"),
    EB_GARAMOND("ebGaramond", "EB Garamond", "La lettre du livre imprimé classique"),
    SPECTRAL("spectral", "Spectral", "Ouverte et franche, tient les petites tailles"),
    SOURCE_SERIF("sourceSerif", "Source Serif", "Neutre, elle s'efface derrière le texte"),
    NEWSREADER("newsreader", "Newsreader", "Étroite, plus de texte par écran"),
    JOST("jost", "Jost", "Géométrique — la fonte de l'édition imprimée"),
    GEORGIA("georgia", "Georgia", "La fonte du système, robuste et familière");

    public companion object {
        public fun depuis(cle: String?): ReadingFont =
            entries.firstOrNull { it.cle == cle } ?: LITERATA
    }
}

/**
 * Quand le lecteur veut recevoir le verset du jour.
 *
 * L'heure est à la minute près parce que la minute est ce qui rend le rappel
 * utilisable : 7 h 00 tombe dans le réveil, 7 h 12 dans le trajet. Une app qui
 * ne propose que des heures rondes force à choisir entre deux mauvais moments.
 */
public data class DailyVerseSchedule(
    public val enabled: Boolean = false,
    public val hour: Int = 7,
    public val minute: Int = 30,
) {
    init {
        require(hour in 0..23) { "heure hors bornes : $hour" }
        require(minute in 0..59) { "minute hors bornes : $minute" }
    }

    public companion object {
        public val DEFAUT: DailyVerseSchedule = DailyVerseSchedule()

        /** Borne plutôt que de refuser — pour ce qui vient d'un fichier relu. */
        public fun borne(enabled: Boolean, hour: Int, minute: Int): DailyVerseSchedule =
            DailyVerseSchedule(enabled, hour.coerceIn(0, 23), minute.coerceIn(0, 59))
    }
}

/**
 * Ce que le lecteur a réglé.
 *
 * Les deux premiers champs ne sont pas des préférences d'affichage : ce sont
 * les **niveaux du texte** (CLAUDE.md §2.1), et pouvoir les éteindre est la
 * raison d'être de la liseuse. Corps seul, on lit d'une traite ; gloses
 * allumées, on lit l'appareil ; hébreu allumé, on travaille.
 */
public data class ReadingPreferences(
    /** Niveau 2 — les gloses. */
    public val showGloss: Boolean = true,
    /** Niveau 3 — translittération et hébreu. */
    public val showLevel3: Boolean = true,
    /**
     * Le corps du texte, en points, avant mise à l'échelle système.
     *
     * Sur Android l'échelle vient de `fontScale`, l'équivalent du Dynamic Type
     * — et elle doit être suivie sans plafond. Un lecteur qui monte le curseur
     * le fait parce qu'il ne voit pas autrement.
     */
    public val textSize: Double = 19.0,
    /** L'interligne, en multiple de la taille du corps. */
    public val lineSpacing: Double = 0.5,
    public val theme: ReadingTheme = ReadingTheme.PARCHMENT,
    public val bodyFont: ReadingFont = ReadingFont.LITERATA,
    /**
     * Les versets à la suite, en prose continue, plutôt qu'un par bloc.
     *
     * Deux façons de lire, pas deux goûts : le bloc par verset sert l'étude —
     * on vise, on annote, on compare. La prose continue sert la lecture suivie,
     * où la découpe en versets est un artefact du XIIIᵉ siècle qui hache une
     * phrase en trois.
     *
     * À la suite par défaut : on ouvre une Bible pour la lire. Qui vient
     * étudier trouvera le mode blocs dans les réglages ; l'inverse demandait de
     * savoir qu'un texte haché en trois n'était pas une fatalité.
     */
    public val continuous: Boolean = true,
    /**
     * Nommer les livres et les sections dans le français reçu.
     *
     * **Vrai par défaut**, et c'est délibéré : un lecteur qui arrive doit
     * pouvoir se repérer avec les mots qu'il connaît — « Apocalypse »,
     * « la Loi », « Chapitre 7 ».
     *
     * À faux, il lit ce que le nom ONT veut dire : « le **machazeh** de
     * Yohanan », « la Fondation », « **Parashah** 7 ». Les intraduisibles y
     * restent en hébreu, là où le français les rend.
     *
     * **L'écart entre les deux est le projet lui-même** : la *torah*,
     * l'instruction qui vise, est devenue *nomos*, le code qui contraint, puis
     * « la Loi ». Le réglage laisse le lecteur passer d'un monde à l'autre au
     * lieu de le lui raconter.
     *
     * La valeur par défaut au constructeur **est** la tolérance de relecture :
     * kotlinx.serialization retombe dessus quand la clé manque. Un réglage
     * enregistré avant l'arrivée de ce champ se relit donc sans erreur — c'est
     * ce que fait le `decodeIfPresent` d'iOS, ici gratuitement.
     */
    public val french: Boolean = true,
    /**
     * Le rappel quotidien.
     *
     * Ici plutôt que dans un second magasin, parce qu'il n'y a qu'un port de
     * préférences et qu'en ouvrir un deuxième pour trois entiers coûterait plus
     * que la petite impureté de ranger un rappel avec des réglages d'affichage.
     */
    public val daily: DailyVerseSchedule = DailyVerseSchedule.DEFAUT,
) {
    /**
     * Les réglages d'affichage remis au départ — le rappel quotidien intact.
     *
     * [daily] traverse, et c'est tout l'intérêt de ne pas écrire
     * `preferences = ReadingPreferences()` dans l'écran. Le rappel n'est pas un
     * réglage d'affichage : il vit sur son propre écran, il a demandé une
     * autorisation système, et le remettre au départ reprogrammerait
     * silencieusement des notifications que personne n'a demandé de toucher.
     *
     * Reconstruit par le constructeur plutôt que champ par champ : un réglage
     * d'affichage ajouté demain revient au départ sans qu'on y pense, alors
     * qu'une liste à recopier s'oublie exactement une fois.
     */
    public fun resettingDisplay(): ReadingPreferences = ReadingPreferences(daily = daily)

    /**
     * Vrai quand aucun réglage d'affichage ne s'écarte du départ.
     *
     * Sert à éteindre le bouton de remise à zéro : proposer d'annuler ce qu'on
     * n'a pas changé fait douter d'avoir changé quelque chose.
     */
    public val isDisplayDefault: Boolean get() = this == resettingDisplay()

    public companion object {
        public val DEFAUT: ReadingPreferences = ReadingPreferences()
    }
}
