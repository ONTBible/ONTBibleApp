package com.labibleont.ont.designsystem.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.labibleont.ont.designsystem.metrics.ONTRadius
import com.labibleont.ont.designsystem.typography.ONTFonts

/**
 * Le mobilier — et lui seul.
 *
 * ## Pourquoi un second système de texte
 *
 * Il y en a déjà un : `ONTTypography`. Il ne fait pas ce travail-ci, et les
 * confondre serait une faute.
 *
 * `ONTTypography` fabrique des `SpanStyle` pour **le texte biblique**, dont
 * tous les niveaux cohabitent dans une même ligne — un verset porte du corpus,
 * un intraduisible, une glose et de l'hébreu sans changer de paragraphe. Sa
 * granularité est la plage de caractères.
 *
 * Ce fichier-ci porte des `TextStyle` pour **le mobilier** : intitulés
 * d'onglets, en-têtes de section, libellés de réglages. Sa granularité est le
 * composable, et c'est ce que Material sait consommer.
 *
 * Les deux ne se recouvrent pas : la surface de lecture n'a aucune taille en
 * dur, tandis que le mobilier en comptait 93 le jour où ce fichier a été
 * écrit — dont deux grands titres à 34 sp et deux autres à 32 sp, la même
 * intention à deux valeurs. C'est ce trou-là qu'on comble.
 *
 * ## Ce qu'on ne fixe pas, délibérément
 *
 * Les rôles de corps et d'étiquette **ne portent pas de famille**. Ils gardent
 * donc celle du système, qui est ce que le mobilier affiche déjà aujourd'hui :
 * seuls les titres demandent Jost, explicitement, écran par écran. Poser
 * Literata sur `bodyLarge` repeindrait d'un coup les 93 `Text` qui n'imposent
 * rien — un changement qu'on ne verrait qu'à l'usage, et qu'aucun test ne
 * signalerait.
 *
 * Brancher n'est pas redessiner. Ce fichier ouvre la porte ; ce qui passe
 * dedans se décide écran par écran, en regardant.
 */
internal val ONTChromeTypography: Typography = Typography().let { defaut ->
    val titre = TextStyle(fontFamily = ONTFonts.display, fontWeight = FontWeight.SemiBold)
    defaut.copy(
        // Le grand titre d'écran — « Qahal », « Lexique ». Une seule valeur,
        // là où le code en portait deux.
        headlineLarge = titre.copy(fontSize = 34.sp, lineHeight = 40.sp),
        headlineMedium = titre.copy(fontSize = 28.sp, lineHeight = 34.sp),
        headlineSmall = titre.copy(fontSize = 22.sp, lineHeight = 28.sp),

        // Les titres de section et d'entrée de liste.
        titleLarge = titre.copy(fontSize = 22.sp, lineHeight = 28.sp),
        titleMedium = titre.copy(fontSize = 17.sp, lineHeight = 24.sp),
        titleSmall = titre.copy(fontSize = 15.sp, lineHeight = 20.sp),

        // Le corps du mobilier — sans famille imposée, cf. ci-dessus.
        bodyLarge = defaut.bodyLarge.copy(fontSize = 16.sp, lineHeight = 24.sp),
        bodyMedium = defaut.bodyMedium.copy(fontSize = 15.sp, lineHeight = 21.sp),
        bodySmall = defaut.bodySmall.copy(fontSize = 13.sp, lineHeight = 18.sp),

        // Les étiquettes. 13 sp est, de loin, la taille la plus employée du
        // mobilier — 23 occurrences ; elle mérite d'être le milieu de gamme
        // plutôt qu'une valeur qu'on retape.
        labelLarge = defaut.labelLarge.copy(fontSize = 14.sp, lineHeight = 20.sp),
        labelMedium = defaut.labelMedium.copy(fontSize = 13.sp, lineHeight = 17.sp),
        labelSmall = defaut.labelSmall.copy(fontSize = 11.sp, lineHeight = 15.sp),
    )
}

/**
 * Les formes, reprises d'[ONTRadius].
 *
 * `ONTRadius` existait déjà et n'était lu que par trois `clip` manuels. Le
 * brancher sur `Shapes` fait que tout composant Material posé désormais prend
 * l'arrondi de la maison sans qu'on ait à le lui dire.
 *
 * Une conséquence visible, et voulue : les feuilles du bas tirent leur arrondi
 * d'`extraLarge`. Elles passent donc de 28 dp — le défaut de Material — à
 * 22 dp, celui des cartes. Deux arrondis pour deux surfaces de même rang était
 * un accident, pas une intention.
 *
 * `pill` n'y figure pas : une capsule n'est pas un rang de la gamme Material,
 * c'est une forme qu'on demande explicitement.
 */
internal val ONTShapes: Shapes = Shapes(
    extraSmall = RoundedCornerShape(ONTRadius.highlight),
    small = RoundedCornerShape(10.dp),
    medium = RoundedCornerShape(14.dp),
    large = RoundedCornerShape(ONTRadius.block),
    extraLarge = RoundedCornerShape(ONTRadius.card),
)
