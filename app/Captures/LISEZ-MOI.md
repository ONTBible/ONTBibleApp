# Les captures pour l'App Store

Produites par `scripts/captures.sh`, pas à la main : une capture reprise à la
main après chaque changement visuel finit par montrer une version qui n'existe
plus. C'est arrivé — celles du 13 août ont survécu à deux refontes de la mise
en page iPad, et sont restées en vitrine.

| dossier | contenu | committé |
|---|---|---|
| `brut/` | ce que rend le simulateur | non, régénérable |
| `iphone-6.9/` | les affiches, 1320 × 2868 | **oui**, c'est ce qu'on téléverse |
| `ipad-13/` | les affiches, 2064 × 2752 | **oui** |

Les deux tailles sont **obligatoires**, l'app visant iPhone et iPad ; Apple
redimensionne pour les écrans plus petits.

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
cerclé d'or qui déborde par le bas. Les textes sont ceux de la description de
la fiche, mot pour mot : les réécrire ici, c'est se garantir deux versions qui
divergeront.

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
