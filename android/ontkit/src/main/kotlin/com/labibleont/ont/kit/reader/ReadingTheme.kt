package com.labibleont.ont.kit.reader

/**
 * La peau de la lecture.
 *
 * Quatre thèmes, dont `MYSTIQUE` — la nuit aubergine du site. Il porte ce nom
 * dans les trois dépôts : le site l'avait sans le nommer, lui donner un nom l'a
 * fait passer d'un habillage à quelque chose qu'on peut porter ailleurs.
 *
 * Les valeurs `name` restent celles du Swift (`parchment`, `light`, `dark`,
 * `mystique`) : c'est ce qui est déjà écrit dans les réglages enregistrés, et
 * la synchronisation de compte fait voyager ce champ d'un appareil à l'autre.
 * Un lecteur qui a un iPhone et une tablette Android doit retrouver son thème.
 */
public enum class ReadingTheme(public val cle: String, public val label: String) {
    PARCHMENT("parchment", "Parchemin"),
    LIGHT("light", "Clair"),
    DARK("dark", "Sombre"),
    MYSTIQUE("mystique", "Mystique");

    /**
     * Vrai quand la page est sombre et l'encre claire.
     *
     * Existe pour qu'on cesse d'écrire `theme == DARK`. La comparaison était
     * juste tant qu'il n'y avait qu'un seul thème sombre ; à l'arrivée du
     * second, chaque occurrence est devenue un défaut muet — l'or assombri sur
     * une nuit, un jeu de couleurs clair sous un fond noir. Le compilateur ne
     * dit rien d'une égalité qui reste valide.
     */
    public val isDark: Boolean
        get() = when (this) {
            PARCHMENT, LIGHT -> false
            DARK, MYSTIQUE -> true
        }

    public companion object {
        /** Retrouve un thème depuis la valeur enregistrée. */
        public fun depuis(cle: String?): ReadingTheme =
            entries.firstOrNull { it.cle == cle } ?: PARCHMENT
    }
}

/**
 * Les cinq couleurs de surlignage.
 *
 * Le domaine ne connaît que le **nom**. La teinte vit dans le design system,
 * ce qui permet de retoucher la palette sans migrer les surlignages déjà
 * enregistrés chez les lecteurs.
 */
public enum class HighlightColor(public val cle: String) {
    GOLD("gold"),
    OLIVE("olive"),
    SKY("sky"),
    ROSE("rose"),
    VIOLET("violet");

    public companion object {
        public fun depuis(cle: String?): HighlightColor =
            entries.firstOrNull { it.cle == cle } ?: GOLD
    }
}
