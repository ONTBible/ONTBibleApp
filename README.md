# ONT App — pipeline de contenu

Transforme le vault Obsidian de **La Bible ONT** en données structurées pour une
liseuse — dans l'esprit de YouVersion pour la lecture, de Bible Strong pour le
lexique.

Rien ici n'est propre à une plateforme. La sortie est du JSON que Swift, Kotlin
et Rust lisent aussi bien : **le choix du socle de l'app ne change pas une ligne
de ce dépôt.**

```bash
./scripts/corpus.sh                       # vault → dist/ → ressources → projet
cargo run  --manifest-path pipeline/Cargo.toml --bin ont-pipeline --release
cargo test --manifest-path pipeline/Cargo.toml             # 49 tests
```

Le vault est lu à son emplacement iCloud par défaut ; `ONT_VAULT` permet d'en
viser une copie, `ONT_OUT` de changer la destination. `ONT_PRETTY=1` indente le
JSON pour l'inspection — à ne jamais livrer, l'indentation change les empreintes
du manifeste et ferait retélécharger tout le corpus.

**Le pipeline est en Rust depuis le 14 août 2026.** C'était neuf fichiers
TypeScript exécutés par Node ; c'est un binaire, sans runtime à installer — ni
ici, ni dans les deux CI qui le rejouent. Le portage a été prouvé en faisant
tourner les deux et en comparant les huit fichiers produits, entrée par entrée :
identiques. Il a trouvé trois défauts que l'original portait en silence, dont
une expression rationnelle globale dont le `lastIndex` persistait — l'hébreu de
certaines définitions du lexique n'était pas isolé, donc rendu sans fonte
hébraïque ni passage en RTL, dans l'app comme sur le site.

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

---

## L'auteur se nomme **Gloire Bikouta** en public

Le vault emploie **Sha'eliel** — son nom fonctionnel, interne au projet. Il ne
sort pas : ni dans l'app, ni sur le site, ni sur GitHub, ni dans une fiche
d'App Store.

La règle était écrite dans le CLAUDE.md du site, et ce dépôt ne la connaissait
pas — l'onglet « Vous » a crédité la traduction à « Sha'eliel » jusqu'au
14 août 2026. C'est ce que coûte une règle qui ne vit que dans un des trois
dépôts.


---

## Le contrat : les trois niveaux ne sont jamais aplatis

Tout le pipeline existe pour cette raison. Le CLAUDE.md §2.1 pose trois niveaux,
et un parseur markdown générique les écraserait en gras/italique indifférenciés.
Ici chaque niveau reste un type de nœud distinct :

| Source | Nœud | Niveau |
|---|---|---|
| texte ordinaire | `text` | 1 — le corps de la traduction |
| `**chesed**` | `term` + `lemma` | 1 — intraduisible, **touchable** → fiche |
| `==« Jour »==` | `important` | 1 — terme important, coloré mais **inerte** |
| `*[glose]*` | `gloss` | 2 — la voix du projet |
| `(*chasdo* / חַסְדּוֹ)` | `translit` | 3 — translittération + hébreu |
| hébreu isolé | `heb` | 3 — séquence RTL déjà repérée |

Le nœud `important` (CLAUDE.md §2.5 bis) est né d'un défaut : du gras posé pour
insister se retrouvait déclaré intraduisible, donc affiché en or et touchable,
ouvrant une fiche de lexique vide. L'or promet une fiche et la tient ; le
bordeaux clair `#862742` marque sans rien promettre.

D'où les trois interrupteurs de lecture, gratuits côté client : **gloses on/off**,
**hébreu on/off**, corps seul pour la lecture continue.

> **Note de rendu** — retirer un niveau laisse des espaces doubles là où le nœud
> a disparu. Le client doit resserrer les blancs à l'affichage ; les données, elles,
> restent fidèles à la source. `tidy()` fait exactement cela pour le texte nu, en
> préservant l'espace français avant `: ; ! ?` et le guillemet fermant.

---

## Sortie

```
dist/
  corpus.json        les 70 slots — corpus → mode → livre → unités
  books/<id>.json    le contenu complet d'un livre
  glossary.json      le lexique des intraduisibles
  occurrences.json   lemme → tous ses passages
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

---

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
c'est là qu'il se traite, dans le dossier ONT et non ici.

S'y ajoutent 22 marqueurs déséquilibrés, tous dans les pieds de page de
*Bereshit* 15 à 19 : le motif `- ***Terme* (…)` ouvre un gras qui ne se referme
pas. Le parseur le contourne — un `**…**` ne peut pas contenir une phrase
entière — mais la coquille reste à corriger dans le vault.

---

## Structure

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
