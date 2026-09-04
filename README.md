# La Bible ONT — l'app, le pipeline, le backend

Trois pièces dans un dépôt, et elles ne se ressemblent pas : le **pipeline** qui
transforme le vault de traduction en données, l'**app iOS** qui les lit, le
**backend** qui synchronise ce que le lecteur y ajoute.

Dans l'esprit de YouVersion pour la lecture, de Bible Strong pour le lexique.

```
../ONTBibleTranslation      le vault — la traduction (dépôt voisin)
        │
        ▼
   pipeline/     Rust        vault + CLAUDE.md → dist/*.json  +  les DTO Swift
        │
        ├──▶  app/           l'app iOS — le corpus est embarqué au build,
        │                    puis recouvert par les mises à jour du réseau
        │
        ├──▶  ../ONTBibleWebapp   le site, qui prend la caisse en dépendance
        │
        └──▶  backend/  Rust sur Lambda — comptes, surlignages, position
```

```bash
./scripts/corpus.sh                       # vault → dist/ → ressources → projet Xcode
cargo test --manifest-path pipeline/Cargo.toml     # 63 tests
cargo test --manifest-path backend/Cargo.toml      # 25 tests, sans réseau ni AWS
```

---

# I. Le pipeline

Rien ici n'est propre à une plateforme. La sortie est du JSON que Swift, Kotlin
et Rust lisent aussi bien : **le choix du socle d'une liseuse ne change pas une
ligne de ce dossier.**

```bash
cargo run --manifest-path pipeline/Cargo.toml --bin ont-pipeline --release
```

Le vault est lu **à côté** — les deux dépôts sont côte à côte sous `ONTBible/`.
`ONT_VAULT` permet d'en viser un clone ailleurs, ce dont les CI se servent ;
`ONT_OUT` change la destination. `ONT_PRETTY=1` indente le JSON pour
l'inspection — à ne jamais livrer, l'indentation change les empreintes du
manifeste et ferait retélécharger tout le corpus.

**Le pipeline est en Rust depuis le 14 août 2026.** C'était neuf fichiers
TypeScript exécutés par Node ; c'est un binaire, sans runtime à installer — ni
ici, ni dans les CI qui le rejouent. Le portage a été prouvé en faisant tourner
les deux et en comparant les huit fichiers produits, entrée par entrée :
identiques. Il a trouvé trois défauts que l'original portait en silence, dont
une expression rationnelle globale dont le `lastIndex` persistait — l'hébreu de
certaines définitions du lexique n'était pas isolé, donc rendu sans fonte
hébraïque ni passage en RTL, dans l'app comme sur le site.


## Installer la liseuse du Mac

Par [Homebrew](https://brew.sh), sans passer par l'App Store :

```sh
brew install --cask ontbible/ont/la-bible-ont
```

Le cask vit dans [`ONTBible/homebrew-ont`](https://github.com/ONTBible/homebrew-ont)
et se met à jour tout seul : chaque étiquette `brew-vX.Y.Z` de ce dépôt
construit, signe (Developer ID), notarise et publie le zip, puis réécrit la
version et le `sha256` du cask — voir `.github/workflows/cask.yml`. Cette voie
ne consomme aucune place du quota App Store Connect.

Deux écarts avec la version App Store, dits aussi par le cask : « Continuer
avec Apple » et les notifications poussées demandent des droits réservés à
l'App Store. Google et GitHub fonctionnent.

## Le schéma n'est plus décrit qu'à **un** endroit

`pipeline/src/schema.rs`. Tout le reste en découle, et par deux chemins
différents :

```
                    pipeline/src/schema.rs
                              │
        ┌─────────────────────┴─────────────────────┐
        │                                           │
   dépendance de caisse                      engendrement
        │                                           │
   le site, en Rust                    ONTData/Bundle/Schema.swift
   (ne le redécrit pas)                (réécrit à chaque build)
```

Le site **utilise** les mêmes types : ajouter une variante y casse la
compilation. Swift ne peut pas compiler de Rust, alors on lui écrit ses DTO —
et le `switch` de `SchemaMapping.swift` étant exhaustif, la même variante y
casse la compilation aussi.

`Schema.swift` n'est pas dans le dépôt, comme `dist/` et `ONT.xcodeproj`. Il est
réécrit **inconditionnellement** à chaque build : pas de déclencheur, donc pas
de filtre de chemins à oublier de mettre à jour, donc jamais périmé.

Le jour où une app Android existera, `codegen/kotlin.rs` sera un émetteur de
plus. Le modèle intermédiaire ne connaît ni Swift ni Rust — des types, des
champs, des clés JSON.

**Ce que ça ne couvre pas** : un *champ* ajouté à une structure ne casse rien,
seules les variantes d'énumération sont vérifiées. Un champ ignoré ne fait pas
disparaître de texte ; une variante ignorée, si.

## Le contrat : les trois niveaux ne sont jamais aplatis

Tout le pipeline existe pour cette raison. Le CLAUDE.md du vault §2.1 pose trois
niveaux, et un parseur markdown générique les écraserait en gras/italique
indifférenciés. Ici chaque niveau reste un type de nœud distinct :

| Source | Nœud | Niveau |
|---|---|---|
| texte ordinaire | `text` | 1 — le corps de la traduction |
| `**chesed**` | `term` + `lemma` | 1 — intraduisible, **touchable** → fiche |
| `==« Jour »==` | `accentuation` | 1 — une accentuation, colorée mais **inerte** |
| `*[glose]*` | `gloss` | 2 — la voix du projet |
| `(*chasdo* / חַסְדּוֹ)` | `translit` | 3 — translittération + hébreu |
| hébreu isolé | `heb` | 3 — séquence RTL déjà repérée |

Le nœud `accentuation` (§2.5 bis) est né d'un défaut : du gras posé pour insister
se retrouvait déclaré intraduisible, donc affiché en or et touchable, ouvrant
une fiche de lexique vide. L'or promet une fiche et la tient ; le bordeaux clair
`#862742` marque sans rien promettre.

D'où les interrupteurs de lecture, gratuits côté client : **gloses on/off**,
**hébreu on/off**, corps seul pour la lecture continue.

> **Note de rendu** — retirer un niveau laisse des espaces doubles là où le nœud
> a disparu. Le client doit resserrer les blancs à l'affichage ; les données, elles,
> restent fidèles à la source. `tidy()` fait exactement cela pour le texte nu, en
> préservant l'espace française avant `: ; ! ?` et le guillemet fermant.

## Sortie

```
dist/
  corpus.json        les 70 slots — corpus → mode → livre → unités
  books/<id>.json    le contenu complet d'un livre
  glossary.json      le lexique des intraduisibles
  occurrences.json   lemme → tous ses passages
  search.json        l'index — texte plié, hébreu dénudé
  daily.json         le vivier du verset du jour
  manifest.json      les compteurs du build
  report.md          l'état du corpus, et les anomalies repérées dans le vault
```

**`corpus.json`** est l'arborescence de navigation seule — assez légère pour
être chargée au lancement. L'ordre canonique n'y est pas redéclaré : il est lu
dans les préfixes numériques des dossiers du vault (`01. bereshit (Genèse)`),
donc ajouter un slot dans le vault suffit à le voir apparaître.

**`glossary.json`** est construit depuis le `CLAUDE.md`, pas recopié : §2.5 pour
les formes balisées et le premier emploi, §3 pour l'hébreu, la traduction ONT
arrêtée et le champ sémantique. Une décision terminologique prise dans le vault
arrive dans la liseuse au prochain build.

**`occurrences.json`** distingue le niveau de chaque occurrence — `body` ou
`gloss`. C'est ce qui sépare « où ce mot est dans le texte » de « où on
l'explique », et la ventilation est parlante : **mishpat** paraît 14 fois dans le
corps contre 40 dans les gloses — le profil d'un terme encore en cours de
fondation. **gibbaraya**, lui, est à 47 contre 6 : acquis.

### L'appui long, concrètement

Un `term` porte son `lemma`. Le lemme ouvre son entrée de `glossary.json` —
champ sémantique, hébreu, ce que le terme *n'est pas*, premier emploi — et la
liste de ses passages dans `occurrences.json`. La règle de déduction du §2.5 est
exécutable : `**anashim**` ouvre la fiche d'**ish**, `**mishpatim**` celle de
**mishpat**.

## Les modules

| Fichier | Rôle |
|---|---|
| `pipeline/src/schema.rs` | **le contrat** — le schéma, et les formes des fichiers publiés |
| `pipeline/src/inline.rs` | le tokeniseur — les trois niveaux, et le contrôle des marqueurs |
| `pipeline/src/blocks.rs` | titres, paragraphes, listes, citations, tableaux |
| `pipeline/src/chapter.rs` | un `.md` → une unité ONT : versets, sous-titre, pied de page |
| `pipeline/src/vault.rs` | l'arborescence du vault → corpus / mode / livre |
| `pipeline/src/reference.rs` | `CLAUDE.md` → glossaire et répertoires de noms |
| `pipeline/src/search.rs` | l'index de recherche — texte plié, hébreu dénudé |
| `pipeline/src/build.rs` | assemblage, index des occurrences, rapport |
| `pipeline/src/codegen/` | `schema.rs` → les liaisons des liseuses |

Quatre dépendances, et le contrat n'en demande qu'une. `serde` suffit à décrire
`schema` ; `regex`, `once_cell` et `unicode-normalization` sont derrière la
fonctionnalité `parsers`, active par défaut.

C'est ce qui permet au site de prendre la caisse en `default-features = false` :
il **lit** du JSON déjà produit et ne parse aucun markdown, donc les tables
Unicode de `regex` n'ont rien à faire dans un binaire Lambda dont le démarrage à
froid se compte déjà en centaines de millisecondes. Les deux configurations sont
éprouvées en CI — un `#[cfg]` mal placé ne se verrait sinon qu'au déploiement du
site.

---

# II. L'app iOS

SwiftUI, iOS 18 minimum, Swift 6 en concurrence stricte. Le projet Xcode est
**engendré** par `xcodegen` depuis `app/project.yml` et n'est pas committé —
comme `Schema.swift`, et pour la même raison : committer un fichier engendré,
c'est garantir qu'il divergera.

## Les modules, et une seule règle

```
ONTKit ───────────────┐         le domaine. Zéro dépendance.
   ▲                  │         Inline, Block, Chapter, Book, GlossaryEntry,
   │                  │         Highlight, les protocoles de dépôt.
   │                  ▼
ONTData          ONTDesignSystem      jetons, thème, composants, catalogue
   │                  │               + le moteur de rendu du texte ONT
   └────────┬─────────┘
            ▼
      ONTFeatures                     Qahal · Reading · Lexicon · Search · You
            ▼
      Sources/App                     assemblage, injection, routeur
```

**Les flèches ne remontent jamais**, et c'est le compilateur qui le fait
respecter. `ONTKit` ne peut pas importer SwiftUI ; il ne sait rien d'AWS, du
bundle, ni de l'écran. Des paquets SPM et non des dossiers : un dossier est une
convention qu'on oublie, un module est une barrière.

Le découpage détaillé vit dans **`docs/architecture-app.md`**.

## Les cinq onglets

| onglet | ce qu'il fait |
|---|---|
| **Qahal** (קָהָל) | l'assemblée — le verset du jour ; la part communautaire, posée sans serveur |
| **Bible** | la lecture : chapitre, balayage, réglages, suivi, surlignages |
| **Lexique** | les 105 intraduisibles, et la fiche d'un terme avec ses occurrences |
| **Recherche** | l'index plié, hébreu dénudé |
| **Vous** | compte, synchronisation, thème, effacement |

Le nom *Qahal* est cohérent avec le corpus : la *Kenesset* est le rassemblement
des **textes**, le *Qahal* celui des **lecteurs**. Ce qui suppose d'autres
lecteurs est annoncé sans être simulé — un faux fil d'activité donnerait une
idée fausse de ce qui existe.

S'y ajoutent un **widget** et une **notification** de verset du jour. Les trois
tombent sur le même verset le même jour sans se parler : c'est une fonction de
la date, pas un tirage. Le site rejoue le même calcul, à l'entier près — y
compris son décalage de fuseau, qu'il serait faux de corriger d'un seul côté.

## Le corpus n'est plus prisonnier du binaire

Il est embarqué au build **et** publié sur `ontbible.com/corpus/`. Le bundle
garantit qu'une installation neuve lit le corpus avant d'avoir vu le réseau ;
le disque ne fait que le recouvrir, fichier par fichier, selon un manifeste
d'empreintes.

Sans ça, corriger un verset demandait une compilation, un envoi à Apple, une
revue, puis que chaque lecteur installe la mise à jour — des jours pour une
faute de frappe. Le téléchargement va dans `Application Support` et **pas** dans
`Caches`, qu'iOS purge quand l'espace manque : on perdrait le corpus au pire
moment, hors ligne. Il est exclu des sauvegardes — ces vingt méga sont
retéléchargeables.

## Le thème *mystique* se règle ailleurs

Quatre thèmes de lecture : Parchemin, Clair, Sombre, **mystique**. Le dernier
est la nuit d'aubergine du site, transposée — `ONTColors.nuit`, `nuitSurface`,
`nuitEncre` citent les jetons de `ONTBibleWebapp/style/main.css` par leur nom et
leur valeur. **La référence est le site** : une teinte s'y retouche, puis se
reporte ici. Jamais l'inverse.

## Les tests

| | |
|---|---|
| `app/Packages/*/Tests` + `app/Tests` | **126 tests** — Swift Testing |
| `app/UITests` | **19 tests** — accessibilité, thèmes, gestes, estompage |

Ce qu'ils couvrent et qu'on n'attend pas d'une app : le contraste de chaque
thème, la typographie sous Dynamic Type, les pierres tombales de suppression,
l'image de partage.

---

# III. Le backend

Lambda Rust derrière une API Gateway HTTP, DynamoDB en table unique, région
**Paris**. Comptes Apple / Google / GitHub, jetons maison, synchronisation des
surlignages et de la position de lecture.

Le détail — routes, durées de jeton, création des trois comptes OAuth,
déploiement Terraform — vit dans **`backend/README.md`** et
**`docs/backend-aws.md`**.

Trois décisions à ne pas défaire sans les connaître :

- **Pas de Cognito.** Il facture *par personne* quand tout le reste facture *par
  requête* : à 50 000 lecteurs, 600 $ contre 30 $.
- **Paris, et la synchronisation facultative.** Les surlignages d'un lecteur de
  Bible révèlent des convictions religieuses — catégorie particulière au sens de
  l'article 9 du RGPD. D'où le consentement séparé, le `DELETE /me` qui efface
  pour de vrai, et une app qui reste pleinement utilisable sans compte.
- **La référence est `(unité, verset)`**, jamais un décalage de caractères. Une
  révision du texte déplacerait les caractères et rendrait les surlignages faux.

---

## La liseuse du Mac, et son mode développeur

`ONTMac` est une **cible native**, pas du Catalyst. Catalyst rendrait l'app iOS
dans une fenêtre — gestes, marges de pouce, barre d'onglets en bas —, une app
iPad posée sur un bureau. Elle partage les quatre paquets, donc le corpus, les
thèmes, le moteur de rendu et les seuils de contraste ; **rien de ce qui fait la
lecture n'est réécrit.**

Ce qui diffère est borné et court : les tâches de fond (`BGTaskScheduler`
n'existe pas ici, et une machine allumée n'en a pas besoin) et Sentry. Le reste
des écarts passe par `ONTPlateformes`, côté design system : une vue déclare une
intention — « ce titre est compact » — jamais un système.

**Les notifications, elles, ne diffèrent plus.** Elles figuraient dans cette
liste sur une note affirmant que le Mac « les gère autrement ». Il ne les gérait
pas du tout : `RacineMac` rendait `false` au réglage des parutions et `true` au
verset du jour sans rien programmer — un interrupteur qui refusait de s'allumer,
et un autre qui s'allumait pour rien.

Rien ne l'empêchait. `UserNotifications` existe sur macOS, et
`DailyVerseNotifications` était déjà compilée dans la cible sans que personne
l'appelle. APNs ne distingue pas non plus les deux plateformes : même service,
même format de jeton, même registre côté backend. `PushDistant` n'était UIKit
que par **deux lignes** — `registerForRemoteNotifications` —, isolées depuis
dans deux fonctions privées derrière un `#if canImport`.

### L'échelle de l'interface, et ce que les listes en font

⌘= grossit l'interface — `ONTEchelleUI`, puisque `dynamicTypeSize` est inerte
ici. Deux chemins mènent au texte, et il faut savoir lequel on emprunte :

- **déclarer la fonte** — `ONTUI.body`, `ONTUI.points(14)`. C'est ce que fait la
  barre latérale, et ça marche partout ;
- **s'en remettre à l'environnement**, que `AvecLaFonteDeLInterface` pose sur
  toute la fenêtre. Ça marche partout **sauf dans une `List`**.

Une `List` de macOS ne transmet pas `\.font` à ses lignes : elle leur pose la
fonte système de son style. L'environnement n'est pas perdu — la même vue posée
à côté de la liste grossit — il est écrasé au passage. Mesuré au pixel, facteur
forcé à 1,5, où 32 px valent 13 pt et 48 px valent 19,5 :

| ce qu'on pose | dans une `List` |
|---|---|
| rien (l'environnement seul) | 32 px — ne suit pas |
| `.font()` sur la `List` | 32 px — ne suit pas |
| `.font()` sur une `Section` | 32 px — ne suit pas |
| `.font()` sur un `Text` de ligne | 48 px — suit |
| `.font()` sur un `Label` de ligne | 32 px — ne suit pas |
| un `LabelStyle` | 48 px — suit |

D'où `FonteDesListes`, deux styles posés une fois sur le détail. Les en-têtes de
section et les `Text` nus de `YouTab` restent hors d'atteinte : aucun
modificateur extérieur ne les touche, il faudra qu'ils déclarent `ONTUI`.

### Lire ses brouillons

L'app lit `dist/`, pas le vault. Entre les deux il y a le pipeline. Le mode
vault ferme la boucle : on désigne le dossier, il surveille, il reconstruit,
l'app recharge.

```
./scripts/embarquer-le-pipeline.sh     # une fois, après un build de ONTMac
```

puis, dans l'app, **Fichier → Suivre un vault…** (⇧⌘O). Un bandeau en bas de
fenêtre dit ce qui se passe.

Le pipeline est **embarqué dans l'app** plutôt qu'installé : un binaire posé
dans `/usr/local/bin` vieillirait à part, et l'on relirait ses brouillons avec
un pipeline d'il y a trois semaines sans que rien ne le dise.

Il attend **deux secondes de silence** avant de reconstruire. En dessous, une
sauvegarde automatique d'éditeur déclencherait une reconstruction par phrase ;
au-dessus, on attend devant un texte qu'on vient de corriger. Chaque écriture
repousse l'échéance : c'est la fin de l'écriture qu'on guette, pas son début.

Il écrit dans `Application Support/vault-apercu`, jamais dans `dist/` : un
aperçu de brouillon n'a rien à faire dans un arbre de travail git, ni dans un
build par accident.

Le dossier désigné est **retrouvé au lancement suivant**, par un signet à portée
de sécurité et non par un chemin. Sous bac à sable, le droit de lire un dossier
est accordé au *processus* par le sélecteur, et meurt avec lui : un chemin relu
des réglages désignerait le bon dossier sans l'ouvrir, et l'app dirait « dossier
illisible » d'un dossier parfaitement lisible. « Cesser de suivre » oublie le
signet — cesser veut dire cesser, pas suspendre.

### Le bac à sable

`ONTMac.entitlements` porte `com.apple.security.app-sandbox` depuis le 30 août
2026. Il est **obligatoire à l'App Store du Mac**, et son absence n'empêchait
rien en distribution directe — c'est exactement le genre de manque qui ne se
voit qu'au dépôt de la fiche.

Quatre droits, et pas un de plus :

| droit | pourquoi |
|---|---|
| `app-sandbox` | l'exigence elle-même |
| `files.user-selected.read-only` | le vault ; **lecture seule**, l'aperçu s'écrivant dans le conteneur |
| `files.bookmarks.app-scope` | retrouver le vault au lancement suivant |
| `network.client` | le backend et le manifeste du corpus — le bac coupe le réseau par défaut |

**Ce qui a été mesuré**, sur une app signée ad hoc : le bac s'applique — le
conteneur apparaît sous `~/Library/Containers/com.labibleont.ONT` —, l'app
s'ouvre, et le corpus embarqué se charge intact (864 versets, 108 entrées). Tout
le stockage persistant étant déjà en `Application Support`, il suit dans le
conteneur sans qu'une ligne change.

**Et le processus fils voit le vault** — mesuré le 31 août 2026, sur l'app
signée et confinée, vault désigné à la souris :

    ✓ 44 unités, 864 versets                    ONTBibleTranslation

C'était la question ouverte : un fils hérite du bac de son père, mais **pas
nécessairement des droits que le sélecteur a accordés à celui-ci**. Il les
hérite. Le mode vault fonctionne donc sous bac à sable sans rien changer à sa
mécanique — pas de passage de contenu par un autre canal, pas d'extension à
consommer à la main.

Elle ne pouvait pas se trancher en intégration : il fallait un dossier
réellement choisi dans le sélecteur, donc une main sur la souris. C'est la seule
mesure de ce chantier qu'un job ne pouvait pas faire.

**Deux limites à connaître avant d'essayer.** Une signature ad hoc portant *à la
fois* le bac et un droit restreint — `applesignin`, `associated-domains` — fait
**échouer le lancement** (`RBSRequestErrorDomain` 5, spawn refusé) : le système
refuse ces droits sans profil au lieu de les ignorer. Pour éprouver le bac
localement, on signe avec les quatre clés de bac **seules**. Et le bac et Sign in
with Apple ne peuvent donc pas être éprouvés ensemble tant que la machine n'est
pas enregistrée dans le compte développeur.

### Pourquoi ce mode existe

Relire un brouillon dans un aperçu markdown distingue le corps des gloses par
**l'italique** — donc par la pente des lettres. C'est le pire discriminant
possible pour un lecteur atteint de kératocône, où la condition déforme déjà les
formes et effondre la sensibilité au contraste.

L'app distingue les niveaux par **la couleur, la taille et l'espace** — voir
`ONTTypography.apparatus` — et sait éteindre les gloses pour ne garder que le
corps. **C'est aussi la raison, longtemps tacite, du standard de contraste
au-dessus d'AA que ce projet s'impose.** Une exigence dont on connaît le motif
se défend ; une exigence orpheline se fait raboter au premier arbitrage.

# IV. La livraison

Cinq workflows, et chacun répond à une question différente.

| workflow | quand | ce qu'il fait |
|---|---|---|
| `tests.yml` | poussée, proposition | éprouve — **sans aucun secret**, le dépôt étant public |
| `branch-policy.yml` | proposition | refuse qu'on saute un palier de la chaîne |
| `livraison.yml` | `dev` / `staging` / `main` | monte le build vers le bon public |
| `deployer-backend.yml` | `main` | remplace le **code** de la Lambda, jamais son infrastructure |
| `signature-diagnostic.yml` | à la main | ce que la clé App Store Connect a le droit de voir |

**Le Mac ne passe pas par là**, et c'est mesuré et non choisi.
`./scripts/livrer-le-mac.sh` fait la même chaîne depuis la machine de l'auteur.

L'`actool` d'Xcode 26.3 **plante** en composant `ONT.icon` pour macOS — un
plantage sans diagnostic, pile d'appel d'`IBAbstractPlatformToolProxy` et rien
d'autre. Et l'image du runner ne propose que cette version, alors que le
workflow demande déjà `latest` : il n'y a pas de version à monter.

Un runner **auto-hébergé** réglerait la version et ouvrirait pire. Ce dépôt est
public, et un runner auto-hébergé sur un dépôt public laisse toute proposition
venue d'un fork exécuter du code sur la machine — c'est celle de l'auteur.

Le script suit donc les mêmes règles que le workflow, sans démon qui écoute :
même table de canaux, même numéro de build daté, même `destination: upload`
plutôt qu'`altool`. Il vérifie l'icône **avant** d'archiver, parce que le
découvrir au milieu d'une archive coûte l'archive. Le jour où l'image du runner
monte de version, ce fichier redevient un job et l'on jette celui-ci.

**Une branche nomme un destinataire, pas une manœuvre :**

| branche | qui le voit |
|---|---|
| `dev` | soi, et les siens — groupe interne TestFlight |
| `staging` | les testeurs invités — groupe externe, revue de bêta |
| `main` | tout le monde — revue de l'App Store |

Les rulesets de GitHub savent exiger une revue, une signature, un contrôle vert.
Ils ne savent pas exiger **d'où** vient une branche : c'est ce que
`branch-policy.yml` écrit, et il est ensuite posé comme contrôle requis, ce qui
lui donne la même force qu'une règle.

**Aucune clé nulle part** pour AWS : l'authentification passe par OIDC, et la
condition sur `sub` épingle le dépôt et la branche. Et **la CI ne touche jamais
à Terraform** — l'état vit en local ; un job qui l'exécuterait travaillerait sans
savoir ce qui existe, donc recréerait tout ou détruirait ce qu'il ignore.

---

## L'auteur se nomme **Gloire Bikouta** en public

Le vault emploie un nom fonctionnel, interne au projet. Il ne sort pas : ni dans
l'app, ni sur le site, ni sur GitHub, ni dans une fiche d'App Store.

La règle était écrite dans le CLAUDE.md du site, et ce dépôt ne la connaissait
pas — l'onglet « Vous » a crédité la traduction au nom interne jusqu'au
14 août 2026. C'est ce que coûte une règle qui ne vit que dans un des trois
dépôts.

---

## État du corpus au dernier build

| | |
|---|---|
| Slots | 3 rédigés sur 70 — *Bereshit*, *Toledot Adam ve-Chavah*, *Sefar Gibbaraya* |
| Unités | 39 chapitres + 2 feuilles d'introduction — **781 versets** |
| Glossaire | 105 entrées, dont 47 intraduisibles balisés |
| Index | 2 033 occurrences |

Le flux de validation du §12 est respecté : `brouillons/` l'emporte sur
`locked/` pour une même unité, et chaque unité porte son `status`. La
distribution publique ne doit embarquer que les unités `locked`.

## Ce que le build a trouvé dans le vault

Le pipeline vérifie au passage la conformité au §2.5, qui réserve `**…**`
*exclusivement* aux intraduisibles — un gras d'emphase déclencherait à tort le
style « Transliteration » d'Affinity au copier-coller, et l'app afficherait le
mot en or, touchable, sans fiche derrière. Voir `dist/report.md` pour le détail
avec contexte.

**Onze formes ont été corrigées** le 12 août 2026, converties en `==…==` :
`« Jour »`, `« Nuit »`, `« Cieux »`, `« Mers »`, `« Terre »` (*Bereshit* 1),
les noms propres `Sarah`, `Chavah`, `Noach` (contre le §4.12), et trois
métadonnées d'apparat critique dans *Bereshit* 19.

**Neuf restent**, et elles demandent une décision de traducteur, pas une
correction — entrée de glossaire, ou passage en `==…==` :

- **Formes dérivées non déclarées au §2.5** — `tsadiqim` (9 occ.), `gibborim`,
  `gibor`, `nashim`, `chata'ah`, `tsedaqah umishpat`, `shiphchah`, `Tov vara`.
  La règle de déduction s'y applique, mais les puces du §2.5 ne les listent pas.
- **Une incohérence de forme** — `shaliachim` (2 occ., *Sefar Gibbaraya*) là où
  le §2.5 fixe **shlichim**.

Le relevé complet, avec les emplacements, vit au **CLAUDE.md §13** du vault —
c'est là qu'il se traite, dans le dépôt de la traduction et non ici.

S'y ajoutent 22 marqueurs déséquilibrés, tous dans les pieds de page de
*Bereshit* 15 à 19 : le motif `- ***Terme* (…)` ouvre un gras qui ne se referme
pas. Le parseur le contourne — un `**…**` ne peut pas contenir une phrase
entière — mais la coquille reste à corriger dans le vault.

---

## Se repérer dans le dépôt

| | |
|---|---|
| `pipeline/` | le contrat et sa mise en œuvre — voir la table des modules |
| `app/` | l'app iOS : `Sources/App`, `Packages/`, `Widget/`, `Tests/`, `UITests/` |
| `backend/` | la Lambda Rust, son Terraform, son propre README |
| `scripts/` | `corpus.sh` d'abord ; puis captures, OAuth, déploiement, iPhone |
| `docs/` | `architecture-app.md`, `backend-aws.md`, `comptes-oauth.md` |
| `dist/` | **engendré** — jamais committé, jamais dupliqué |

`scripts/corpus.sh` est le geste qu'on répète : il enchaîne le pipeline,
l'engendrement des DTO, la recopie dans les ressources et `xcodegen`. Quatre
choses qui vont toujours ensemble et qu'on ne veut pas voir se désynchroniser.

## Les dépôts voisins

| | |
|---|---|
| [`ONTBibleTranslation`](https://github.com/ONTBible/ONTBibleTranslation) | le vault — la traduction |
| [`ONTBibleWebapp`](https://github.com/ONTBible/ONTBibleWebapp) | `ontbible.com` |

Les trois portent le même ruleset : `main` protégée, passage par pull request,
**signatures exigées**, suppression de la branche après fusion.
