package com.labibleont.ont.designsystem.typography

import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.intl.LocaleList
import androidx.compose.ui.text.style.Hyphens
import androidx.compose.ui.text.style.LineBreak

/**
 * Le réglage typographique de la prose française.
 *
 * ## `localeList` est la ligne qui compte
 *
 * Android choisit ses motifs de césure d'après la **langue déclarée du texte**,
 * pas d'après son contenu. Sans cette ligne, il prend celle de l'appareil : un
 * téléphone réglé en anglais coupait la prose française avec les motifs
 * anglais, et rendait « bénédic-tion » là où le français demande
 * « béné-diction ».
 *
 * Le lecteur n'y aurait vu qu'une coupure bizarre, jamais un défaut de l'app —
 * et il n'y a aucun réglage à travers lequel il aurait pu s'en plaindre.
 *
 * Les motifs français existent dans AOSP, ce sont ceux de TeX. Il suffit de
 * dire que c'est du français.
 *
 * ## Les deux autres vont ensemble ou ne servent qu'à moitié
 *
 * `LineBreak.Paragraph` demande à Android sa stratégie de haute qualité — celle
 * qui regarde le paragraphe entier au lieu de couper ligne par ligne. Son
 * propre KDoc précise « **y compris la césure, si elle est activée** » : seule,
 * elle ne coupe donc rien.
 *
 * `Hyphens.Auto` l'active. Les deux API sont stables depuis janvier 2023.
 *
 * ## Ce que ça change pour la mesure du texte
 *
 * Une colonne de téléphone fait trente-cinq à quarante-cinq signes. Sans
 * césure, un mot long en fin de ligne laisse un trou que rien ne comble — et le
 * français en abonde : « miséricordieux », « commandements »,
 * « intraduisible ». C'est là que la dentelure du bord droit se voit, et c'est
 * là que la lecture accroche.
 */
public object ONTProse {

    /**
     * À fusionner avec le style de l'appel — jamais à remplacer.
     *
     * `TextStyle.merge` garde ce que l'appelant a posé et complète le reste,
     * de sorte qu'une taille ou une couleur locale survit. L'inverse effacerait
     * l'interligne calculé sur le réglage du lecteur.
     */
    public val francaise: TextStyle = TextStyle(
        localeList = LocaleList("fr-FR"),
        lineBreak = LineBreak.Paragraph,
        hyphens = Hyphens.Auto,
    )
}
