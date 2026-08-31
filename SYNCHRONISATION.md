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
| la palette | `Webapp/style/main.css` — `--color-nuit`, `--color-or`, `--color-accentuation` | `App/…/ONTDesignSystem/Tokens/ONTColors.swift`, qui les réécrit à la main |
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

## Plusieurs sessions à la fois — se parler, toujours

**Posé le 21 août 2026, après deux pertes dans la même journée.**

Il arrive que deux sessions Claude — ou plus — travaillent en même temps sur
ces dépôts. Elles ne partagent pas des copies : elles partagent **les mêmes
dossiers et le même arbre de travail**. Ce qu'une session écrit, l'autre le
voit ; ce qu'une session jette, l'autre le perd.

Ce jour-là, une session a lancé `git reset --hard origin/main` dans
`ONTBibleWebapp` et jeté une journée de travail non commité. Quelques heures
plus tard, la même a commité et rebasé dans `ONTBibleApp` **sans regarder sur
quelle branche elle était** : son correctif a atterri sur la branche de
l'autre, et son `push` a échoué sans qu'elle le voie.

### La règle

**Se parler, et d'abord.** `ListAgents` montre les autres sessions ;
`SendMessage` leur écrit. Le réflexe n'est pas « je vérifie s'il y a quelqu'un
quand ça coince », c'est **« je dis ce que je vais faire avant de le faire »** —
et ça vaut entre toutes les sessions, y compris celles qui viendront.

Quatre moments où le silence coûte cher :

1. **À l'ouverture d'une session** qui va toucher un dépôt : annoncer sur quoi
   on part, et demander si quelqu'un y est déjà.
2. **Avant toute opération destructive** — `reset --hard`, `rebase`, `checkout`,
   `stash`, `clean`. Prévenir, et attendre la réponse. Aucune de ces commandes
   ne distingue son travail de celui d'un autre.
3. **Avant de fusionner ou de promouvoir**, parce que ça déplace le sol sous
   les branches des autres.
4. **En rendant**, pour dire ce qui a changé et ce qui reste à faire.

### L'arbre de travail se tient à un seul — ou, mieux, on n'en partage pas

Une seule session à la fois, et la passation est **explicite** : « je prends » /
« je rends », vérifiée avant — `git branch --show-current`, `git status` — et on
ne touche à rien entre les deux. Annoncer qu'on prend l'arbre ne suffit pas : il
faut déplacer `HEAD`, et le constater.

C'est un protocole social. Il tient tant que tout le monde s'en souvient, et il
coûte une journée le jour où quelqu'un l'oublie. On peut faire mieux.

### `git worktree` — rendre le conflit impossible plutôt que déconseillé

**Posé le 24 août 2026.** Deux sessions travaillaient en parallèle sur
`ONTBibleApp` ; l'une a changé de branche pendant que l'autre écrivait. Rien n'a
été perdu — elle a prévenu, et vérifié après coup que la branche voisine était
intacte — mais le seul rempart avait été sa vigilance.

Un dépôt git confond deux choses parce qu'elles vivent au même endroit : le
dossier `.git`, qui porte **toute** l'histoire, et les fichiers autour, qui n'en
montrent **qu'une branche**. D'où la limite : un dépôt, une branche visible. En
changer déplace les fichiers de tout le monde.

`git worktree` sépare les deux :

    git worktree add ../ONTBibleApp-android ma-branche

donne un **second dossier de fichiers**, sur une **autre branche**, partageant le
**même** `.git`. Ce n'est pas un clone : rien n'est dupliqué, et le `.git` du
nouveau dossier n'est même pas un dossier — c'est un fichier d'une ligne qui
renvoie vers l'original.

    ONTBibleApp/              ← branche A        session 1
      .git/                   ← l'histoire, partagée
    ONTBibleApp-android/      ← branche B        session 2
      .git                    ← un renvoi, pas une copie

Chaque dossier a son propre `HEAD`. Un `switch` chez l'une ne touche plus
l'autre. Les commandes utiles tiennent en quatre lignes :

    git worktree list                    qui travaille où, sur quelle branche
    git worktree add <dossier> <branche>
    git worktree remove <dossier>
    git worktree prune                   nettoie les dossiers effacés à la main

**Quand l'employer.** Dès qu'une session sœur est présente — `ListAgents` le
dit. Le monter coûte une seconde ; la passation d'arbre coûte une conversation,
et un oubli coûte une journée.

**Quatre choses à savoir, dont une qui mord.**

1. **Une branche ne s'ouvre que dans un seul worktree.** Git refuse la seconde
   sortie — c'est une protection : deux dossiers sur la même branche
   divergeraient.
2. **Les fichiers non suivis ne suivent pas.** C'est le vrai piège, et il s'est
   présenté le jour même : le travail en cours n'était pas encore commité, il a
   fallu le déplacer à la main. Commiter avant de monter le worktree l'évite.
3. **Branches, commits, `stash` sont partagés** — c'est le même dépôt. Seuls les
   fichiers de travail sont séparés, et c'est exactement ce qu'on veut.
4. **Les artefacts de build sont à refaire.** Chaque worktree a ses `target/`,
   `build/`, `.gradle/`. Compter une première compilation complète, et un
   `cargo clean` de plus en fin de chantier.

5. **Un worktree retient sa branche, même fusionnée.** `git branch -d` refuse —
   « cannot delete branch used by worktree » — et la suppression automatique
   après fusion échoue de la même façon. Rencontré le 25 août, sur trois
   branches à la fois. La parade tient en un geste : **démonter le worktree dès
   que la branche est poussée**, sans attendre la fusion. Le travail vit alors
   sur le distant, et il n'y a plus rien à retenir.

6. **Ne jamais écrire dans la copie de la racine puis diffuser.**
   `~/ONTBible/SYNCHRONISATION.md` se présente comme la source des quatre, et
   c'est la seule que **rien** ne synchronise : la racine n'est pas un dépôt,
   aucun `pull` ne l'atteint, aucune fusion ne la corrige. Elle dérive donc en
   silence, et la recopier dans les dépôts n'y perd rien — elle y **impose un
   état périmé**.

   C'est arrivé le 25 août : trois entrées écrites à la racine puis recopiées
   ont effacé de l'app toute cette section-ci, arrivée par une fusion que la
   racine ignorait. Le vault et le site n'ont survécu que par accident, leurs
   propres PR la rapportant en parallèle.

   Partir d'un dépôt à jour, toujours, et porter le changement dans chacun.

7. **Une commande qui écrit sur le distant laisse l'arbre partagé périmé sur sa
   propre branche.** `gh pr update-branch` fusionne la branche de base **dans le
   dépôt distant** : l'arbre local ne l'apprend pas, et se retrouve en retard
   sur la branche qu'il croit tenir. Un commit posé par-dessus écraserait la
   fusion.

   Ce qui le rend dangereux n'est pas l'écart mais le silence : **`git status`
   répond « propre », et il dit vrai** — il compare l'arbre à l'index, pas à
   `origin`. Rien dans sa sortie ne suggère d'aller regarder ailleurs.

   Trouvé le 25 août par une session qui arrivait sur l'arbre et l'a contrôlé
   avant d'y écrire. La parade : `git fetch` puis `git rev-list --left-right
   --count origin/<branche>...HEAD` avant de toucher un arbre qu'on ne vient pas
   de quitter — et `git pull --ff-only` après toute commande `gh` qui écrit.

**Ce que ça ne remplace pas.** Se parler. Le worktree protège les fichiers, pas
les décisions : deux sessions qui refondent le même module chacune de leur côté
produiront deux refontes, proprement isolées et incompatibles.

### Vérifier ce que l'autre affirme

Une session sœur travaille de bonne foi et se trompe quand même. Ce jour-là,
quatre affirmations sur l'état du dépôt étaient fausses — dans les deux sens,
chacune de nous s'y est mise.

Donc : **on ne valide pas un raisonnement dont on ne peut pas voir les pièces.**
Avant de sauter des commits qu'on vous dit « déjà en amont », comparer le
contenu. Avant de croire qu'un fichier a survécu, chercher le **nom du symbole**
et non un mot qui y ressemble — dans un dépôt écrit en français, le vocabulaire
du domaine est partout dans les commentaires, et `grep "glose"` ne prouve rien.

Et vérifier son propre instrument avec la même sévérité : deux de ces quatre
erreurs venaient d'une commande mal écrite qui avalait sa sortie, pas d'une
donnée fausse. C'est la règle du §4 du site tirée du DNS — on ne juge pas un
enregistrement sur ce qu'on croit avoir collé.

### Commiter tôt, sur une branche à soi

Un travail non commité n'est protégé de rien. C'est ce qui a rendu la première
perte possible. Dès que ça compile : une branche, un commit signé.

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

### 21 août 2026 — le corpus publié suit `dev` de l'app, plus `main`

**Source : le site.** `deployer.yml` clonait `ONTBibleApp` sur sa branche par
défaut pour compiler le pipeline. Il clone désormais **`dev`**.

**Pourquoi.** Le pipeline sert deux consommateurs de cadences opposées : le
corpus publié atteint les apps **déjà installées** en minutes, par
`CorpusUpdater`, sans revue ; le binaire iOS met des jours. Tant que le site
clonait `main`, la publication du corpus héritait du filtre de toute la chaîne
de promotion — une correction de pipeline ne pouvait pas atteindre un lecteur
sans qu'un build parte chez Apple. C'est ce qui a tenu les cent six fiches de
lexique hors de portée alors que le code était fusionné et testé.

**Pour l'app :** une correction de `pipeline/**` fusionnée dans `dev` part en
ligne au prochain déploiement du site. Elle n'attend plus `staging` ni `main`.
La chaîne de promotion du **binaire** ne change pas.

**Le garde-fou qui vient avec, et pourquoi il n'est pas optionnel.**
`CorpusUpdater` s'abstient **en silence** devant un manifeste dont le schéma lui
est inconnu : ni erreur, ni trace, elle reste sur son bundle. Publier un schéma
monté cesserait donc de mettre à jour tous les lecteurs installés sans que rien
ne le dise. Deux constantes, dans deux dépôts, qu'aucun test ne rapprochait —
`"schema": 1` dans `corpus-publie.py`, `static let schema = 1` dans
`CorpusUpdater.swift`. Le déploiement les compare et refuse de publier si elles
divergent, la référence étant **`main` de l'app**, c'est-à-dire ce qui est en
vente.

**Conséquence à retenir :** monter le schéma du corpus demande désormais de
livrer d'abord une version de l'app qui sait le lire. C'est l'ordre correct, et
il est maintenant imposé plutôt que supposé.

### 21 août 2026 — publier fait sonner les téléphones

**Source : l'app et le site, mais la conséquence est pour le vault.**

Jusqu'ici, publier depuis `ONTBibleTranslation` déposait un corpus qu'un lecteur
découvrait à l'ouverture de l'app. Désormais, la même publication **notifie** :
une alerte par livre paru, une par chapitre, une quand un lemme entre au
lexique.

**Ce que le vault doit en retenir.** Une fusion dans `main` du vault n'est plus
un geste silencieux. Elle atteint un écran verrouillé, le soir, sans que
personne ne l'ait demandée au moment où elle arrive. Deux règles en découlent :

- **Ne pas publier pour éprouver.** Un aller-retour `brouillon` → `locked` →
  `brouillon` sur un chapitre déjà paru ne renotifie pas — c'est garanti par
  `NouveautesNotifications` — mais un livre publié par erreur, si.
- **Un chapitre paraît une fois.** L'état est retenu en `livre:chapitre`, pas en
  identifiant de chapitre nu : deux chapitres 3 dans deux livres ne se
  masquent plus l'un l'autre. Renommer un livre revient donc à faire reparaître
  tous ses chapitres. À faire, si besoin, avant la première parution.

**Deux chemins, pas un.** L'app décide seule, hors ligne, en comparant le corpus
qu'elle vient de télécharger à celui qu'elle avait — c'est le chemin qui marche
sans serveur ni consentement. Le push distant (APNs) ne sert qu'à l'instantané :
le déploiement du site appelle le backend, qui pousse. Si le backend tombe,
l'alerte arrive quand même, à la prochaine ouverture. **Aucune parution ne
dépend d'Apple.**

**Pour le site : deux étapes ajoutées à `deployer.yml`.** « L'annonce de la
parution » compare le plan publié au précédent et n'appelle le backend que sur
une vraie différence — un redéploiement sans changement de texte ne notifie
personne.

**Pour la confidentialité.** Un jeton d'appareil retenu côté serveur révèle
qu'un appareil lit une Bible : c'est une donnée de l'article 9 du RGPD. Le push
est donc **désactivé par défaut**, activé sur consentement explicite, et le
retrait efface le jeton du serveur **avant** de se désinscrire chez Apple —
jamais l'inverse, sous peine de laisser un jeton orphelin. `confidentialite.rs`
le dit désormais en toutes lettres ; il affirmait le contraire.

**Une clé APNs ne couvre qu'un environnement.** Une clé de production est
refusée par le serveur bac à sable avec `BadEnvironmentKeyInToken`, et
réciproquement. Le backend en porte donc **deux**, indexées par environnement.
Sans cela, la moitié des appareils échouait sans que rien ne le signale.

### 21 août 2026 — « important » devient « accentuation », le fil compris

**Source : partout à la fois.** Le troisième niveau de marquage — `==mot==` —
s'appelait « le terme important ». Il s'appelle désormais **l'accentuation**,
dans les trois dépôts, dans la prose comme dans le code : `Inline::Accentuation`
en Rust, `.accentuation` en Swift, `Noeud::Accentuation` sur le site,
`--color-accentuation` en CSS.

**Le tag du fil change avec le nom — et c'est ce qui demande de l'attention.**
L'enum Rust tire son tag de son nom de variante ; le corpus publie désormais
`{"t":"accentuation"}`. Les versions 1.0.1 et 1.0.2 attendent `"important"` et
leur décodeur **lève** sur un nœud inconnu.

Ce qui les protège n'est pas le décodeur, c'est le **numéro de schéma**, monté
de 1 à 2. `CorpusUpdater` compare le schéma du manifeste au sien *avant* de
télécharger quoi que ce soit et renonce à la mise à jour entière : une app
antérieure garde son corpus embarqué, intact, et cesse simplement de recevoir
les parutions jusqu'à sa propre mise à jour. C'est le comportement voulu d'un
changement de format, et la raison pour laquelle le champ existe.

**L'ordre est imposé, pas supposé.** L'étape « Le schéma du corpus » du
déploiement du site compare `corpus-publie.py` à `CorpusUpdater.swift` **sur
`main` de l'app**, et cette étape s'exécute avant la compilation. Monter le
schéma côté site pendant que `main` est en 1.0.2 bloquerait donc le déploiement
du site **entier**, pas seulement le corpus. La séquence tenable est donc :
1.0.3 sur `main` d'abord, `corpus-publie.py` ensuite.

**Ce qui n'a pas bougé.** L'adjectif français ordinaire — « le point le plus
important », « le composant le plus important du site » — n'est pas le marqueur.
Un remplacement en masse aurait corrompu une fiche de lexique et un commentaire
de rendu. Le renommage s'est fait site par site.

### 21 août 2026 — deux épingles Rust, et la seconde a manqué une journée

**Source : le site, puis l'app.** `rustup toolchain install stable` a ramené
Rust 1.98.0 sans que personne n'ait rien poussé. Son linker passe
`--fix-cortex-a53-843419`, que `cargo-zigbuild` ne sait pas filtrer. Les deux
dépôts compilent du Rust pour la même cible, par la même chaîne d'outils : les
deux ont cassé.

**Le site a été corrigé le matin** — `VERSION_RUST: "1.97.1"` dans
`deployer.yml`. **La correction n'a pas été portée dans l'app**, et son
déploiement de backend a continué d'échouer **en silence** jusqu'au soir : les
routes `/appareils` et `/diffuser` répondaient 404 en production, et le push
distant ne pouvait pas fonctionner. On a cherché la panne dans Terraform, dans
la passerelle, dans le routeur — partout sauf dans un déploiement qui échouait
déjà.

**Les deux épingles se nomment désormais l'une l'autre** dans leurs
commentaires : `ONTBibleWebapp/.github/workflows/deployer.yml` et
`ONTBibleApp/.github/workflows/deployer-backend.yml`. Remonter l'une sans
l'autre est ce qu'il faut empêcher — et rien ne le vérifie, c'est un
commentaire, pas un contrôle.

**Ce qui va avec, et qui est propre à l'app.** Le rôle AWS n'autorise le
déploiement du backend que depuis `main`, à dessein : un `workflow_dispatch`
depuis une branche est refusé par `sts:AssumeRoleWithWebIdentity`. Un correctif
de CI doit donc traverser `dev → staging → main`. Or `livraison.yml` n'avait
aucun filtre de chemins : ce trajet déclenchait un build **et une soumission à
l'App Store**, pendant qu'une revue était en cours. Un `paths-ignore` écarte
maintenant les workflows, le backend et la documentation — ce qui ne peut pas
entrer dans le binaire iOS. Il ne saute que si **tous** les fichiers touchés y
figurent, donc un changement mêlé à du code d'app livre toujours.

**La leçon, pour les trois dépôts :** un outil qui suit `stable` casse un matin
sans qu'on ait rien fait, et il casse **partout où il est employé**. Épingler
un dépôt sans regarder ses voisins ne corrige que la moitié du défaut — et
l'autre moitié échoue là où personne ne regarde.

### 24 août 2026 — `git worktree`, pour que deux sessions cessent de se disputer l'arbre

**Source : l'incident du jour, sans perte cette fois.** Deux sessions
travaillaient en parallèle sur `ONTBibleApp` ; l'une a déplacé `HEAD` pendant
que l'autre écrivait le portage Android. Rien n'a été perdu — elle a prévenu, et
vérifié la branche voisine après coup — mais le seul rempart avait été sa
vigilance, et c'est exactement ce que le 21 août avait déjà coûté.

**Pour les trois dépôts :** la section « Plusieurs sessions à la fois » ne dit
plus seulement « l'arbre se tient à un seul ». Elle documente `git worktree`,
qui donne à chaque session son propre dossier de fichiers sur sa propre branche,
avec le même `.git` — donc le même historique, les mêmes commits, et deux `HEAD`
indépendants. Le conflit devient **impossible** au lieu d'être déconseillé.

Le piège à connaître, rencontré le jour même : **les fichiers non suivis ne
suivent pas** le worktree. Commiter avant de le monter, ou les déplacer à la
main.

Cette page-ci a été écrite depuis trois worktrees, un par dépôt — les branches
en cours des sessions sœurs n'ont pas été touchées.

### 25 août 2026 — le corpus se nomme dans deux registres

**Source : le pipeline, mais la décision vient du vault.**

Chaque section et chaque livre porte désormais **deux noms**. La règle qui les
sépare tient en une ligne : **en français les intraduisibles sont rendus, en
glose ils restent en hébreu.**

    Torah              la Loi                  ⟨la Fondation⟩
    Nistarot           Écrits apocalyptiques   ⟨les Réalités voilées⟩
    Machazeh Yohanan   Apocalypse              ⟨le machazeh de Yohanan⟩

Un interrupteur laisse le lecteur passer de l'un à l'autre, **allumé par
défaut** : il faut pouvoir marcher avant de savoir. L'écart entre les deux
colonnes n'est pas une nuance de traduction — c'est ce que le projet montre.

**Pour le vault :** le pont français d'un livre vient du **nom de dossier** de
`in-writing/`. Quatorze ne menaient nulle part — `44. marqus (Marqus)` répétait
le nom ONT, `48. gevurot-ha-neviim (les Gevurot des Neviim)` n'était pas du
français. Renommer le libellé suffit ; l'identifiant, donc les URL, ne bouge
pas. La glose ONT, elle, se déclare dans `config.rs` : les libellés de dossiers
mélangent les registres et ne peuvent pas servir de source.

**Pour les liseuses :** `Chapitre 7` en français, **`Parashah 7`** en glose — et
`parashah` est un intraduisible, en or, avec sa fiche. C'est peut-être le
premier que le lecteur rencontre, puisqu'il apparaît au moment où il éteint
l'aide.

### 25 août 2026 — les renvois d'un verset à un autre mènent quelque part

**Source : le pipeline. Conséquence pour les trois liseuses.**

Une glose écrit « déjà posé en *Bereshit* 9:27 ». Ailleurs, on ouvre le
chapitre 9 et on descend. **Ici c'est impossible** : les unités ONT ne
coïncident pas avec les chapitres reçus. Le renvoi biblique est à la fois la
seule chose que le lecteur sait et précisément ce qu'il ne peut pas suivre.

218 renvois sont désormais liés. « Bereshit 9:27 » mène à `bereshit-9?v=10` —
le verset 27 est le dixième de l'unité, qui commence à 9:18.

**Le calcul refuse de conclure quand il ne peut pas.** L'unité 2 annonce
`2:4-25`, soit vingt-deux versets, et n'en porte que vingt et un : deux ont été
réunis. 48 renvois sur 218 visent un verset ; les 170 autres mènent à l'unité
**par prudence, pas par oubli**.

**Aucune montée de schéma**, à dessein : un type de nœud inédit ferait *lever*
les liseuses installées. On réemploie `Inline::Link` avec une adresse **absolue**
vers `ontbible.com` — une app ancienne l'ouvre dans le navigateur, une app à
jour reconnaît son domaine et navigue au-dedans. Le site rend le chemin relatif
et n'ouvre pas d'onglet.

### 25 août 2026 — tout champ ajouté au corpus est facultatif

**La règle a été payée deux fois dans la même journée**, et elle vaut pour les
trois dépôts.

`groups`, puis `french`, ont été ajoutés au schéma **sans valeur par défaut**.
Chaque fois, une app compilée depuis la branche ne pouvait plus lire le corpus
**publié** — qui, lui, ne porte pas encore la clé.

La distinction qui a produit le défaut, deux fois : une clé **en trop** est
ignorée par un décodeur ; une clé **manquante** sur un champ non optionnel
**lève**. Éprouver la première ne dit rien de la seconde.

**Et le numéro de schéma ne protège pas ici** : il ne bouge pas quand on ajoute
une clé. La seule garde qui l'ait attrapé, les deux fois, est le test
d'intégration qui interroge le **vrai serveur** — parce que seul un corpus
réellement publié, plus ancien que le code, peut révéler le manque.

Le corpus atteint des liseuses plus anciennes **et** plus récentes que lui.
Cela vaut aussi dans l'autre sens : un champ retiré casse les liseuses qui
l'attendent. Ajouter est sûr, retirer ne l'est pas.

### 25 août 2026 — rendre un champ facultatif est une rupture chez le voisin

**Source : le pipeline. Victime : le site.**

L'entrée précédente pose la règle — tout champ ajouté au corpus est facultatif.
Elle est juste, et l'appliquer a cassé `main` du site le jour même.

`CorpusOutline.french` et `ModeOutline.french` sont passés de `String` à
`Option<String>` dans `pipeline/src/schema.rs`. Le site **partage cette
structure** — il dépend du pipeline comme caisse, pas seulement de sa sortie.
Deux `error[E0308]`, et le dépôt voisin ne compilait plus.

**Ce qu'il faut retenir : la règle protège le décodeur, pas le compilateur.**
Rendre un champ facultatif est sûr *pour les liseuses installées*, qui liront
un corpus sans la clé. C'est une **rupture** pour tout consommateur qui partage
le type, parce qu'il doit maintenant décider quoi faire de l'absence. Les deux
sont vrais en même temps, et le second ne se voit pas depuis le dépôt qui écrit
le schéma.

**Elle a été fusionnée verte, puis cassée après coup**, par un changement du
voisin. Rien ne l'a signalé. Le seul témoin a été, par hasard, la CI d'une PR
qui ne touchait qu'un `.md`.

**Et l'immobilisation dépassait la compilation.** Le déploiement du site
republie `ontbible.com/corpus/`, que `CorpusUpdater` tire dans les apps déjà
installées. Un `main` qui ne compile pas tient donc **tout le corpus** hors de
portée des lecteurs — les deux registres, `Chapitre`/`Parashah`, les conteneurs
du Ḥurban —, alors que le code est fusionné et testé. Un site cassé n'est pas
qu'un site cassé.

La parade est un `schedule` côté site, qui recompile `main` contre le pipeline
de `dev` et ouvre une issue nommant le commit pris. Elle **détecte** la dérive ;
elle ne l'empêche pas — le site suit un pipeline mouvant parce que c'est voulu.

### 25 août 2026 — une version approuvée ferme son train de préversions

**Source : App Store Connect. Conséquence : la liseuse iOS, et un jour Android.**

Six livraisons de suite ont échoué au téléversement, toutes sur la même phrase :
*Invalid Pre-Release Train. The train version '1.0.3' is closed for new build
submissions.* 1.0.3 avait été approuvée par Apple, et une version approuvée
**ferme son train** : tout build qui la porte encore est refusé.

**L'échec arrive tard, et c'est ce qui le rend coûteux.** La compilation
réussit, l'archive se signe, et ça casse à la toute fin, une fois les minutes
payées. Il se répète à chaque fusion vers `dev` tant que le nombre n'a pas
bougé — et pendant deux jours, tout le travail fusionné n'a atteint aucun
appareil.

**La règle : monter `CFBundleShortVersionString` dès qu'Apple a approuvé la
précédente**, sans attendre que la livraison suivante casse. Le numéro de build,
lui, n'a pas ce problème : il est daté, il croît tout seul.

### 25 août 2026 — un contrôle compare enfin les quatre exemplaires de ce fichier

**Source : l'incident de la veille. Vaut pour les trois dépôts et la racine.**

Ce fichier se déclare identique partout où il se trouve. Rien ne le vérifiait.
`ONTBibleTranslation/scripts/concorder-la-synchronisation.py` le fait, depuis
n'importe où sous `~/ONTBible/`, et rend `1` quand un exemplaire s'écarte.

Trois choix, chacun payé par une erreur réelle :

- **il balaie plutôt qu'il ne liste.** Une liste de chemins manque les
  worktrees — et une première version a annoncé « les trois dépôts concordent »
  au moment où les pièges qu'on documentait n'existaient que là. Le balayage est
  **exhaustif** parce qu'un worktree monté hors de `~/ONTBible/` ne compile pas :
  le site dépend du pipeline par un chemin relatif ;
- **la racine ne vote jamais.** Un décompte majoritaire naïf prend racine + un
  dépôt en retard contre deux dépôts à jour, et désigne le contenu périmé comme
  référence. C'est arrivé ;
- **l'octet décide, les titres expliquent.** Les titres seuls laissent passer
  deux exemplaires aux mêmes sections et au texte différent.

Les worktrees figurent au tableau mais ne votent pas : ils partagent le `.git`
de leur arbre principal, donc la même autorité. Le tableau dit ce que **voit**
chaque session ; le vote dit ce que **porte** chaque dépôt.

Enfin, `--aligner-la-racine <DÉPÔT>` écrit la racine depuis un dépôt nommé. La
direction est dans la commande, elle ne se devine plus.

### 25 août 2026 — un type écrit à la main suit un contrat qu'il ne surveille pas

**Le même défaut, le même jour, dans les trois dépôts et dans trois langages.**

Aucun n'a été trouvé en le cherchant. Chacun est apparu parce qu'une session
avait mis un nom sur le précédent — c'est le **motif** qui a voyagé, pas la
recherche. D'où la règle qu'on en tire, et qui n'est pas « faire relire son code
par le voisin » : **nommer un défaut, et pas seulement le corriger.**

- **App / Android** — `PreferencesFichier`, écrit à la main, ne portait pas le
  réglage « Le français reçu ». Il se basculait, l'écran suivait, il
  disparaissait à la fermeture.
- **Site** — quatre mappages lisaient le schéma du pipeline par accès de champ.
  Un champ ajouté en amont passait en silence ; **quatre l'étaient déjà** sans
  que personne le sache, dont l'`intro` d'un livre.
- **App / iOS** — le conteneur `State` refusait de se décoder si une clé de haut
  niveau manquait, et le `try?` avalait l'erreur : tous les surlignages du
  lecteur, perdus sans un mot. **Latent, jamais déclenché** — les trois champs
  sont là depuis le commit initial. Le prochain champ ajouté l'aurait armé, et
  le prochain est la synchronisation de compte.

**Trois gardes, chacune propre à ce que son langage permet :** déstructuration
exhaustive en Rust — `error[E0027]` à la compilation, sans `..` qui rétablirait
le silence ; réflexion sur le constructeur primaire en Kotlin, faute de motif
exhaustif sur les data classes ; initialiseur mémberwise **sans valeurs par
défaut** en Swift, où les défauts ne protégeaient rien et donnaient l'illusion
du contraire — `var preferences: ReadingPreferences = .default` se lit comme une
tolérance, et le décodage synthétisé ne consulte jamais cette valeur.

**Chacune a été éprouvée en cassant exprès ce qu'elle garde** — un champ ajouté
au schéma, un `@Required` posé, une clé retirée du fichier. C'est la seule façon
de savoir qu'on a des gardes et non des intentions. Et une épreuve qui rougit
**seule** en dit plus qu'une suite qui rougit en entier : quatre épreuves vertes
autour d'une rouge bornent le défaut au lieu de le supposer partout.

**Ce qui reste commun aux trois, après les correctifs** : une lecture ratée ne
doit pas devenir une perte. Le fichier qu'on n'a pas su lire est mis de côté —
`lecteur.illisible.json` — avant qu'on reparte à vide. Repartir vide est le bon
comportement ; l'écraser ensuite transformait un incident de lecture en
destruction définitive.

### 25 août 2026 — iOS est en amont, Android en aval

**Ce n'est pas une répartition de charge, c'est le sens du travail**, et il vaut
d'être écrit parce que tout le reste en découle. Les mots de l'auteur :

> « comme je suis un Apple user, je suis majoritairement en train d'examiner
> l'app iOS ; j'ajoute sur iOS et après j'importe les changements sur Android. »

Android **porte**, il ne conçoit pas. Une seule session y suffit, là où iOS en
occupe plusieurs — et le portage à l'identique n'y est pas un cas particulier :
c'est le mode normal de travail du dépôt.

**Ce qui fait du portage un risque permanent, et non une corvée.** Recopier la
justification avec le code est le **bon** geste : c'est ce qui garantit que le
portage reproduit la *décision* et pas seulement l'*effet*. Le défaut naît de ce
que la décision, elle, peut être révisée en amont sans que la copie l'apprenne
— et un commentaire ne casse pas la compilation.

C'est arrivé le jour même. Le filet du Ḥurban était en accentuation, avec un
commentaire qui expliquait pourquoi l'or ne convenait pas. Android l'a recopié
mot pour mot, comme il fallait. iOS a changé d'avis quelques heures plus tard :
la copie est devenue fausse en silence, et sa justification recopiée continuait
de plaider pour ce qu'on venait d'abandonner.

**La parade n'est pas « ne recopiez pas les commentaires »** — ce serait le
mauvais enseignement. C'est : *porter une décision, c'est aussi vérifier qu'elle
tient encore en amont*. Et, côté amont : ce qu'on écrit en commentaire sur iOS
est ce qu'Android héritera sans avoir le contexte de le contester. On écrit donc
pour quelqu'un qui n'était pas là.

### 25 août 2026 — le registre n'est pas une préférence, c'est l'exactitude

Le réglage « Le français reçu » — *Chapitre 7* contre *Parashah 7* — a d'abord
été présenté comme un confort de lecture, et l'auteur a failli le retirer du site
pour cette raison. Il est revenu dessus avec l'argument juste :

> « quand des parashah ne couvrent pas les mêmes chapitres que dans les
> traductions habituelles, là c'est parashah qui est utilisé. »

Quand l'unité recouvre *Bereshit* 7 **et** 8, l'appeler « Chapitre 7 » est
**faux**. Ce n'est pas un chapitre. Le mot juste dépend donc de ce que l'unité
*est*, pas seulement du registre où l'on veut lire — et le sous-titre de
référence le dit déjà, « 7-8 » là où il dirait « 3 ».

**Conséquence : le registre vaut sur les trois liseuses**, site compris. C'est
même sur le site qu'il compte le plus, puisque c'est la porte d'entrée de
quelqu'un qui arrive avec sa Bible et va comparer.

**Un renseignement disponible et inemployé** : le corpus sait lesquelles
coïncident. `reference` porte « 3 » d'un côté, « 7-8 » ou « 9:18-29 » de
l'autre. Aucune des trois liseuses ne s'en sert. Le jour où la question revient
— « pourquoi Chapitre 7 quand ça couvre 7 et 8 ? » —, la réponse est dans les
données, pas à inventer.

### 25 août 2026 — un calcul né dans une vue diverge, et les trois dépôts le montrent

Le libellé d'une unité — « Chapitre 2 » ou « Parashah 2 » — était écrit **dans
une vue**, en variable privée. Le compte, au moment où on l'a regardé :

- **iOS** — présent au sommaire du livre, recopié nulle part, **manquant** au
  sélecteur de renvoi (qui disait encore « Bereshit 2 ») et à la pastille de
  l'écran de lecture ;
- **Android** — **manquant partout**. Le sélecteur disait « Bereshit 6 » quels
  que soient les réglages ;
- **site** — présent au sommaire, manquant à la page de lecture et à la page de
  passage, qui affichaient le nom ONT brut. Un lecteur touchait « Chapitre 2 »
  et arrivait sur autre chose.

**Deux liseuses écrites séparément ont produit la même dette au même endroit.**
Ce n'est pas une coïncidence : le calcul est *né* dans une vue, et rien
n'oblige un portage à corriger ce que la source n'a pas encore vu.

Il vit maintenant dans le noyau des trois — `LibelleDUnite` côté iOS et Android,
`nom_d_unite` côté site — et porte cinq formes, parce que l'app en a eu besoin
de cinq : le rang, le rang situé (« Bereshit · Chapitre 6 », pour le seul écran
qui n'a pas d'autre repère), le nom, le pluriel, et « Tout le / Toute la » avec
son genre.

**Deux détails qui piègent le point d'appel, et qui sont la raison d'être du
helper :**

- **le genre voyage avec le mot.** « Tout le chapitre » mais « Toute **la**
  parashah ». Rendre le seul nom laisse l'accord à l'appelant, qui l'oubliera ;
- **le pluriel de *parashah* n'est pas français** : **parashiot**, marque
  hébraïque `-ot`, comme le §2.5 le fixe. « parashahs » franciserait un
  intraduisible — l'inverse exact de ce que le réglage cherche à faire. C'est
  le genre de détail qu'un appelant pressé règle avec un `+ "s"`.

**Et « unité » n'est ni l'un ni l'autre des deux registres** : c'est le mot du
pipeline. Juste, mais interne — et il donnait un **troisième** nom à la chose,
en face du lecteur, à quatre endroits de l'app iOS. Il ne reste que dans les
lignes de journal, où il est le bon.

### 25 août 2026 — un outil qui déclare un système cassé peut s'être trompé de geste

Un modèle de langage interrogé sur `ontbible.com` a répondu qu'il n'arrivait pas
à en récupérer le texte : « Le moteur ne l'indexe pas, **et le site ne s'ouvre
pas correctement depuis mon outil** ». La seconde moitié est fausse, et c'est
elle qui envoyait chercher un défaut.

Mesuré avant d'y croire : `robots.txt` autorise tout, chaque page porte
`index, follow`, Googlebot, ChatGPT-User, curl et une requête sans agent
reçoivent tous 200 et **le même octet**, le texte est en clair dans le HTML —
27 302 caractères lisibles — et une récupération directe rend les cinq premiers
versets de *Bereshit*, intégralement.

L'outil avait **cherché**, pas **ouvert**. Il a rapporté l'échec du premier geste
comme une panne du second. La cause réelle n'était pas dans le système : le
domaine était en ligne depuis dix jours sans avoir été soumis à aucun index.

**La règle** : quand un outil déclare qu'une de nos pièces est cassée, mesurer la
pièce elle-même avant de la réparer. Le verdict d'un outil porte sur ce qu'il a
tenté, qui n'est pas toujours ce qu'il croit avoir tenté.

C'est la sœur d'une règle déjà écrite ici — **suspecter la mesure avant la
donnée** — et l'inverse du piège de `apercu.py` au §7 bis du site, où c'était
l'instrument qui montrait un défaut inexistant. Ici l'instrument annonçait la
panne au lieu de la montrer ; dans les deux cas, ce qu'on allait corriger était
intact.

#### La parade, et elle coûte une ligne

**Un instrument se valide sur un cas dont on connaît la réponse, jamais sur
celui qu'on étudie.**

Elle vient de la session Android, le même jour, sur trois instruments qui lui
ont menti coup sur coup : `git grep -E '\bmotif\b'` rendant **0** au lieu de 2
— `\b` n'existe pas en ERE POSIX, le moteur ne l'applique pas *et ne signale
rien* ; le `grep` de cette machine qui n'est pas GNU mais **`ugrep`**, muet sur
un motif finissant par une parenthèse ; `gradlew test` annonçant « BUILD
SUCCESSFUL in 739ms » **sans exécuter un seul test**, servi par son cache.

Le motif commun avec le verdict de ChatGPT est plus profond que la coïncidence :
**le format de sortie survit à l'absence de mesure.** Un `0` bien aligné, un
« BUILD SUCCESSFUL », un « je ne peux pas ouvrir le site » — les trois ont
l'apparence d'un résultat, et rien dans leur forme ne dit qu'il n'y en a pas eu.

C'est ce qui rend la relecture inopérante : un zéro ne donne **aucun
appariement à regarder**, donc relire les lignes ne peut rien attraper là où il
n'y a rien à lire. Seul un témoin dont on connaît d'avance la réponse distingue
« rien trouvé » de « rien cherché ».

#### Et elle innocente aussi souvent qu'elle accuse

La forme séduisante de cette leçon est « les outils mentent ». Elle est fausse,
et il faut l'écrire ici parce qu'elle se retient mieux que la vraie.

Le jour même, `concorder-la-synchronisation.py` a annoncé le site à 709 lignes
quand son disque en portait 763. L'écart était réel, l'accusation était prête —
et l'instrument avait raison : sa colonne d'empreinte donne ce qui **fait foi**,
c'est-à-dire l'état publié, et il signalait `disque ≠ origin/main` sur la même
ligne. L'entrée manquante vivait sur une branche, donc n'était pas publiée, donc
était à bon droit hors du compte.

La règle a mordu **dans l'autre sens** : on a validé l'instrument sur un cas dont
on connaissait la réponse, et c'est la lecture qui a cédé. Un instrument juste
qu'on n'a pas lu jusqu'au bout se présente exactement comme un instrument
fautif — et le réécrire aurait cassé la garde qui protège ce fichier-ci.

Ce qu'on éprouve n'est donc pas la sincérité de l'outil, c'est **l'appariement
entre ce qu'il mesure et ce qu'on lui demande**. Il tombe des deux côtés.

Ce que le site en a tiré : `/llms.txt`, qui pose le cadre de lecture ONT à la
racine plutôt que dans une page qu'il faut avoir trouvée. Il n'indexe rien — les
soumissions à Bing et Google restent le seul geste qui fasse entrer un site dans
un index, et elles appartiennent à Gloire.

### 25 août 2026 — trois compteurs au vert, et une forme mal rangée dessous

**Source : le vault**, en soldant le §13 de son `CLAUDE.md`. Rien à porter dans
le pipeline ni dans le site — mais il faut reconstruire le corpus, et ce qui
suit vaut pour les trois dépôts.

**Ce que le vault a décidé.** Les sept termes que le pipeline signalait balisés
sans entrée de glossaire sont réglés, et deux décisions dépassent le balisage :
**shiphchah** devient intraduisible, et surtout la famille **chata** passe
entière en hébreu — **chata** est le ==premier verbe intraduisible de l'ONT==,
tous les verbes du §3.1 étaient traduits jusqu'ici. Le §2.3 reçoit par ailleurs
l'argument d'exactitude sur le registre : « Chapitre 7 » pour une unité qui
couvre *Bereshit* 7 et 8 est un intitulé faux, pas une commodité.

#### Un compteur à zéro est un zéro, et il faut savoir ce qu'il comptait

C'est ce que la journée ajoute à ce qu'elle avait déjà écrit.

En déclarant un construit au §2.5, la puce de **tsedaqah** citait
`**yirat YHWH**` comme exemple — **entre accents graves**. Or c'est exactement
ce que le pipeline lit comme une *déclaration de forme*. `yirat YHWH` s'est
donc retrouvé rattaché à **tsedaqah** au lieu de **yirah**.

Le rapport de construction n'a rien dit. **Zéro terme inconnu, zéro marqueur
déséquilibré, zéro mot d'or sans fiche** — les trois compteurs au vert, et une
forme rangée sous le mauvais lemme. Un lecteur touchant le mot serait tombé sur
la mauvaise fiche, sans qu'aucun contrôle ne s'en aperçoive.

La cause n'est pas un contrôle défaillant : les trois vérifiaient exactement ce
qu'ils annoncent — que tout terme balisé **a** une fiche. Aucun ne vérifiait
qu'il a **la bonne**. Trouvé en ouvrant `dist/glossary.json` et en lisant les
formes une par une, pas en lisant le rapport.

**D'où la règle, qui prolonge celle du verdict qui se mesure :** un compteur à
zéro ne dit pas que tout va bien, il dit que *ce qu'il comptait* est à zéro. Ce
qu'il ne compte pas reste invisible, et l'aplomb du rapport ne distingue pas les
deux. ==Lire la sortie construite, pas seulement le rapport qui la résume.==

**Et ce n'est pas le même défaut que le « BUILD SUCCESSFUL » de l'entrée
précédente — c'est un cran plus bas.** Là, la sortie survivait à une mesure qui
n'avait pas eu lieu : il n'y avait rien derrière. Ici la mesure a bien eu lieu,
les compteurs ont réellement compté, et ==le zéro était vrai==. C'est la
*question* qui était à côté.

La différence est pratique, pas philosophique : le premier cas se répare en
**ajoutant une mesure**, le second ne se répare qu'en **changeant la question**.
Aucune insistance sur la rigueur n'y mène — il fallait ouvrir la sortie et lire
les formes une par une, c'est-à-dire faire à la main ce que le contrôle existe
pour éviter.

**La cause profonde a un nom, et elle ressortira ailleurs :** ==un langage qui
n'a pas de citation ne peut pas distinguer *montrer* de *dire*.== Le §2.5 déclare
ses formes entre accents graves ; il n'a donc aucun moyen d'écrire « voici à quoi
ressemble une déclaration » sans écrire « ceci en est une ». Ce n'était pas une
maladresse de rédaction mais une propriété du format, et tout document qui se
lit lui-même comme configuration porte le même défaut.

#### Le même motif, une fois de plus, sur le relevé qui ouvrait le chantier

Le §13 annonçait « vingt-deux marqueurs déséquilibrés » dans les pieds de
*Bereshit* 15 à 19. Le compte était relevé **par ligne** — or un `**…**` enjambe
légitimement un retour à la ligne, et un gras ouvert en fin de ligne, fermé au
début de la suivante, produit deux lignes « impaires » sans le moindre défaut.

Mesuré **par paragraphe**, l'unité réelle du balisage : ==deux==, non
vingt-deux. Les deux étaient réels et sont corrigés. Le balayage a ensuite été
repassé sur tout le corpus, non sur les seuls chapitres que le §13 regardait :
zéro.

C'est le quatrième exemplaire du même motif en un jour, et il n'a rien de neuf
sinon sa banalité : un nombre bien formé, aligné, crédible, qui mesurait autre
chose que la question posée.

#### Le contrôle de concordance n'élit plus de référence

`concorder-la-synchronisation.py` retenait le contenu **majoritaire** parmi les
dépôts. Juste contre une racine périmée, faux pendant une **fenêtre de
propagation** : le dépôt qui vient de recevoir une entrée est minoritaire, donc
la majorité est l'ancienne version. Il désignait le retard comme référence et
proposait d'y figer la racine.

Le refus d'aligner était déjà en place ; c'est le **verdict au-dessus** qui
manquait, et une note sous un verdict est ce qu'on lit le moins. Quand les
dépôts divergent, il n'existe pas de référence — le contrôle dit maintenant qui
porte quoi, et rien d'autre.

Éprouvé sur un état divergent **construit exprès**, jamais sur l'état du moment.
C'est précisément ce qui n'avait jamais été fait, et pourquoi le défaut a
attendu d'être rencontré pour se voir.

**Ce que les trois dépôts doivent en retenir :** reconstruire le corpus après
toute décision de balisage, et **lire la sortie**, pas seulement le résumé.

### 26 août 2026 — la zone qui répond au doigt n'est pas le mot qu'on voit

Un lecteur signalait devoir **viser** pour ouvrir la fiche d'un intraduisible :
souvent, disait-il, seule la première lettre répondait. La composition était la
suspecte évidente — et elle est innocente. Une épreuve qui relève, caractère par
caractère, ce que porte la chaîne composée le montre : les six lettres
d'« Elohim » portent bien le lien de leur fiche, le lien du verset ne déborde
d'aucun caractère, et il n'y a pas de zone morte.

**Ce que le doigt touche n'est pas ce que la chaîne porte.** La plage est une
propriété du texte ; la zone tactile est une propriété de la **mise en page**,
calculée après composition des lignes. Les deux ne coïncident pas, et aucune
épreuve portant sur les caractères ne peut voir la seconde.

Mesuré sur *Bereshit* 1 en prose continue, réglages par défaut (corps 19,
interligne 0,5) :

    encre du mot                    15,3 pt de haut
    bande qui répond au doigt       30 à 36 pt
    minimum recommandé (HIG)        44 pt

La bande est celle de la **ligne**, donc elle suit les réglages du lecteur —
42 pt à interligne maximal, 48 pt à corps 28. Les deux curseurs déjà offerts
l'épaississent, aucun réglage raisonnable n'atteint 44.

**La cible rétrécit avec le corps du texte**, et linéairement — mesuré sur un
mot entouré de texte des deux côtés, interligne au défaut :

    corps   encre    bande qui répond
      11    8,3 pt      18 pt
      15   10,3 pt      24 pt
      19   12,7 pt      30 pt      ← le défaut
      24   19,0 pt      42 pt
      28   21,7 pt      48 pt

Le rapport tient autour de 1,7 fois le corps. **Seuls les deux plus grands
réglages approchent les 44 pt de la HIG** ; le réglage par défaut en offre 30,
et le plus petit 18 — moins de la moitié.

Conséquence qui oriente le correctif : le défaut n'est pas le même pour tous
les lecteurs. Il s'aggrave pour qui lit petit et s'efface pour qui lit grand.
Ce n'est donc pas quelques points à gagner partout, c'est un **plancher** à
poser — que la zone ne descende jamais sous un seuil, quel que soit le corps
choisi.


**Ce qui rend le défaut sensible tient à la prose.** En lecture continue, le
verset entier porte lui aussi un lien. Manquer la bande du mot ne fait donc pas
« rien » : ça **désigne le verset**, des deux côtés. Le lecteur ne voit pas un
raté, il voit un autre événement — une carte qu'il doit refermer — et il en
conclut qu'il a mal visé. C'est le presque-raté qu'il faudrait rattraper, non la
bande qu'il faudrait agrandir : chaque point autour du mot appartient déjà au
verset, et le lui prendre demande un arbitrage.

Le constat vaut sur les deux liseuses. Android mesure 35 à 42 dp pour 48 exigés
par Material, par balayage d'appuis sur un Pixel. Même grandeur, même écart,
deux mécanismes indépendants — et une exemption commune : les cibles en ligne
dans une phrase échappent à la règle de taille minimale, précisément parce qu'on
ne peut pas les agrandir sans aérer le texte d'un tiers.

Travail rangé sans correctif : le relevé et son instrument sont acquis.

### 26 août 2026 — trois manières pour un instrument de rendre un relevé faux

La journée en avait donné le motif — *le format de sortie survit à l'absence de
mesure*. L'enquête ci-dessus l'a fait rendre trois fois, sous trois formes
distinctes, et c'est la distinction qui est utile.

> **Il y en a six.** Trois autres ont été trouvées le 27 août, pendant le
> rattrapage d'Android sur iOS, et sont consignées dans cette entrée-là —
> « Trois manières de plus pour un instrument de rendre un relevé faux ». Elles
> y sont bien rangées, puisqu'elles appartiennent à ce récit ; le renvoi est
> ici parce que c'est ici qu'on vient chercher le sujet.
>
> Sans lui, on lit « trois manières », on referme, et on croit avoir fait le
> tour. C'est le lecteur **confiant** qui se trompe, pas le distrait — la même
> forme que le journal qui régresse, où l'on croit lire l'état de la
> connaissance et où l'on lit celui d'avant.

**Un instrument non reproductible.** Le premier balayage refermait la fiche par
un glissement vers le bas entre deux appuis — geste qui fait aussi **défiler la
page**. Chaque appui suivant visait le mot là où il n'était plus. Le relevé
sortait aligné, croissant, vraisemblable. Deux exécutions de la même
configuration ont rendu 27 pt puis 36 pt, et c'est **la répétition seule** qui
l'a montré : relire le code ne l'aurait pas donné.

**Un détecteur qui ne détecte pas.** Le relevé cherchait la fiche par le mot
« occurrence », que toutes les fiches n'affichent pas. Il a rendu « rien » sur
toute la bande — un faux négatif ayant exactement la forme d'un résultat. Le
marqueur est maintenant le bouton « Fermer » de la barre, présent quel que soit
le terme.

**Un cas particulier pris pour le cas général.** La mesure portait sur le
**premier** mot doré de la page, donc posé sous un titre. L'espace vide relevé
au-dessus de lui était ce titre. On en avait tiré qu'il y avait de la place
libre à ramasser, et donc un correctif sans arbitrage : il n'existe pas. Sur un
mot entouré de texte des deux côtés, le relevé est symétrique.

Les trois parades ne sont pas la même. La première demande de **refaire la
mesure** ; la seconde, de **valider le détecteur sur un cas dont on connaît la
réponse** ; la troisième, de **choisir le cas mesuré plutôt que de prendre le
premier venu** — le premier élément d'une liste est presque toujours en bordure
de quelque chose.

### 26 août 2026 — `main` se déployait sans qu'aucun contrôle soit exigé

Les cinq rulesets du projet portaient `pull_request`, `required_signatures`,
`deletion` et `non_fast_forward` — mais **aucun n'exigeait que la CI ait
répondu**. Une PR pouvait donc être fusionnée le contrôle rouge, et `main` se
déploie seule en production.

Ce n'était pas théorique. Une session a armé la fusion automatique d'une PR du
site avant que `Éprouver` ne rende son verdict ; il a échoué ; le défaut est
parti en ligne. Avec un `MERGED` parfaitement bien formé sur une PR au contrôle
rouge.

C'est le motif de la journée sous sa forme la plus coûteuse, et sous une
**troisième variante**. Ailleurs, l'instrument mesurait autre chose que la
question posée ; ici, le `MERGED` ne mentait pas — il rapportait fidèlement une
fusion qui avait bien eu lieu. Ce qu'il ne disait pas, parce que rien ne le lui
demandait, c'est qu'**aucun contrôle n'y était exigé**. Un verdict exact sur une
question qu'on n'avait pas posée. Ailleurs ça coûte des heures ; ici ça met un
défaut devant des lecteurs.

État vérifié depuis l'API après correction — les cinq portent désormais un
contrôle exigé, et les quatre autres règles sont intactes :

    site/main            eprouver
    vault/main           eprouver
    app/main             tests, Chaîne de promotion
    app/dev              tests
    app/staging          tests, Chaîne de promotion

**« Tous les dépôts portent le même ruleset » cesse d'être littéral ici**, et
c'est la nuance à retenir : le *contexte* exigé est le **nom réel du job** de
chaque dépôt — `eprouver` chez le site et le vault, `tests` chez l'app. Un nom
deviné n'aurait pas protégé : il aurait bloqué **toutes** les PR, en attendant
un contrôle qui ne vient jamais. La règle est la même partout ; son paramètre ne
peut pas l'être.

`strict_required_status_checks_policy` reste à **`false`** partout, et
délibérément. À `true`, chaque fusion périme toutes les autres PR, qui doivent
rebaser avant de pouvoir passer : à cinq sessions, c'est une file d'attente
permanente. C'est la contradiction exacte qui a bloqué `dev → staging` la
veille — `dev` n'autorisant que le squash pendant que `staging` exigeait
`strict`, la fusion devenait structurellement impossible, pas seulement
difficile.

### 26 août 2026 — le rattrapage d'Android sur iOS, et ce qu'il a appris

Vingt-quatre commits pour ramener la liseuse Android au niveau de l'iOS. Ce
qu'il faut en retenir tient en trois points, et aucun n'est propre à Android.

**Un portage ne se vérifie pas fichier par fichier.** Le premier audit
comparait des **noms de fichiers** entre deux arbres — et les deux n'étaient pas
sur la même branche : l'écran d'ouverture n'existait pas sur celle qu'on
interrogeait. Il n'aurait de toute façon rien vu de l'essentiel : l'accentuation
peinte puis repeinte, l'hébreu absent du sous-titre, le filet du Ḥurban rendu en
gris. **Les fichiers existaient des deux côtés ; seuls leurs rendus
divergeaient.** Un audit utile compare ce qui s'affiche, pas ce qui s'appelle.

**Une même donnée peut plaire à une plateforme et tuer l'autre.**
`SearchHit.id` vaut `unité-verset-niveau` et n'est pas unique. SwiftUI tolère
les identifiants doublés — il avertit, et réutilise parfois la mauvaise vue.
Compose lève : chercher « alliance » fermait l'app. Même domaine, même donnée,
même requête ; une plateforme plante là où l'autre murmure. **Un défaut
silencieux d'un côté n'est pas un défaut absent** — Android ne l'a pas
introduit, il l'a révélé. Le portage est donc un instrument de mesure sur
l'amont, et pas seulement du travail en aval.

**Ce que la plateforme donne gratuitement à l'une, l'autre doit l'écrire.** Le
même réglage d'interligne rendait 1,735 sur iOS et 1,500 sur Android :
`SwiftUI.lineSpacing` **ajoute** des points à l'interligne de la fonte, Compose
`lineHeight` **fixe** la hauteur et l'efface. Les deux courbes se croisent. De
même, une rotation ne reconstruit pas la vue racine d'iOS mais recrée l'activité
Android — l'ouverture y rejouait cinq secondes et demie à chaque quart de tour.
**Porter du code, c'est porter ce que le code ne dit pas.**

**Ce que ce travail change pour les voisins.**

Pour le **site** : `/{langue}/lire/{livre}/{unité}?v=…` n'est plus une route de
page, c'est un **contrat que deux apps lisent**. Le changer sans prévenir casse
les liens partagés sur les deux plateformes. Et l'App Link Android exige
`/.well-known/assetlinks.json` servi sans redirection — posé côté site, avec
l'empreinte de la clé de téléversement. Une seconde empreinte s'y **ajoutera**
après le premier envoi à Play, celle avec laquelle Google resigne : la
remplacer ferait cesser d'être reconnues toutes les installations de test.

Pour le **vault** : rien à corriger. Les astérisques des décisions
terminologiques viennent de l'analyseur du pipeline, qui ne sait pas ouvrir une
emphase juste avant un gras — `***Elohim** / …*` est du Markdown valide. Le
mot d'or s'appelle alors littéralement `*Elohim`, vingt-six fois dans
*bereshit*. Le lien de la fiche reste juste ; seul l'affichage est faux.

**Et une règle nouvelle, posée par Gloire ce jour :** les initiatives viennent
d'iOS, Android applique. Quand le portage révèle un arbitrage plutôt qu'un
rattrapage, il remonte à iOS — jusque dans le vocabulaire des libellés, où
inventer une meilleure formulation reviendrait à créer un second dialecte pour
la même idée.

#### Trois manières de plus pour un instrument de rendre un relevé faux

L'entrée « trois manières pour un instrument de rendre un relevé faux », plus
haut, en compte trois. La journée en a produit deux autres, et elles ne se
recouvrent avec aucune des précédentes.

**La quatrième porte sur la cadence.** Une sonde par capture d'écran a mesuré
douze à vingt secondes pour une animation d'ouverture qui dure 5,515. L'horloge
d'échantillonnage était plus lente que le phénomène échantillonné. Ce qui la
rend redoutable, c'est que le résultat avait *la forme d'un blocage* : une suite
de « toujours l'ouverture » ressemble trait pour trait à une ouverture qui ne
finit pas. L'instrument mesurait la bonne chose, correctement, et trop lentement
pour qu'elle existe — aucune relecture de la sonde ne l'aurait montré. Il a
fallu une seconde mesure d'une autre nature, un journal horodaté.

**La cinquième porte sur le chemin entre le rapport et la décision.** Un script
de résolution de conflit a émis un `AssertionError` parfaitement exact, et un
`git commit` a suivi dans la même commande, parce qu'il était après un `&&` sur
une *autre* commande. Des marqueurs `<<<<<<<` sont partis dans le journal, et le
build a rendu `BUILD SUCCESSFUL` par-dessus — un Markdown avec des marqueurs de
conflit compile parfaitement.

C'est la seule des cinq où aucune amélioration de l'instrument n'aurait aidé :
il avait raison, et il parlait dans le vide. **Le contrôle porte sur le fichier,
jamais sur le rapport de l'outil qui vient de le toucher.**

Et le lendemain de cette erreur, la même heure en a produit le versant
symétrique : accuser l'outil de concordance d'avoir écrit dans un arbre de
travail, alors que sa seule écriture vise le dossier parent et qu'elle est
doublement gardée. La ligne venait d'une session, qui l'avait déposée dans tous
les exemplaires sans prévenir. Le raisonnement était cohérent et faux, et agir
dessus aurait fait tomber une garde ajoutée la veille.

Il est plus facile de soupçonner l'outil qui balaie que la session qui écrit :
l'un est visible dans les commandes qu'on tape, l'autre non. **Ce qu'on éprouve
n'est jamais la sincérité de l'outil, c'est l'appariement entre ce qu'il mesure
et ce qu'on lui demande — et il tombe des deux côtés.**

**La sixième porte sur le témoin lui-même**, et c'est la seule où le protocole
était bien construit.

Vérification du suivi de lecture sur l'APK de production : « avant défilement,
aucun fichier » — juste, la garde tenait. Puis « après défilement, aucun
fichier » — et la conclusion, fausse : R8 aurait emporté quelque chose.

En réalité **`run-as` refuse tout paquet non débogable**. Il rendait vide dans
les deux cas, quel que soit l'état de l'app. Le témoin avait été lu, il avait
répondu juste — mais un témoin qui attend « rien » ne peut pas distinguer un
instrument muet d'un instrument correct. **Un contrôle négatif ne contrôle rien
quand la panne produit un négatif.**

Ce qui en sort de pratique : un témoin doit attendre quelque chose de
**positif**. Lire un fichier dont on sait qu'il existe avant de conclure d'un
fichier absent. Et quand un doute subsiste, mesurer par un instrument qui ne
partage pas le mode de panne du premier — ici l'interface, qui ne passe pas par
`run-as`, et qui a rendu « Reprendre — Bereshit 1:13 ».

#### Ce que le glissement a appris sur le portage d'une sensation

iOS accroche ses trois retours haptiques à des **états** — `trigger: courant.id`
pour celui du milieu, celui qui dit que l'unité a changé pour de bon. Android
appelle `aller()`, qui lance une coroutine et rend la main avant que l'unité
soit là. Porter le retour sur l'appel plutôt que sur l'état l'aurait fait vibrer
avant l'événement, et aussi quand rien n'arrive.

La leçon dépasse l'haptique : **ce qui se porte d'une plateforme à l'autre, ce
n'est pas le geste d'iOS, c'est ce qu'il observe.** Un port qui recopie l'appel
au lieu de l'état a l'air fidèle et ne l'est pas.

Une divergence a été remontée à iOS comme la règle l'exige : Android vibrait à
l'ouverture et à la fermeture de la barre de sélection, iOS non. **iOS a tranché
en s'alignant** — `.sensoryFeedback(.selection, trigger: selection.isEmpty)`.

Le motif de la décision vaut d'être gardé, parce qu'il montre à quoi sert la
règle. iOS n'a pas ratifié une liberté prise par Android : il a constaté qu'il
lui manquait quelque chose, et c'est le relevé d'Android qui le lui a montré. On
désigne un verset en regardant le texte, pas la barre qui monte du bas de
l'écran — sans retour tactile, le seul signe que le mode a changé est hors du
regard. Et l'argument redouble ici, où le corps est réglé grand : la barre sort
d'autant plus du champ.

Le déclencheur est `selection.isEmpty` et non `selection` : la frontière du
mode, pas le décompte. Sur `selection`, il vibrerait à chaque doigt posé.

**La règle n'empêche donc pas Android de trouver — elle l'empêche de décider.**
C'est une distinction utile : un portage regarde deux fois le même produit, et
le second regard voit ce que le premier avait laissé passer.

#### Le suivi de lecture, qui n'existait pas sur Android

Le second regard a servi une deuxième fois, et sur plus gros. iOS porte un
`SuiviDeLecture` : il retient le verset le plus haut visible **quand le
défilement s'arrête**, et seulement si le lecteur a fait défiler quelque chose.

Android ne retenait la position qu'au **toucher** d'un verset — c'est-à-dire en
le sélectionnant. Qui lisait en faisant défiler, sans jamais rien désigner, ne
déplaçait jamais sa reprise : la carte « Reprendre » pointait le dernier verset
touché, parfois d'une tout autre séance. Le défaut ne se voit pas en lisant le
code, parce que la position *existait* et *se sauvegardait* ; c'est son
déclencheur qui était faux. Il ne s'est vu qu'en comparant les deux écrans de
lecture ligne à ligne.

Un premier correctif retenait le premier verset du **bloc** en tête d'écran,
puisque le bloc est l'élément de liste, et l'inscrivait ici comme une différence
assumée avec iOS. **C'était une erreur, et iOS l'a signalée.**

Le suivi au bloc *est* le défaut qu'iOS avait déjà réparé : en prose continue un
bloc est une section entière dans un seul `Text`, et « Reprendre » ramenait au
début de la section au lieu de l'endroit qu'on lisait. Tant que les blocs
valaient un verset, ça ne se voyait pas ; la fusion l'a révélé.

La leçon vaut au-delà du cas : **inscrire un écart comme une décision le referme
pour des années.** Quelqu'un le relira comme un choix motivé et ne le rouvrira
pas. Un écart qu'on n'a pas encore comblé s'écrit comme un écart.

Il est comblé. Le suivi est au verset des deux côtés — et Android le fait avec
plus d'exactitude qu'iOS, non par mérite mais par ce que la plateforme donne :
iOS estime la part de hauteur de chaque verset au prorata des signes affichés,
faute de pouvoir demander sa mise en page au moteur de texte ; Compose la rend
dans `TextLayoutResult`, et on lit donc les bornes réelles.

La garde d'ouverture est reproduite telle quelle : ouvrir une unité, la lire
sans bouger et la quitter ne déplace pas la reprise. C'est ce qui permet à une
restauration de survivre à une visite.

Deux pièges de plateforme, trouvés en mesurant et non en relisant :

`boundsInRoot()` **rogne** aux limites visibles. Un bloc à moitié sorti par le
haut se déclarait donc au bord de la fenêtre, tous ses versets paraissaient
visibles, et le plus petit numéro gagnait — c'est-à-dire celui qu'on venait de
quitter. C'est `positionInRoot()` qu'il faut.

La sortie du champ n'est pas un événement, c'est une **absence** d'événements :
`onGloballyPositioned` cesse simplement de parler. Les bornes se figeaient donc
dans la fenêtre et le verset 1 gagnait pour toujours. iOS n'a pas ce problème,
sa sonde signale l'entrée *et* la sortie. Ici il faut prendre la sortie là où
elle se manifeste — la mise au rebut du composable.

**Un écart reste ouvert, et il est écrit comme tel.** Android calcule où finit le
numéro de verset dans le texte réuni pour savoir où commencer le pointillé ; iOS
monte le numéro dans un `Text` séparé, si bien qu'il n'y a aucun offset à
calculer. Les deux marchent, mais seule la seconde ne *peut pas* se tromper —
et c'est justement un offset mal calculé qui a fait démarrer le pointillé dix
signes trop loin pendant des semaines.

iOS n'avait pas séparé le numéro pour cette raison : c'était le décroché du
pointillé sous l'exposant, et la robustesse est venue en prime. C'est le sens
habituel de ces choses. **Un défaut qu'on rend impossible vaut mieux qu'un défaut
qu'on calcule bien**, et le jour où la composition d'Android sera rouverte, c'est
la forme à viser.

Éprouvé sur l'appareil, pas seulement compilé : aucun `lecteur.json` après
l'ouverture, puis `Bereshit 1:9` après quatre défilements, et la carte
« Reprendre » qui l'affiche.

### 30 août 2026 — la troisième couche du texte, et ce qu'un type fait qu'un lien ne fait pas

Les noms propres — les **Shemot** — ont leur couche. `[[Nom]]` dans le vault
devient `Inline::Shem { v, lemma }` dans le pipeline, et paraît en terre brûlée,
touchable, avec sa fiche.

#### Ce que le choix du type a évité

La marque est le lien natif d'Obsidian, que `inline.rs` lisait déjà. On aurait
donc pu émettre un `Link` et laisser chaque liseuse reconnaître un Shem à ce que
son `href` n'a « ni schéma ni barre oblique ».

Le site a mesuré ce que ça donnait chez lui avant qu'on décide, au lieu de le
déduire : il classe extérieur tout `href` qui ne commence pas par son adresse.
Chaque Shem y serait devenu un lien souligné, `noopener`, ouvrant un onglet neuf
vers une page inexistante. **Pas un lien mort — un lien mort qui arrache le
lecteur de sa page.**

Et sa formulation vaut mieux que la mesure : *une règle qui distingue « une
chaîne sans schéma » d'une URL casse au premier cas particulier.* Il y en a
déjà — l'apostrophe de `Na'amah`, le composé de `Tuval-Qayin` — et trois
liseuses auraient refait le même arbitrage, chacune se trompant séparément.

**Un type déplace la décision là où l'information existe.** Le pipeline sait
qu'il a lu `[[…]]` ; aucune liseuse n'a à le redéduire d'une forme de chaîne.

#### L'asymétrie qui n'existe plus, et une mémoire qui l'ignorait

J'ai affirmé que le changement casserait iOS et Android — engendrés — en
laissant le site se taire, puisqu'il écrit son domaine à la main.

**C'était vrai jusqu'à fin août et ça ne l'est plus.** Le site dépend de
`ont-pipeline` comme d'une caisse, son `match` porte neuf bras sans `_ =>`, et
une variante nouvelle y produit un `error[E0004]`. Trois chemins, un contrat,
trois refus de compiler.

Je le récitais depuis une note de projet écrite le 25 août, sans aller vérifier —
alors que le `grep` qui m'aurait détrompé prend cinq secondes, et que je l'avais
fait : j'avais vu `pipeline::Inline::Link` dans son code et lu « il redéfinit les
formes » au lieu de « il importe les tiennes ».

**Une forme de plus : un relevé juste, conservé, et devenu faux sans que rien ne
le signale.** Proche des deux référentiels divergents, mais décalée dans le
*temps* plutôt que dans l'espace. Une mémoire ne se périme pas bruyamment ; elle
attend qu'on la récite.

#### Ce que le compilateur ne garde pas

Le site tient une garde qui refuse tout `href` relatif dans le corpus. Elle
n'attrape pas ce que les compilateurs attrapent — elle attrape ce qu'ils ne
peuvent pas voir.

**Les formes, jamais les contenus.** Un Shem émis en `Link` avec un `href`
relatif est un `Link` parfaitement valide : le type juste, la valeur fausse. Le
type `shem` transforme précisément cette valeur vérifiée à l'exécution en forme
vérifiée à la compilation — trois compilateurs au lieu d'une garde, et la garde
reste pour tout le reste.

#### Deux contrôles qui manquaient, et le second n'était pas cherché

Un Shem sans fiche **ne dégrade pas** : il est émis, et un compteur le nomme.
Le §2.10 veut qu'une fiche dise ce qui reste à venir, et le vault porte des
renvois vers des porteurs pas encore écrits — ce sont des marques de travail, pas
des erreurs. Dégrader en texte nu ferait disparaître la liste de ce qui manque.
Dix aujourd'hui, sur 1 947 Shemot et 205 porteurs.

Le second est venu du vault, qui l'a trouvé **en faisant autre chose**. En
posant l'hébreu dans les fiches, cinq intraduisibles n'avaient rien à prendre au
glossaire : `neshamah`, `emunah`, `tsadiq`, `tsedaqah`, `mabbul` étaient
déclarés au §2.5, balisés partout, affichés en or et touchables — et le §3 ne
disait rien d'eux.

**Trois gardes les avaient laissés passer**, une du site et deux d'ici. Aucune ne
se trompait : toutes vérifiaient que le mot **mène** quelque part, jamais que ce
quelque part **dise** quelque chose. C'est plus facile à écrire, et c'est ce qui
reste faux.

#### Les titres de section n'ont demandé aucun code

Le vault et le site les croyaient jetés par `read_fiches`, sur la foi d'un filtre
qui n'existe plus. `bloc_de_fiche` les gère, et n'écarte que le niveau 1 — le
titre de la fiche, affiché par ailleurs.

Ils ne paraissaient nulle part parce que **les seules fiches qui en portent sont
celles des Shemot**, précisément celles qui n'étaient pas publiées : 197 sur 305,
contre zéro des 108 fiches d'intraduisibles. Publier les unes fait apparaître les
autres — 620 titres pour 1 498 paragraphes.

Ce qui l'a montré : avoir mesuré la **sortie** au lieu de relire le code.

#### Et le lien de partage qui manquait à Android

Un passage partagé depuis Android arrivait chez le destinataire sans aucun moyen
de l'ouvrir. iOS en pose un depuis toujours.

**Je l'ai d'abord nié**, `grep ontbible.com` rendant zéro sur ses chemins de
partage. L'URL est construite, et le domaine ne s'écrit que dans `project.yml` —
pour qu'un changement de domaine ne demande pas de toucher au code. Chercher une
chaîne littérale ne pouvait pas la trouver, et j'ai pris l'absence d'une chaîne
pour l'absence d'une chose. L'erreur s'est propagée : j'ai fait douter iOS d'une
fonctionnalité qu'elle avait.

Un écart minuscule est tombé en le posant : `VerseRange.label` joint avec « , »,
espace comprise, et iOS passe cette chaîne à `URLQueryItem`, qui la
percent-encode. Son lien émet `?v=1-3,%207` là où le site produit `?v=1-3,7`.
Les deux parsent — mesuré en production — mais ce sont deux chaînes pour un même
passage, donc deux entrées de cache et deux aperçus.

### 28 août 2026 — la liseuse Android sur un vrai téléphone, et ce qu'il a montré

Un Galaxy S20+ sous Android 13, branché pour la première fois. Trois défauts
sont tombés en une heure qu'aucun émulateur n'avait signalés en deux jours.

#### Le glissement mangeait le défilement

« Je n'arrive plus à scroller, tous les mouvements sont attrapés par le swipe. »

`horizontalDrag` de Compose ne guette **aucun seuil**. Appelé juste après
`awaitFirstDown`, il happe le premier mouvement venu, quelle qu'en soit la
direction — et comme la suite le consomme, un doigt qui montait pour lire était
pris par le glissement de parashah.

Ce que le portage avait laissé passer : **SwiftUI arbitre seul entre deux gestes
concurrents.** `.simultaneousGesture` laisse le défilement et le glissement se
disputer le doigt, et le système tranche. Compose ne fait rien de tel.

C'est la même leçon que le suivi de lecture, sous une autre forme : ce qui se
porte d'une plateforme à l'autre n'est pas le geste, c'est **ce dont il dépend**.
iOS dépendait ici d'un arbitrage que le système lui rendait gratuitement, et qui
n'existe pas en face. Un port qui recopie le geste sans le voir a l'air fidèle
et ne l'est pas.

#### Le défilement à 61 ms par image, et trois hypothèses fausses

Mesuré à `dumpsys gfxinfo` : **85 % d'images en retard, 61 ms par image**, pour
16 ms de budget à 60 Hz.

J'ai soupçonné le suivi de lecture, qui écrit un état à chaque image — débranché,
c'était pire. Puis `LineBreak.Paragraph`, la stratégie de haute qualité d'Android
sur des sections immenses — aucun écart. Deux intuitions raisonnables et fausses,
qui auraient chacune coûté un correctif inutile.

Ce qui a tranché : `framestats`, qui horodate chaque étape d'une image. Mesure et
placement **0,1 ms**, GPU 8 ms, **enregistrement des commandes de dessin 23 ms**.
Tout était là, et aucune des trois intuitions ne l'aurait montré.

La cause : le pointillé de sélection lisait la mise en page **dans la phase de
dessin**, s'y abonnait, et `onTextLayout` la réécrivait à chaque passe. Chaque
image, le dessin s'invalidait et réenregistrait les glyphes d'un texte haut de
plusieurs écrans — **même sans aucune sélection**, où il n'avait rien à dessiner.

Trois corrections, chacune mesurée : le texte mémorisé au lieu d'être rebâti à
chaque recomposition, le modificateur recevant des valeurs plutôt que des
lambdas, et le pointillé posé sur un `Canvas` **frère** du texte, avec son propre
nœud de dessin. 61 ms → 16 ms.

#### Une neuvième forme : le relevé optimiste sans qu'on le sache

Les six premières portent sur un instrument qui se trompe, se tait, ou détruit ce
qu'il mesure. La septième porte sur deux référentiels divergents, la huitième sur
des mesures qui s'accumulent. Celle-ci est d'un genre de plus.

Après le correctif du geste, le même protocole a rendu **754 images là où il en
rendait 320**, et 10 ms au lieu de 16. Rétrospectivement, mes mesures de
fluidité étaient prises sur un défilement **à moitié volé** : plus de la moitié
du mouvement partait au glissement, et ce que j'appelais « le défilement » était
en partie l'animation du feuillet.

Le rapport 61 → 16 reste juste, parce que les deux états partageaient le même
défaut. Mais **le nombre absolu ne mesurait pas ce que son nom disait.** Un
instrument juste, un protocole stable, un écart réel — et une grandeur mal
nommée. Il n'y avait aucun moyen de s'en apercevoir avant de corriger autre
chose.

La règle qui en sort : **un chiffre stable et reproductible ne garantit pas qu'on
mesure la chose qu'on nomme.** Quand une correction sans rapport déplace une
mesure qu'elle ne devait pas toucher, ce n'est pas du bruit — c'est que la
mesure portait sur autre chose.

#### La publication sur Play, et deux manières pour un cache de mentir

L'app est en test interne sur le Play Store, installée depuis le Store et
signée par Google. La chaîne complète a été éprouvée bout en bout : un lien
`ontbible.com` ouvre l'app, affiche l'unité, et désigne les versets demandés.

Deux défauts sont tombés en chemin, et aucun n'était dans notre code.

**L'empreinte recopiée depuis la mauvaise source.** La page de signature de la
Play Console affiche désormais **deux** certificats côte à côte — la clé
classique et une clé post-quantique — avec deux boutons au libellé identique.
C'est le second qui a été copié, et la valeur est partie au site.

Rien n'aurait cassé : `assetlinks.json` aurait été servi, bien formé, avec une
empreinte inutile, et les liens auraient continué de partir au navigateur sans
qu'aucun message ne dise pourquoi.

Ce qui l'a rattrapée, c'est d'avoir tiré l'APK du téléphone et recalculé le
condensat — `apksigner --print-certs` sur l'objet réel plutôt que sur ce qu'une
console en dit. **Onzième forme : la source faisait autorité et n'était pas la
mesure.** La console n'a pas menti ; elle affichait deux valeurs, et rien dans
la page ne dit laquelle Android va lire.

La règle qui en sort vaut au-delà du cas : **quand une valeur décrit un objet
qu'on peut interroger, on interroge l'objet.**

**Puis le cache de Google, qui rend deux réponses contradictoires.** Le site
déployé servait bien les deux empreintes, et la vérification échouait toujours.
L'API publique de Google — `digitalassetlinks.googleapis.com` — n'en voyait
qu'une : son infrastructure avait mis le fichier en cache avant le déploiement.

Le champ `maxAge` de la réponse donne la durée de vie restante, et sert de
signal : une valeur qui **remonte** signifie que Google est allé relire. Elle
est passée de 37 minutes à une heure pleine, la seconde empreinte est apparue,
et la vérification a rendu `verified`.

Mais huit appels d'affilée depuis la même machine ont ensuite rendu quatre fois
l'ancien contenu et quatre fois le nouveau. **Douzième forme : un même système
rend deux réponses contradictoires au même instant**, chacune cohérente en
elle-même, et l'on tombe sur l'une ou l'autre au hasard.

Elle est la plus retorse de la série parce qu'elle prend à contre-pied tout ce
qui précède. Les onze premières se corrigent en mesurant ; celle-ci punit qui
mesure **une seule fois** — un appel rend une réponse complète, plausible, sans
erreur. Rien n'invite à en faire un second quand le premier répond ce qu'on
espérait, et c'est exactement à ce moment-là qu'il le faut.

Conséquence pratique, écrite pour le jour où un testeur le signale : pendant la
propagation, deux appareils peuvent obtenir des résultats opposés avec un
fichier irréprochable. Ce n'est pas une régression, et ça se règle seul.

#### Ce que le téléphone a confirmé par ailleurs

Démarrage à froid en **196 ms**. Ouverture animée mesurée au film à **5,8 s**
contre 5,5 s de construction. Aucun plantage sur l'APK de production avec R8.

Et un faux défaut qui vaut d'être connu : le verset du jour différait entre le
téléphone et l'émulateur. **L'horloge du Samsung était restée en 2025.** Rien à
corriger — une app qui doit marcher sans réseau n'a pas d'autre source de date
que l'appareil.

### 26 août 2026 — la glose des livres n'arrivait pas jusqu'à l'app

Le corpus écrit une `glose` sur **chaque livre** — `Gevurot ha-Neviim` porte
« Actes des Apôtres » comme pont français et « les gevurot de YHWH par ses
neviim » comme glose. Le site les affiche tous les deux depuis toujours,
`sommaire.rs` choisissant selon « Le français reçu ». L'app iOS, elle, affichait
le français **quel que soit le réglage** : `BookOutline` ne déclarait pas le
champ, donc la traduction du schéma le jetait sans que rien ne s'en aperçoive.
L'auteur l'a vu en mettant les deux écrans côte à côte.

**Ce que ça dit des trois dépôts.** Un champ que le pipeline écrit et qu'une
liseuse ne déclare pas ne casse **rien** : le domaine compile, l'écran s'affiche,
le lecteur voit simplement l'autre nom. C'est l'inverse exact d'un changement de
schéma, qui casse iOS et Android tout de suite parce qu'ils sont engendrés — ici
la perte est silencieuse des deux côtés à la fois.

- **site** — rien à porter, *constaté* : `sommaire.rs:75-86` traite déjà les
  livres comme les sections. C'est lui qui faisait foi ;
- **Android** — `BookOutline` de `ontkit` porte la même omission, je l'avais
  porté ainsi. Signalé à la session Android dans la même heure ;
- **vault** — rien : la donnée était juste, c'est la lecture qui manquait.

**Et le motif, une fois de plus.** La règle du choix — français si le reçu est
allumé, glose sinon, rien quand la ligne se redoublerait — tenait en trois
lignes et était **recopiée dans une vue**. Elle était donc appliquée dans la
liste de la Bible et **absente** du sélecteur de référence, qui affichait le
français en toutes circonstances. Une règle recopiée est une règle qu'un écran
finit par ne pas appliquer. Elle vit maintenant dans le noyau — `Registre.second`
côté iOS, à côté de `LibelleDUnite`, qui est arrivé là par le même chemin.

### 26 août 2026 — le site consomme le backend de l'app, et ce que ça engage

Le site a ouvert un compte, et ce n'est pas une fonctionnalité de plus : il
**dépend désormais du backend de l'app**, là où il ne dépendait que de `dist/`.
Trois choses en découlent, et aucune ne se voit depuis un seul dépôt.

**`/auth/{fournisseur}`, `/auth/refresh` et `/sync` sont maintenant appelés par
deux clients.** Le backend les servait à l'app iOS ; le site les appelle
aujourd'hui, et Android les appellera. Un changement de forme dans l'une de ces
réponses casse une plateforme qui n'est pas celle qu'on regarde en le faisant.

Le partage des noms JSON est le point le plus fragile : le backend écrit en
`snake_case` **littéral**, sans aucun `rename`. Un `#[serde(rename_all)]` ajouté
là-bas paraîtrait innocent et ferait échouer la désérialisation ici, sans
message utile — le site verrait une réponse vide et l'appellerait « pas de
compte ».

**Les cinq couleurs de surlignage sont une liste que personne ne valide.**
`Highlight.color` est une chaîne libre côté backend : c'est **au client** de
tenir `gold`, `olive`, `sky`, `rose`, `violet`. Deux clients qui divergeraient
afficheraient deux couleurs pour la même marque, et rien ne le signalerait.
L'app le prévoit déjà — « une couleur inconnue vient d'une version plus récente,
et on préfère ignorer la ligne plutôt que de faire échouer toute la
synchronisation » — et le site fait de même.

**Une seconde adresse de retour OAuth existe.** `https://ontbible.com/fr/compte/retour`,
distincte de celle de l'app, qui rebondit vers `ont://`. Elle doit être déclarée
chez chaque fournisseur, et le README du backend l'avait prévu : « [le Services
ID Apple] ne redeviendra nécessaire que le jour où une version web signera des
comptes ». C'est ce jour-là. GitHub, lui, n'accepte qu'une adresse par
application : il en faudra une seconde.

**Ce qui reste vrai des deux côtés, et qu'on ne relâche pas.** La
synchronisation est **facultative** : le site et l'app se lisent entièrement sans
compte. Le backend en donne la raison, et elle vaut ici mot pour mot : « les
surlignages et les notes d'un lecteur de Bible, rattachés à une identité,
révèlent des convictions religieuses — article 9 du RGPD ». Un client qui
exigerait un compte pour lire ferait de cette lecture une donnée.

**Et un piège du contrat, qu'aucune signature ne montre.** Le backend apparie
les surlignages par `(chapter_id, verse)` et non par `id`. Deux couleurs ne
coexistent donc pas sur un même verset, et un identifiant neuf sur un verset
déjà marqué **écrase** au lieu d'ajouter. Un client qui apparierait par `id`
croirait avoir deux marques là où le serveur n'en garde qu'une — et l'écart ne
se verrait qu'après un aller-retour.

### 28 août 2026 — une dixième forme : l'optimisation qu'on n'a pas mesurée

La série des manières dont un relevé peut tromper s'est enrichie de deux
entrées le même jour, et elles se ressemblent assez pour qu'on les confonde.

**La neuvième**, trouvée côté Android : *quand une correction qui n'aurait pas
dû toucher une mesure la déplace, ce n'est pas du bruit — c'est que la mesure
portait sur autre chose.* Un défilement relevé à 320 images en a rendu 754
après un correctif de geste sans rapport ; ce qu'on appelait « le défilement »
était en partie l'animation d'un feuillet qui volait le doigt. L'instrument
était juste, le protocole stable, l'écart réel. Seul le **nom** de la grandeur
était faux.

**La dixième**, trouvée côté iOS le même jour : *une optimisation qu'on n'a pas
mesurée avant et après est une croyance.* `plainText()` construisait deux
chaînes là où une suffit ; les fusionner devait rendre un gain net. Relevé :
**4 %**, de 0,280 à 0,269 ms. Le coût était dans le parcours caractère par
caractère, pas dans l'allocation qu'on croyait coupable.

**Ce qui les rapproche** : dans les deux cas le chiffre est bon, le protocole
tient, et c'est le récit autour qui est faux. On croit savoir *ce qu'on mesure*
dans un cas, *pourquoi c'est rapide* dans l'autre.

**Ce qui les sépare, et qui est la part utile** : la dixième se détecte en
mesurant — il suffit de le faire des deux côtés du changement. La neuvième ne
se détecte pas du tout. Il faut qu'une correction étrangère déplace le chiffre,
et qu'on choisisse de s'en **étonner** plutôt que de s'en réjouir. C'est ce
qu'on ne fait pas d'ordinaire quand un nombre s'améliore.

**Et la conséquence pratique, prise des deux côtés** : garder dans un test la
*mesure* plutôt que la *conclusion*. « C'est rapide » vieillit ; « 0,27 ms pour
trente versets » est encore utile le jour où quelqu'un change la donne. Les
deux liseuses portent maintenant un relevé de ce genre au même endroit — le
calcul des ancres de position —, avec le prix écrit de ce qui le rendrait
coûteux : rendre le suivi de lecture observable le facturerait à chaque image,
sur le geste le plus courant de l'app.

**Ce qui traverse** : rien de technique. C'est une manière de tenir les
relevés, et elle vaut pour les trois dépôts — le vault mesure des corpus, le
site des temps de rendu, l'app des images par seconde.

---

## 30 août 2026 — le corpus publié écrasait le corpus embarqué, plus neuf

**Traverse les trois dépôts.** Le vault date le contenu, le pipeline l'estampille,
le site le publie, les deux apps le lisent. Le maillon manquant tenait en un
champ vide.

### Ce qui se serait passé

L'app iOS lit son corpus **du disque quand il existe, du bundle sinon** — et le
disque est rempli par ce que le site publie. Tant que le publié est le plus
récent des deux, tout va bien. C'est faux **à chaque livraison TestFlight**, où
un build part avant que le site redéploie.

Mesuré sur simulateur en voulant simplement montrer le rendu des Shemot :

    bundle de l'app : 1913 occurrences de "shem"
    disque de l'app :  217   ← ce que l'app lit vraiment

Le dossier effacé, l'app le recréait au lancement en retéléchargeant l'ancien.
La couche des noms propres serait arrivée chez tous les testeurs **sans un seul
nom affiché**. Aucun test ne pouvait l'attraper : ils mesurent tous le corpus du
bundle, que personne ne lit.

### La forme du défaut

`genere` traverse toute la chaîne depuis le début, et vaut `""`. Il n'a pas été
oublié : `build.rs` le laisse vide **délibérément**, pour que deux exécutions
sur le même vault produisent le même octet — donc la même empreinte, donc aucun
retéléchargement inutile. Le déterminisme était tenu ; l'ordre entre deux corpus
n'existait nulle part, et personne n'en avait eu besoin jusqu'ici.

Côté site, `corpus-publie.py` reportait bien le champ, mais avec un
`.get(…, "")` : il publiait un manifeste **bien formé et indatable**. Un défaut
par valeur par défaut est plus discret qu'un défaut par oubli, parce que sa
sortie a l'air correcte.

### Le remède, et pourquoi il n'est pas une horloge

La date porte celle du **contenu source** — le dernier commit du vault —, pas
celle du build. Déterministe pour un vault donné, croissante quand il change :
l'ordre qui manquait, sans sacrifier ce que le pipeline tenait.

Elle est **passée en entrée** au pipeline, jamais lue par lui : un binaire qui
ouvre `.git` tombe sur un export d'archive, un `--depth 1`, un vault copié sans
son dépôt. Et le repli sur la mtime des fichiers est un piège — un clone frais
leur donne la mtime du `checkout`, c'est-à-dire l'heure du build déguisée, et
non déterministe en CI où personne ne regarde.

### Le format, qui n'est pas une préférence

    %Y-%m-%dT%H:%M:%SZ en UTC   →   2026-08-30T00:14:00Z

L'app compare ces dates **comme des chaînes**. Deux écritures du *même instant*
s'ordonnent alors à l'envers :

    "2026-08-30T00:14:00Z"  <  "2026-08-30T02:14:00+02:00"

L'app garderait le plus vieux des deux corpus **en croyant garder le plus
neuf** — le même défaut, sous une date bien formée, donc bien plus difficile à
voir qu'un champ vide. Pas de `to_rfc3339()` : il rend l'offset de la machine de
build et des fractions de seconde, ce qui casse aussi le déterminisme entre la
CI en UTC et une machine en `+02:00`.

### Ce que chaque dépôt en porte

| | |
|---|---|
| **pipeline** | `generated_at` reçoit la date du vault, en entrée |
| **site** | refuse de publier un corpus indatable ; le report existait déjà |
| **app iOS** | `CorpusUpdater.Estampille` — n'accepte que ce qu'il peut prouver plus récent |
| **app Android** | n'avait aucun dépôt disque : le défaut n'y existait pas, l'actualiseur s'y porte avec la garde |

**Refuser quand l'ordre est indécidable.** Un corpus figé se voit et se répare ;
un corpus silencieusement remplacé par du plus vieux ne se voit pas. C'est le
défaut qu'on corrige — l'accepter « au cas où » serait le reproduire dans sa
correction.

**Ordre de livraison, sinon on se bloque en rond** : pipeline, site, app.

### Ce qu'on en retient au-delà du cas

Trois fois dans la même soirée, une mesure exacte a répondu à une autre question
que celle qu'on posait. Le rendu montrait du rose : le moteur, sondé plutôt
qu'accusé, rendait `#B98B6C` — c'était la donnée qui était vieille. Une session
cherchait le même défaut sur Android, ne l'a pas trouvé, et a trouvé à la place
une fiche Play qui promettait la fonctionnalité absente. Et les quatre tests de
la nouvelle garde passaient **sans elle**, leurs manifestes ne listant aucun
fichier — un instrument dont la panne ressemble au résultat attendu.

La parade, à chaque fois, est la même : vérifier que l'épreuve **échoue** quand
on retire ce qu'elle garde.

---

## 30 août 2026 — une déclaration sans la chose, deux fois le même mois

Le réglage « Le français reçu » d'Android décrivait son effet dans son propre
texte d'aide — « Apocalypse », « la Loi », « **Chapitre 7** » — et aucun écran
de lecture ne le produisait. La pastille disait `Bereshit 2` dans les deux
registres ; le sélecteur aussi ; sa sortie courte proposait « Toute l'unité »,
un troisième mot hors des deux registres.

C'est **le deuxième cas du même genre en quelques jours**. La fiche du Play
Store annonçait la mise à jour du corpus avant qu'Android sache la faire ; la
correction n'était pas d'amender la phrase mais d'écrire l'actualiseur. Gloire
l'avait dit en une ligne : *« il faut pas fixer la déclaration, il faut
implémenter ce qu'il manque »*.

Le motif mérite d'être nommé, parce qu'il ne ressemble pas à un défaut : rien
n'est faux dans le code, rien ne plante, aucun test ne rougit. C'est un texte
qui décrit une intention, et la distance entre l'intention et le fait n'est
mesurée nulle part. **Une phrase d'aide, une fiche de magasin, un `README` : ce
sont des affirmations sur le logiciel que le logiciel ne vérifie pas.**

### L'état des trois, sur ce point précis

| | ce qu'il fait du registre |
|---|---|
| **site** | complet, et **au-delà** : en glose ONT, `Parashah` est un intraduisible en or, touchable, qui ouvre sa fiche |
| **app iOS** | complet — `LibelleDUnite`, cinq formes, trois points d'appel |
| **app Android** | l'annonçait dans ses réglages, ne le produisait nulle part → #153 |

Le site était **en avance sur les deux apps**, ce qui n'est pas l'ordre
habituel. Le porter d'iOS a suffi pour Android ; son traitement du mot comme
intraduisible touchable reste, lui, à porter — et c'est à iOS d'en décider.

### Le pluriel qui ne se francise pas

*parashah* fait *parashiot*, jamais « parashahs » : le §2.5 le fixe, et la
marque hébraïque est le seul détail du lot qu'un point d'appel pressé règle
avec un `+ "s"`. Franciser l'intraduisible **déferait exactement ce que le
réglage vient de faire**. Les trois dépôts portent maintenant le cas dans un
test.

### Et une méthode qui a servi deux fois

Une branche en retard ne demande pas un rebasage, elle demande qu'on vérifie
**si elle a encore quelque chose à dire**. Appliquée à deux PR le même soir,
elle a donné des verdicts opposés : #144 était entièrement dépassée et s'est
fermée ; #95 était 38 commits derrière et portait pourtant deux choses vivantes
— le libellé d'unité, et le skill de l'émulateur — qui sont dans #153.

Le reste de #95 posait la **bonne** question — en prose continue, le rang de
l'item ne bouge jamais — avec le mauvais remède : sa fraction de défilement
*estimait* la position, là où `SuiviDeLecture` la *mesure* par
`TextLayoutResult`. Vérifié sur l'appareil avant de fermer, parce qu'une
session qui ne peut pas éprouver du Kotlin avait refusé de trancher à
l'aveugle sur un terrain qui n'était pas le sien.

---

## 30 août 2026 — la liseuse du Mac, et la raison du standard de contraste

**Traverse les trois dépôts**, pour deux raisons très différentes.

### Ce qui a été fait

`ONTFeatures` était le seul paquet fermé à macOS, avec pour raison écrite « les
vues emploient UIKit ». **Mesuré : 3 fichiers sur 25, 8 références.** La
déclaration était très au-dessus de la chose — et elle a tenu des semaines parce
que personne n'avait compté.

Le reste — une trentaine de points — n'était pas un désaccord de conception mais
des modificateurs SwiftUI qu'iOS a et que le Mac n'a pas. Ils passent désormais
par `ONTPlateformes`, côté design system : **une vue déclare une intention,
jamais un système.**

### Ce que ça dit à Android

Le portage Kotlin a rencontré la même question et l'a résolue autrement, en
écrivant deux fois. La leçon vaut dans les deux sens : **ce qui diffère entre
plateformes se range en deux tas, et on les traite différemment.**

- ce que les deux nomment autrement — un titre compact, un placement de bouton,
  une image : ça se **traduit**, en un seul endroit ;
- ce que l'une a et l'autre pas — un glissement de retour, une tâche de fond
  qui suppose un appareil qui dort : ça se **décide**, et le code doit montrer
  qu'on a décidé.

Le second tas est petit. C'est le premier qui fait croire qu'un portage est
long.

### Ce que ça dit au site

`ONTShareItem` était enfermé dans un `#if canImport(UIKit)` alors qu'il ne
contient rien d'UIKit. Il emportait avec lui tout le code qui *décide* quoi
partager — identique partout —, alors que seule la **présentation** diffère.

**La limite qu'une compilation conditionnelle doit suivre : ce qui touche au
système, jamais ce qui touche au sens.** Le site a la même frontière à tenir
entre ce qui dépend du navigateur et ce qui dépend du corpus.

### Et le point qui vaut le plus, pour les trois

**Le projet s'impose un standard de contraste au-dessus d'AA depuis des
semaines, et la raison n'était écrite nulle part.**

Elle a un nom : le **kératocône** de l'auteur. La condition déforme les lettres
et effondre la sensibilité au contraste. Distinguer deux niveaux de texte par
*la pente* — l'italique — est donc pour lui le pire discriminant possible : on
ajoute de la déformation à de la déformation. Ce qui tient contre elle est la
**couleur, la taille, l'espace**.

C'est ce que fait `ONTTypography.apparatus` depuis toujours, sans que le
commentaire dise pourquoi. C'est aussi ce qui rend un aperçu markdown pénible à
relire, et ce qui a motivé la liseuse du Mac.

**Une exigence dont on connaît le motif se défend ; une exigence orpheline se
fait raboter au premier arbitrage.** Le vault, le site et les deux apps tiennent
tous des seuils de contraste : ils savent maintenant contre quoi.

---

## 30 août 2026 — la décision qui vivait dans la vue, et ce qu'elle avait déjà coûté

La session iOS, en portant la liseuse sur Mac, a nommé une frontière : **une
compilation conditionnelle doit suivre ce qui touche au système, jamais ce qui
touche au sens.** Chez elle, `ONTShareItem` était enfermé dans un
`#if canImport(UIKit)` sans contenir un octet d'UIKit, et emportait avec lui le
code qui *décide* quoi partager.

Android n'a ni `#if` ni `expect`/`actual`. La question s'y posait donc
autrement — quelle décision est écrite dans une vue ? — et la réponse était la
même : **la composition du texte partagé, écrite deux fois.**

### Ce que la duplication avait déjà coûté

|  | corps | renvoi | lien |
|---|---|---|---|
| lecture | oui | oui | **oui** |
| verset du jour | oui | oui | **non** |

Le lien manquait au partage le plus fréquent — un verset du jour se transmet, un
passage étudié beaucoup moins. C'était donc le seul que le destinataire ne
pouvait pas ouvrir. Et il manquait depuis qu'on l'avait *ajouté* : le second
point d'appel n'avait pas été vu.

**iOS porte le même écart, sur la même paire d'écrans** — `ChapterView.swift`
pose un lien, `QahalTab.swift` non.

### Le détail qu'aucune lecture du code n'aurait donné

Android enveloppait le corps dans une paire de chevrons, iOS non. On pouvait
croire à un goût. C'en est un fait : **le corpus ouvre des citations que le
verset ne ferme pas.** Bereshit 6:13 porte un chevron ouvrant et aucun fermant,
parce que le discours d'Elohim continue au verset suivant — le français veut
qu'on rouvre à chaque unité sans fermer avant la fin.

    « Elohim dit à Noach : « La fin de toute chair… avec la Terre. »

Deux ouvertures, une fermeture, et un chevron final qui **ferme un propos que le
traducteur avait laissé courir**. Il fallait un verset qui cite quelqu'un, et il
fallait regarder la feuille de partage sur l'appareil.

### Et l'erreur commise en corrigeant, qui est la vraie leçon

En extrayant la composition, on y a ajouté une « normalisation » du corps qui
fondait les retours à la ligne en espaces. Elle contredisait `replier`, **deux
fichiers plus loin**, qui les préserve délibérément :

> un retour à la ligne est une décision de mise en page du traducteur — la
> seconde ligne d'un parallélisme, l'ouverture d'un discours

Sur l'écran, ça sautait aux yeux : « Elohim dit à Noach : » et l'ouverture du
discours collés sur une ligne.

**Sortir une décision au bon endroit ne suffit pas si on en profite pour en
ajouter une.** Un nettoyage qui passe pour de l'hygiène est exactement ce que
personne ne relit.

### 30 août 2026 — une fonte qui ne se charge pas ne dit rien, et une garde peut mentir dans le sens rassurant

**Source : l'app, cible macOS. Conséquence pour le site et pour Android.**

La liseuse du Mac n'inscrivait aucune de ses fontes. iOS les déclare par
`UIAppFonts` dans l'`Info.plist` ; **macOS ne lit pas cette clé** — il lit
`ATSApplicationFontsPath`. La cible `ONTMac` ne déclarait ni l'une ni l'autre :
les `.ttf` étaient copiés dans le bundle, et personne ne les inscrivait.

Mesuré dans l'hôte de test réel : `Literata-Regular`, `-Italic` et `-SemiBold`
**ne se résolvaient pas**. Toute la typographie de lecture du Mac retombait sur
la fonte système. Literata est choisie pour la lecture longue, et c'est le
lecteur au kératocône qui la payait.

#### Pourquoi personne ne l'a vu pendant des semaines

Deux silences empilés, et c'est ça qui vaut d'être retenu.

**Le premier est dans l'API.** `Font.custom("Literata-Regular", size:)` avec un
nom qui ne se résout pas ne lève pas, ne prévient pas, ne journalise pas : il
rend la fonte système. Un nom de fonte est une chaîne, et une chaîne qui ne
désigne rien n'est pas une erreur pour le compilateur.

**Le second est dans la machine de l'auteur.** `EzraSIL`, elle, *se résolvait* —
non depuis le bundle, mais depuis `~/Library/Fonts/SILEOT.ttf`, Gloire ayant
installé Ezra SIL à titre personnel. **L'hébreu s'affichait donc juste sur sa
machine et sur aucune autre.** Le défaut le plus difficile à voir n'est pas
celui qui se cache : c'est celui qui ne se produit pas chez celui qui regarde.

#### La garde qui aurait dû l'attraper rendait « oui » sans regarder

`ONTFonts.hebrewAvailable`, `isAvailable(_:)` et `bodyAvailable` vérifiaient
sous `#if canImport(UIKit)` et **retombaient sur `true`** ailleurs. Le catalogue
du design system affichait « embarquée », en vert, sur la seule plateforme où
c'était faux.

C'est le même motif qu'une garde paraphrasée relevée le même jour côté backend,
et il mérite un nom : **une garde qui ne sait pas ne doit pas rassurer.** Le
repli d'une plateforme inconnue est désormais `false`, non `true`. Un « je ne
sais pas » rendu comme un « oui » est pire que l'absence de garde — l'absence,
au moins, ne fait pas fermer la question.

#### Ce que ça dit au site

Le site **n'a pas** ce défaut-là : `style/main.css` déclare bien sa `@font-face`
pour « Ezra SIL », avec un `unicode-range` borné aux blocs hébreux pour que le
navigateur ne la télécharge pas afin de dessiner du latin. Vérifié, pas supposé.

Mais il partage l'autre trouvaille de la journée, et par construction.
`src/interface/design/verset.rs` rend l'hébreu dans une course en ligne à
`text-[1.08em]` — le même `ONTFonts.hebrewScale`, commenté comme tel. Or
`body { line-height: 1.68 }` est **sans unité**, donc hérité comme un *nombre* :
chaque élément le recalcule contre sa propre taille, et la course hébraïque
s'en donne `1,68 × 1,08 = 1,814em` là où le reste de la ligne tient `1,68em`.

**Ceci est déduit de la cascade, non mesuré** — et la journée a montré ce que
valent les causes plausibles non mesurées. La vérification tient en une ligne
dans l'inspecteur : comparer la hauteur d'une ligne portant de l'hébreu à celle
de ses voisines, sur une unité qui en contient.

Si l'écart est là, **le remède y est trivial** là où il ne l'est pas dans l'app :
une `line-height` explicite sur la course hébraïque, ou une valeur en `rem` sur
le paragraphe. CSS sait faire en une déclaration ce que SwiftUI ne sait pas
faire du tout.

#### Ce que ça dit à Android

Deux choses, et la première est la plus urgente au vu du portage en cours.

**Les fontes se déclarent encore autrement.** Ni `UIAppFonts` ni
`ATSApplicationFontsPath` : `res/font/` et le nom de ressource, ou
`FontFamily`/`Font` en Compose. Une troisième plateforme est une troisième
occasion de croire que copier le fichier suffit. **La garde est ce qui
transporte**, pas la clé : une épreuve qui charge chaque fonte par son nom et
échoue si l'une ne répond pas vaut sur les trois, et c'est ce qui manquait ici.

**Et le même mécanisme d'interligne s'y retrouvera.** La cause n'est pas qu'une
fonte soit plus haute que l'autre — mesurées, leurs boîtes se valent à taille
égale, rapport 0,995. C'est que **la ligne mêlée prend l'ascendante la plus
haute et la descendante la plus basse parmi deux fontes différentes** :
l'ascendante de Literata, la descendante d'EzraSIL.

    Literata 23,54 + EzraSIL 8,72 = 32,26   contre 29,70   → +2,56 pt

Tout moteur qui compose une ligne à partir de plusieurs fontes fait ce calcul —
TextKit, le navigateur, et Android aussi. Ce n'est pas un défaut d'Apple, c'est
la définition d'une ligne.

#### Le geste, plus que le résultat

Cinq bancs de mesure ont été écrits dans la journée pour cette question.
**Quatre ont répondu à côté, et aucun n'a échoué** : deux composaient une
écriture avec la fonte système sans le dire, un comparait EzraSIL au système
plutôt qu'à Literata, un concluait d'un seul point de mesure.

Les deux garde-fous qui distinguent le cinquième sont dans
`scripts/banc-interligne.swift`, et ils valent pour les trois dépôts :

1. **inscrire les fontes**, puis **vérifier qu'elles répondent**, et s'arrêter
   sinon. Un banc qui mesure la fonte de repli rend des nombres plausibles ;
2. **balayer plutôt que mesurer un point.** Un seul point ne distingue pas « ça
   répond » de « ça a bougé pour une autre raison ». C'est ce qui a fait prendre
   un `45 → 38` réel pour la preuve d'une propriété qui n'existe pas : `SwiftUI.Text`
   **ignore** le style de paragraphe, balayé de 20 à 90 points sans qu'un point
   bouge.

`scripts/banc-chapitre.swift` mesure l'autre moitié, et renverse la crainte qui
retenait le portage : **c'est l'architecture qui coûte, pas le moteur.** Une vue
par verset vaut 8× une vue unique côté SwiftUI, 5,6× côté TextKit — le choix
qu'on croyait secondaire pèse plus que celui qu'on croyait risqué. Vrai des
trois plateformes, où la même alternative se posera.

### 30 août 2026 — l'instrument qui répond à une autre question

**Source : les trois dépôts, dans la même soirée.**

Douze fois dans la journée, une mesure exacte a répondu à côté. Le compte n'est
pas une curiosité : **aucune des douze n'a été attrapée par plus de rigueur dans
la mesure.** Elles l'ont été par un second regard, ou par une contradiction entre
deux sources.

#### Ce qui a coûté le plus cher

**Une garde paraphrasée a bloqué tout le dépôt.** `corpusDatable` vérifiait que
les deux estampilles du corpus *existent* ; ce que le téléchargement exige, c'est
que la publiée soit *plus récente*. Deux dates lisibles dont la publiée est la
plus vieille passaient donc la garde et rendaient zéro fichier. Ça se déclenche
dès que le vault avance avant que le site ne republie — et **toutes** les PR de
`ONTBibleApp` tombaient depuis, en attendant une publication que personne n'avait
de raison de faire.

Le nom même était le glissement : « le corpus est-il datable » n'est pas « le
téléchargement va-t-il avoir lieu ». **Une garde doit répéter sa condition mot
pour mot, ou déléguer au même code.** Quand elle a son propre nom, elle a déjà
commencé à s'en éloigner.

Corollaire trouvé le même soir, dans les épreuves du Mac : une épreuve qui
mesurait un `Form` promettait d'établir le comportement d'une `List`. Elle
passait au vert et ne couvrait rien.

#### Ce que ça change pour les trois dépôts

**Une garde qui rassure est pire qu'une garde absente.** L'absente laisse la
question ouverte ; la paraphrasée la fait croire close. À relire dans chaque
dépôt : est-ce que le *nom* de la garde nomme la condition, ou sa conséquence ?

**Une sonde contre le déployé est la seule chose qui mesure ce qui tourne** ;
tout le reste mesure ce qu'on a écrit. Aucune garde du site ne pouvait voir la
configuration de la Lambda qu'il appelle. Quand on allume un fournisseur, la
sonde fait partie de l'allumage, pas de la vérification d'après.

**Une contradiction entre deux sources est un instrument**, et c'est le seul qui
attrape une erreur de *méthode* et non d'état. Elle a servi trois fois : un
`grep` qui contredisait une session voisine et qui a révélé un arbre de travail
717 lignes en retard ; une mesure d'interligne refaite par une seconde session,
qui a montré que la première attribuait un effet réel à la mauvaise cause ; et un
plan de déploiement dont une troisième session a vu la course, pas les chiffres.

#### Le backend est déployé

Depuis un worktree sur `origin/main`, l'arbre principal étant en retard. L'état
Terraform est local : il a été copié, employé, puis recopié **sous garde du
`serial`** — 56 au départ, vérifié inchangé avant d'écrire, 58 après. Sans cette
garde, un `apply` concurrent aurait vu son état écrasé par un plus ancien, en
silence : le motif du corpus publié qui recouvre le paquet plus récent,
transposé sur un `.tfstate`.

Sondé sur le déployé, pas annoncé : Apple passe de 503 à 401 sur l'origine web —
il marche. GitHub reste à 503 tant que le repli de #164 n'a pas franchi
`dev → staging → main`.

#### Et une treizième, mesurée le soir même

La liseuse du Mac ne suivait pas ⌘= sur son écran « Vous ». Trois captures n'ont
rien prouvé : le facteur d'échelle **n'était pas celui qu'on croyait avoir posé**
— 0,9 au lieu de 1,5 —, si bien qu'on mesurait un écran qui avait raison de ne
pas bouger.

Ce qui a tranché, en un seul build : **une sonde qui affiche ses propres
conditions** à côté de ce qu'elle mesure. `f=1.5 cran=1 reglage=1` disait à la
fois le résultat et l'état, et l'incohérence entre les deux derniers a nommé la
cause. Une mesure qui n'affiche pas ses conditions ne mesure rien — c'est la
même leçon que les fontes non inscrites, prise par l'autre bout.

Le défaut réel, une fois le facteur vraiment posé : **une `List` de macOS ne
transmet pas `\.font` à ses lignes.** Vaut pour les trois dépôts au titre de la
méthode, et pour le seul Mac au titre du remède.
