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

### 19 août 2026 — tout nom propre porte `==…==`, dans les trois dépôts

**Source : le vault.** Le §2.5 bis généralise sa règle — tout nom propre est
balisé `==Nom==` à **chacune** de ses occurrences, corps du texte et gloses
comprises. 1 898 marques posées par
`ONTBibleTranslation/scripts/marquer-les-noms-propres.py`, idempotent, à
relancer après chaque chapitre écrit.

**Pour l'app et le site : rien à changer, et c'est pourquoi `==` a été retenu.**
Le pipeline lit déjà `==…==` comme un terme important, `ONTColors.important` le
rend en `#862742` (parchemin, clair) et `#D87994` (sombre, mystique), le site en
`--color-important`. Une quatrième marque aurait demandé un type de nœud, une
teinte de plus dans la rampe, un rendu Swift et un rendu Rust — quatre endroits
à tenir d'accord pour dire ce que la marque existante disait déjà.

**Ce qui traverse quand même :** les données. Toucher au vault oblige à rejouer
le pipeline **et** à recopier `dist/` dans `App/app/Resources/data/`, sinon
l'app affiche l'ancien corpus sans que rien ne le signale. Fait dans la même
session.

**Deux noms restent nus, et attendent l'auteur :** `Shem` et `Adam` sont tantôt
noms propres, tantôt intraduisibles — la casse ne les sépare pas, et 126
occurrences nues mélangent les deux sens. Les marquer en masse donnerait du
bordeaux à des intraduisibles.

### 19 août 2026 — le linker d'Apple ne tient plus le corpus embarqué

**Ne concerne que le site, mais toute session macOS le rencontrera.**
`ONTBibleWebapp` embarque tout `dist/` par `include_str!` : passé deux
mégaoctets de données statiques, `ld` refuse ou plante. Le défaut était masqué
par la compilation incrémentale et se découvre au premier `cargo clean` — on
croit alors avoir cassé quelque chose, et l'on cherche dans le mauvais commit.

Correction : `Webapp/scripts/linker-local.sh`, à lancer **une fois par
machine**, plus un `[profile.dev]` dans son `Cargo.toml`. Aucun des deux ne
suffit seul. Ni la CI ni le déploiement ne sont touchés.

**Ce qui traverse :** le corpus grossit à chaque livre. Ce sursis tombera vers
le cinquième ou sixième, et la réponse sera alors de compresser les JSON
embarqués — décision qui appartient au site, mais que le vault déclenche.

### 20 août 2026 — le lexique du lecteur sort de `CLAUDE.md`

**Source : le vault.** Les fiches d'intraduisibles étaient engendrées depuis
`ONTBibleTranslation/CLAUDE.md`, qui est une *référence de traduction* : le
lecteur qui touchait un mot d'or recevait l'arbitrage du traducteur — deux
phrases pour **Elohim**, 238 octets pour **YHWH**, trois lignes de médiane.
L'explication au lecteur vit désormais dans **`lexique/<lemme>.md`** (§2.5 ter).

**Pour l'app :** `pipeline/src/reference.rs` lit ce dossier et **recouvre le
champ `definition`**. Rien ne change au schéma — les fiches passent donc par
`CorpusUpdater` et atteignent les apps **déjà installées**, sans revue Apple.

**Contrainte à connaître avant d'écrire une fiche :** `TermSheet.swift` ne rend
que `Block::Para` et **laisse tomber le reste sans rien dire**. Un titre ou une
liste dans une fiche disparaît chez le lecteur, en silence. Des paragraphes,
donc — jusqu'à ce que la vue sache rendre le reste.

**Pour le site :** il embarque `dist/` à la compilation ; les fiches denses
arrivent au prochain déploiement, sans rien à changer chez lui.

### 20 août 2026 — le relevé des noms propres avait trois trous

**Source : le vault.** `marquer-les-noms-propres.py` annonçait « 0 marque à
poser » alors que quatre-vingts occurrences étaient nues : il ne voyait le nom
que par son niveau 3 capitalisé. Il a désormais une seconde source — le mot
capitalisé collé au niveau 3 — et **il nomme ce qu'il écarte**, parce qu'un
relevé muet sur ses refus se lit comme une couverture complète.

**Deux arbitrages d'auteur reportés partout :** les gentilés sont des noms
propres, sans exception ; **Nephilim** passe en intraduisible — l'or supplante
le bordeaux — et sa fiche reste à écrire.

**Pour l'app et le site : rien à changer.** La chaîne a été vérifiée de bout en
bout — `pipeline/src/inline.rs:325` → `ONTTextRenderer.swift:242` →
`ONTBibleWebapp/src/interface/design/verset.rs:135`.
