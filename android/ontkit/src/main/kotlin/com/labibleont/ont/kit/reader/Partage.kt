package com.labibleont.ont.kit.reader

/**
 * Ce qu'un passage devient quand il quitte l'app.
 *
 * ## Pourquoi ça ne peut pas vivre dans une vue
 *
 * La forme d'un partage est une **décision** — l'ordre du renvoi et du nom, la
 * place du lien, la présence ou non de guillemets — et non un détail de
 * présentation. Écrite au point d'appel, elle s'écrit autant de fois qu'il y a
 * d'écrans qui partagent, et elle diverge sans que rien ne le dise : aucun test
 * ne compare deux chaînes construites à deux endroits.
 *
 * Elle avait déjà divergé. Deux écrans partagent ici, et au 30 août 2026 :
 *
 *     lecture         « corps »  ⏎⏎  renvoi — La Bible ONT  ⏎  lien
 *     verset du jour  « corps »  ⏎⏎  renvoi — La Bible ONT
 *
 * **Le lien manquait au verset du jour** — celui qu'on partage le plus, et le
 * seul que le destinataire ne pouvait pas ouvrir. L'oubli ne se voyait pas : le
 * texte a l'air complet tant qu'on le relit depuis l'app.
 *
 * ## Les guillemets, et pourquoi ils sont partis
 *
 * Android enveloppait le corps dans une paire de chevrons ; iOS non. Ce n'était
 * pas une question de goût : **le corpus ouvre des citations que le verset ne
 * ferme pas.** Bereshit 6:13 porte un chevron ouvrant et aucun fermant — le
 * discours d'Elohim continue au verset suivant, et le français veut qu'on
 * rouvre à chaque unité sans fermer avant la fin.
 *
 * L'enveloppe donnait donc :
 *
 *     « Elohim dit à Noach : « La fin de toute chair… avec la Terre. »
 *
 * Deux ouvertures, une fermeture, et un lecteur qui ne sait plus qui parle. Le
 * chevron final **ferme un propos que le traducteur avait laissé courir**.
 *
 * On s'aligne sur iOS, qui l'évitait sans l'avoir écrit. Le renvoi ouvre par un
 * tiret : il dit « ce qui précède est cité » sans avoir à l'encadrer.
 *
 * ## Ce qu'on ne touche pas au corps
 *
 * **Les retours à la ligne restent.** `replier`, dans `Inline.kt`, les préserve
 * délibérément : « un retour à la ligne est une décision de mise en page du
 * traducteur — la seconde ligne d'un parallélisme, l'ouverture d'un discours ».
 * Les fondre en espaces effacerait ce que le texte dit de sa propre forme, et
 * une première version d'ici le faisait.
 *
 * Les espaces surnuméraires, eux, sont déjà repliés en amont — par `plainText`
 * côté lecture, par la préparation du rendu côté carte. Il ne reste ici qu'à
 * rogner les bords.
 */
public object Partage {

    /** Le nom sous lequel le projet se présente à qui reçoit le partage. */
    private const val SIGNATURE: String = "La Bible ONT"

    /**
     * Le texte partagé.
     *
     * @param corps le passage, déjà mis à plat et déjà replié
     * @param renvoi « Bereshit 1:1-3, 7 »
     * @param lien l'adresse publique, quand elle existe. `null` la retire —
     *   et une chaîne vide vaut `null`, sans quoi un point d'appel qui rend
     *   `""` laisserait une ligne blanche en fin de message.
     */
    public fun texte(corps: String, renvoi: String, lien: String? = null): String =
        buildString {
            append(corps.trim()).append("\n\n")
            append("— ").append(renvoi).append(", ").append(SIGNATURE)
            if (!lien.isNullOrBlank()) append("\n").append(lien)
        }
}
