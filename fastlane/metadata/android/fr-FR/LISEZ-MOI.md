# La fiche Play — ici, et pas dans un formulaire

Ces fichiers sont la fiche de `com.labibleont.ont` sur le Play Store. Ils
suivent l'arborescence attendue par `fastlane supply` et par les actions
GitHub qui téléversent vers Play, si bien qu'ils sont directement
consommables le jour où `livraison-android.yml` poussera tout seul.

Le texte vit ici pour la même raison que celui de l'App Store vit dans
`.github/scripts/fiche.py` : **il se relit en diff, il se corrige en pull
request, et il ne se perd pas.** Une fiche remplie à la main dans un
formulaire finit par décrire une version que personne ne construit.

## Ce que Play exige, et qui a été vérifié

| pièce | exigence | ici |
|---|---|---|
| `title.txt` | 30 signes | 12 |
| `short_description.txt` | 80 signes | 70 |
| `full_description.txt` | 4000 signes | 1409 |
| `changelogs/1.txt` | 500 signes, nom = `versionCode` | 319 |
| `images/icon.png` | 512×512, PNG 32 bits **avec** alpha, ≤ 1 Mo | ✅ |
| `images/featureGraphic.png` | 1024×500, PNG 24 bits **sans** alpha | ✅ |
| `images/phoneScreenshots/` | 2 à 8, PNG 24 bits sans alpha | 8 |

Deux pièges qui ne se voient qu'au refus :

**Les captures ne peuvent pas porter d'alpha.** `adb exec-out screencap -p`
en produit toujours, et Play les refuse sans dire pourquoi. Elles sont
aplaties sur du blanc — aplaties et non dépouillées, parce que jeter le canal
supposerait que les pixels transparents portent déjà la bonne couleur.

**La plus grande dimension ne peut pas dépasser le double de la plus petite.**
L'émulateur de référence rend du 1280×2856, soit un rapport de 2,23 : ses
captures seraient refusées. Elles sont prises à 1080×1920 — le format que Play
recommande par ailleurs pour paraître dans les grandes vignettes.

## Refaire les captures

    adb shell wm size 1080x1920 && adb shell wm density 420

puis on parcourt l'app, et on aplatit avant de ranger. Remettre ensuite :

    adb shell wm size reset && adb shell wm density reset

L'ordre des captures n'est pas indifférent : Play montre les premières en
grand et beaucoup de gens ne font jamais défiler. On ouvre donc sur la
liseuse et ses trois niveaux, qui est ce que l'app a de propre.

## Ce que ces fichiers ne portent pas

La sécurité des données, le questionnaire de contenu, le public cible et la
politique de confidentialité ne sont pas ici : Play ne les expose pas par
fichier, et sans eux la publication est refusée. Ils se remplissent dans la
console.
