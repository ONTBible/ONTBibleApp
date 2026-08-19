# La synchronisation des dépôts ONT

**Ce fichier est identique partout où il se trouve** — à la racine
`~/ONTBible/` et dans chaque dépôt. Le modifier à un seul endroit, c'est le
casser : chaque dépôt aura l'air cohérent tout seul, et personne ne verra la
divergence.

---

## La règle

Après **chaque** travail dans l'un des dépôts, avant de dire que c'est fini :

1. **Demander ce que ce travail change pour les autres.** Pas « est-ce que j'y
   ai touché » — *ce qu'il change pour eux*. Un fichier déplacé, un format de
   sortie modifié, une couleur, un nom, un numéro de version : rien de tout
   cela ne se voit depuis le dépôt voisin.
2. **S'il change quelque chose, le porter chez eux** — dans la même session,
   pas « plus tard ». Plus tard, c'est la personne suivante qui découvre la
   rupture, sans savoir ce qui l'a causée.
3. **Inscrire la ligne au journal**, en bas de ce fichier, et pousser ce
   fichier identique partout.

**Sans exception.** N'avoir rien à porter est une conclusion, pas une dispense :
elle se constate, elle ne se suppose pas.

## Se lancer depuis la racine

Les dépôts sont côte à côte sous `~/ONTBible/`. **Ouvrir une session depuis la
racine** plutôt que depuis un dépôt : les autres sont alors visibles, et le
`CLAUDE.md` de la racine se charge de toute façon pour tout travail mené dans
un sous-dossier — la règle suit, même quand on descend dans un seul dépôt.

---

## Les dépôts

Un seul projet, découpé par la technique, pas par le sujet. Org GitHub :
[`ONTBible`](https://github.com/ONTBible).

| dépôt | ce qu'il porte |
|---|---|
| [`ONTBibleTranslation`](https://github.com/ONTBible/ONTBibleTranslation) | le vault — la traduction elle-même. La **source** de tout le reste |
| [`ONTBibleApp`](https://github.com/ONTBible/ONTBibleApp) | le pipeline Rust, la liseuse iOS, le backend AWS |
| [`ONTBibleWebapp`](https://github.com/ONTBible/ONTBibleWebapp) | `ontbible.com` — Leptos et Axum, et **les originaux de la marque** |

Tous portent le même ruleset : `main` protégée, passage par pull request,
**signatures exigées**, suppression de la branche après fusion.

---

## Ce qui traverse, et dans quel sens

Une flèche est une dépendance : ce qui est en amont peut casser ce qui est en
aval, jamais l'inverse.

    Translation ──► App ──► Webapp
      le vault      dist/    le site lit ../ONTBibleApp/dist/

| ce qui traverse | source | qui en dépend |
|---|---|---|
| le corpus | le vault | `App/pipeline` l'écrit dans `App/dist/`, que le site lit à la compilation — **jamais copié** |
| le verset du jour | `App/dist/daily.json` | le site, par lecture directe du dépôt voisin |
| la palette | `Webapp/style/main.css` — `--color-nuit`, `--color-or`, `--color-important` | `App/…/ONTDesignSystem/Tokens/ONTColors.swift`, qui les réécrit à la main |
| le wordmark et la montagne | `Webapp/public/images/*.svg` | `App/app/Marque/wordmark.svg`, **copie versée** ; l'icône de l'app |
| les captures de l'app | `App/app/Captures/` | le site, pour `public/images/app-lecture.webp` |
| le nom public de l'auteur | partout | **Gloire Bikouta.** Jamais « Sha'eliel », qui est interne au vault |
| les domaines | partout | `ontbible.com` porte le projet, `labibleont.com` redirige, le bundle reste `com.labibleont.ONT` |

---

## Les copies qu'il faut resynchroniser à la main

Chacune est une divergence en attente. Les toucher d'un côté oblige à l'autre.

| la copie | son original | ce qui casse si elles divergent |
|---|---|---|
| `App/…/ONTColors.swift` | `Webapp/style/main.css` | l'app et le site cessent d'avoir la même peau, et rien ne le signale |
| `App/app/Marque/wordmark.svg` | `Webapp/public/images/wordmark.svg` | les affiches de l'App Store portent un dessin que le site n'a plus |
| `Webapp/public/images/app-lecture.webp` | une capture de l'app | le site montre une interface qui n'existe plus |
| le numéro de version publique | `App/app/project.yml` | la fiche App Store prépare une version que personne ne construit |
| **ce fichier** | lui-même | la règle dit une chose ici et une autre là, donc plus rien |

---

## Ajouter un dépôt

Un nouveau dépôt qui n'est pas raccordé n'est pas un quatrième dépôt : c'est un
dépôt orphelin que personne ne pensera à mettre à jour. Cinq gestes, dans
l'ordre :

1. **Le cloner sous `~/ONTBible/`**, à côté des autres. Un dépôt rangé ailleurs
   sort du champ de vision, et la règle avec lui.
2. **Y copier ce fichier**, à l'octet près.
3. **Poser le rappel en tête de son `CLAUDE.md`** — le même bloc que dans les
   autres, avec la phrase qui dit ce que *ce* dépôt donne aux autres et ce
   qu'il leur prend.
4. **L'inscrire ici** : dans le tableau des dépôts, dans le schéma des
   dépendances, et dans les copies à resynchroniser s'il en introduit.
   Répercuter le fichier partout, racine comprise.
5. **Lui donner le même ruleset** sur GitHub : `main` protégée, pull request,
   signatures, suppression de branche après fusion.

---

## Journal

Ce qui a traversé, et quand. Une ligne par franchissement — pas un changelog du
dépôt, seulement ce que les autres devaient savoir.

### 19 août 2026 — `App/app/Captures/` ne contient plus les captures brutes

Les captures de l'App Store sont désormais des **affiches composées** — fond de
nuit, accroche, châssis d'appareil — produites par `App/scripts/vitrine.py`.

**Pour le site :** `public/images/app-lecture.webp` était découpé dans
`ONTBibleApp/app/Captures/`. Ce dossier porte maintenant les affiches. Les
captures nues sont dans **`ONTBibleApp/app/Captures/brut/`**, qui est *ignoré
par git* et se régénère par `./scripts/captures.sh`. Refaire `app-lecture.webp`
depuis `Captures/` donnerait une affiche entière au lieu d'une dalle.

### 19 août 2026 — le wordmark est versé dans le dépôt de l'app

`Webapp/public/images/wordmark.svg` est copié en `App/app/Marque/wordmark.svg`,
où `vitrine.py` le rastérise pour le poser sur les affiches de l'App Store.
**Toucher au wordmark du site oblige à reporter la copie**, sinon la vitrine de
l'App Store porte l'ancienne marque.
