# ONT App — pipeline de contenu

Transforme le vault Obsidian de **La Bible ONT** en données structurées pour une
liseuse — dans l'esprit de YouVersion pour la lecture, de Bible Strong pour le
lexique.

Rien ici n'est propre à une plateforme. La sortie est du JSON que Swift, Kotlin
et TypeScript lisent aussi bien : **le choix du socle de l'app ne change pas une
ligne de ce dépôt.**

```bash
npm run build     # vault → dist/
npm test          # le tokeniseur, éprouvé sur du texte réel du vault
npm run check     # typage
```

Le vault est lu à son emplacement iCloud par défaut ; `ONT_VAULT` permet d'en
viser une copie. `ONT_PRETTY=1` indente le JSON pour l'inspection.

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
| `src/inline.ts` | le tokeniseur — les trois niveaux, et le contrôle des marqueurs |
| `src/blocks.ts` | titres, paragraphes, listes, citations, tableaux |
| `src/chapter.ts` | un `.md` → une unité ONT : versets, sous-titre, pied de page |
| `src/vault.ts` | l'arborescence du vault → corpus / mode / livre |
| `src/reference.ts` | `CLAUDE.md` → glossaire et répertoires de noms |
| `src/build.ts` | assemblage, index des occurrences, rapport |
| `src/types.ts` | le schéma — le contrat avec les liseuses |

Zéro dépendance d'exécution : Node 24+ exécute TypeScript nativement, sans étape
de build.
