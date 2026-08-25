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
