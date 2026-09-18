# Les captures pour l'App Store

Produites par `scripts/captures.sh`, pas à la main : une capture reprise à la
main après chaque changement visuel finit par montrer une version qui n'existe
plus. C'est arrivé — celles du 13 août ont survécu à deux refontes de la mise
en page iPad, et sont restées en vitrine.

| dossier | contenu | committé |
|---|---|---|
| `brut/` | ce que rend le simulateur | non, régénérable |
| `mac/` | les affiches, 2880 × 1800 | **oui** |
| `iphone-6.9/` | les affiches, 1320 × 2868 | **oui**, c'est ce qu'on téléverse |
| `ipad-13/` | les affiches, 2064 × 2752 | **oui** |

Les deux tailles d'iOS sont **obligatoires**, l'app visant iPhone et iPad ;
Apple redimensionne pour les écrans plus petits.

## La règle, et ce qui la tient

> **La vitrine montre l'app qui existe.** Un jeu de captures pris avant le
> dernier changement d'interface n'est pas réputé juste — il est réputé
> inconnu, et il se refait avant de partir chez Apple.

Le paragraphe d'ouverture disait déjà **comment** les produire ; il ne disait
pas **quand**, et rien ne le vérifiait. Trois récidives en sont sorties, la
même à chaque fois :

    13 août 2026   survivent à deux refontes de la mise en page iPad
    19 août 2026   les jeux iPhone et iPad y restent un mois — l'affiche 01
                   annonce « Nistarot 0/6 » quand le corpus en porte 2, et
                   l'affiche 04 « Trois livres sur soixante-dix » quand il y
                   en a cinq depuis le 11 septembre
    31 août 2026   ceux du Mac traversent la refonte entière

Trois fois, c'est le signe qu'on réparait la manifestation — refaire les
images — et jamais la règle. **Une capture périmée n'est pas une négligence :
c'est ce que produit une chaîne où rien ne peut rougir.** La garde de
`soumettre.py` refuse une version **sans** captures ; personne ne refusait une
version aux captures **fausses**.

## Une vitrine ne dépend d'aucun état de la machine

> Ni l'onglet retenu, ni le thème de la dernière séance, ni la barre repliée,
> ni l'apparence du simulateur. **Le remède n'est pas de remettre chaque
> réglage : c'est d'effacer ce qui les porte.**

Formulé par la session iOS le 18 septembre 2026, après que trois correctifs
séparés eurent dit la même chose sans le savoir : `-tab bible` au lancement du
Mac, la barre latérale imposée ouverte en mode capture, l'apparence forcée dans
`serie()`. Trois clés remises à la main — et la quatrième aurait été oubliée.

**Et le remède n'est pas le même des deux côtés, parce qu'il porte une
prémisse qu'il ne dit pas.** « Effacer ce qui les porte » tient sur simulateur
**parce que la machine y est jetable** : le conteneur ne contient rien qui
appartienne à quelqu'un. Sur le Mac, le même conteneur est le **vrai** lecteur
de l'auteur — `lecteur.json` d'Application Support y tient ses surlignages, ses
notes, sa position, et le réglage « français reçu » avec eux. Le même geste y
devient une destruction.

Le Mac fait donc autrement : `-tailleDeCapture` et `-tab bible` passent par le
**domaine des arguments de lancement**, que `UserDefaults` lit en priorité — ce
qui n'atteint pas ce qui vient d'un JSON. Pour cette famille-là, le geste juste
n'est pas d'effacer mais de **pointer ailleurs** : détourner le dossier du
store vers un emplacement jetable, le temps de la campagne. Même effet, sans
toucher à ce qui n'est pas à nous.

**Ne pas transposer par symétrie.** Un remède qui marche sur une plateforme et
détruit sur l'autre a l'air d'une cohérence, et c'est ce qui le rend
dangereux — sa prémisse était vraie là-bas, pas ici.

Sa reprise a montré pourquoi la liste ne suffit pas. Le thème sombre de l'iPad
ne venait **pas** de l'apparence du système : `simctl ui appearance light` ne
l'atteignait pas, parce que le thème de lecture est une préférence de l'app et
qu'`install` par-dessus garde le conteneur de données. La désinstallation avant
installation ferme la famille entière d'un coup — thème, onglet, position de
lecture — et couvre la prochaine préférence sans qu'on y pense.

**Sa sœur, apprise sur la garde de la campagne elle-même :**

> Un instrument qui mesure une propriété en croyant en mesurer une autre **ne
> rougit jamais sur le cas réel.**

La garde refusait une capture dont la luminance moyenne était basse, en croyant
refuser un écran non rendu. Un iPad en thème sombre, parfaitement rendu, était
donc rejeté — et un aplat crème, accepté. Comme le thème de Gloire est sombre,
elle ne pouvait échouer que sur sa configuration à lui. Elle compare désormais
l'**écart-type** : un écran vide est uniforme quelle que soit sa couleur, un
écran rendu porte du texte et des bords.

`scripts/eprouver-la-fraicheur-des-captures.sh` tient la règle de fraîcheur, et
`tests` le lance à chaque proposition. Il compare deux dates que git tient de
lui-même : il ne déclare rien, donc il ne peut pas mentir. Son en-tête dit ce
qu'il n'attrape pas — **une scène cassée par la donnée**, comme la quatrième
du Mac qui visait `ont://term/elohim`, clé morte depuis que le demi-anneau est
signifiant : la vitrine a montré « Terme non documenté » sans qu'une ligne
d'interface ait bougé.

## Pourquoi une affiche et pas la capture

Une capture nue ne sert personne. En vignette de fiche, l'interface n'est plus
lisible ; et dans un lien partagé, iMessage la reprend telle quelle. Le lien de
l'app donnait une carte où l'on ne distinguait rien — le défaut relevé le
19 août 2026.

Le détail qu'on ne devine pas : Apple **échantillonne la couleur de fond de la
capture n°1** et la publie dans le JSON de la fiche (`backgroundColor`).
iMessage en teinte la bulle entière. Une première capture sur parchemin donnait
une carte blafarde ; le fond de nuit assombrit toute la carte.

`scripts/vitrine.py` compose les affiches — marque, accroche, phrase, appareil
qui déborde par le bas. Les textes sont ceux de la description de la fiche, mot
pour mot : les réécrire ici, c'est se garantir deux versions qui divergeront.

Le châssis est dessiné, pas emprunté : `simctl` ne rend que la dalle. Un simple
rectangle arrondi a d'abord été essayé, et l'affiche s'est fait prendre pour un
appareil Android. Ce qui dit « Apple », c'est l'arête de titane, la lunette
noire, les boutons sur la tranche, la Dynamic Island de l'iPhone — et, sur
l'iPad, la caméra sur le **bord long**, où elle a déménagé avec le M4 : la
mettre en haut, c'est dessiner un iPad d'avant 2024. Tout est dans `CADRES`, en
fractions de la largeur, un dossier par appareil.

## Les quatre écrans

Dans l'ordre où ils racontent quelque chose :

1. le corpus — les 70 livres, et ce qui en est traduit ;
2. la lecture — les trois niveaux visibles d'un coup d'œil ;
3. une fiche d'intraduisible — ce que promet chaque mot d'or ;
4. la table d'un livre.

L'unité montrée est **Bereshit 3**, verrouillée. Bereshit 1 porte la mention
« Brouillon », honnête dans l'app mais mal choisie pour une vitrine.

La barre d'état est figée à 9:41, batterie pleine : sans ça elle porte l'heure
de la machine, la date en anglais — le simulateur ne suit pas la langue de
l'app — et une jauge à moitié vide.
