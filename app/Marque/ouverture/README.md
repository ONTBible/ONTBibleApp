# Le mouvement de l'ouverture

La source du dessin composé par l'auteur avec Claude Design, dont
`ONTDesignSystem/Surfaces/ONTSplash.swift` est le portage.

Elle est ici pour une raison précise : **une animation portée dans un autre
langage perd sa source si on ne la garde pas.** Le Swift dit *ce que* le
mouvement fait ; ces fichiers disent *ce qu'il devait faire*. Le jour où il
faudra le retoucher — ou le porter sur Android, où il n'existe pas encore —,
c'est ici qu'on retrouvera les valeurs d'origine plutôt que dans une
reconstitution à l'œil.

## Le fichier qui compte

`logomark-sweep.jsx` — tout le reste l'entoure.

    scène        durée    courbe            ce qu'elle fait
    ─────────────────────────────────────────────────────────────────────
    Attente      1,1 s    easeOutCubic      le logomark sort de la pénombre
    Balayage     2,8 s    easeInOutSine     le front va de −0,22 à 1,22
    Repos        1,6 s    easeOutQuad       la rémanence retombe de 0,8 à 0
                 ─────
                 5,5 s

Le front **naît et meurt hors du cadre** : on ne le voit jamais apparaître ni
s'éteindre. La lueur est un empilement de cinq ombres portées — 12, 34, 80,
160 et 300 px — et c'est l'empilement qui la fait décroître avec la distance
au lieu de former un halo uniforme.

Les scènes sont déclarées dans `Logomark light sweep.dc.html`, pas dans le
`.jsx` : `window.OM_SCENES` les porte, et le composant lit ses repères
dedans.

## Ce que le portage a changé, et pourquoi

**Le fond.** Le dessin est sur `#0b0b0b` ; l'app emploie `ONTColors.nuit`
— `#18090D`, le fond de `ontbible.com` — assombri au bord. Un noir de
circonstance devenait une teinte de la maison, sans rien coûter.

Le fond **doit** rester sombre : toute la lumière passe par un mélange
`screen`, qui n'a aucun effet sur un fond clair.

**La taille.** Le logomark occupe presque toute la largeur dans le dessin, ce
qui va sur une page où il est le sujet. Dans l'app il est une marque : 36 %
de la largeur, plafonné à 225 pt — et ce plafond ne mord que sur tablette.

Rien d'autre n'a bougé. Les trois durées, les trois courbes, les bornes du
front et la géométrie de la lueur sont celles d'ici.

## Rejouer l'animation

Ouvrir `Logomark light sweep.dc.html` dans un navigateur. `support.js` est le
moteur de Claude Design, vendu avec : sans lui les `.dc.html` ne rendent
rien.

`uploads/logomark.svg` est le tracé employé par le dessin. Il est le même que
`ONTBibleWebapp/public/images/logomark.svg` au caractère près — seule la
balise de fermeture diffère, `</path>` contre `/>`. L'app, elle, n'emploie
aucun des deux : elle passe par `montagne.imageset`, la même montagne en
gabarit, qui sert déjà la carte du verset du jour.

## Les deux autres fichiers

`Splash screens iOS Android.dc.html`, `ios-frame.jsx` et `android-frame.jsx`
montrent le mouvement dans un cadre d'appareil. Ils n'ont pas été portés :
l'app est le cadre.
