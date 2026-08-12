# App iOS — découpage proposé

Reprend les frontières de **Pinkha** (paquets SPM, catalogue DS vivant) et le
découpage en couches de **Coco** (`domain` / `data` / `application` /
`presentation`). Adapté à ce que l'ONT a de particulier : un corpus unique
partagé par toutes les features, et un texte à trois niveaux.

---

## 1. Le graphe des modules

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
         App (Sources/App)            assemblage, injection, routeur
```

Une seule règle, et le compilateur la fait respecter : **les flèches ne
remontent jamais**. `ONTKit` ne peut pas importer SwiftUI ; il ne sait rien
d'AWS, du bundle, ni de l'écran.

Pourquoi des paquets et pas des dossiers : un dossier est une convention qu'on
oublie, un module est une barrière. Le jour où quelqu'un écrit
`import ONTFeatures` depuis `ONTKit`, la compilation casse — c'est le but.

---

## 2. Ce que contient chaque module

### ONTKit — le domaine

```
Corpus/      Inline · Block · Verse · Chapter · Book · Mode · Corpus
Glossary/    GlossaryEntry · Occurrence · TermLevel
Reader/      Highlight · HighlightColor · ReadingPosition
Ports/       CorpusRepository · GlossaryRepository · SearchIndex
             HighlightRepository · PositionRepository · SyncClient
```

Des structures et des protocoles. Aucun `import SwiftUI`, aucun accès disque,
aucun réseau. C'est ce qui rend le domaine testable sans simulateur — comme le
backend Rust, dont les 21 tests tournent sans AWS.

### ONTData — les implémentations

```
Bundle/      BundleCorpusRepository · BundleGlossaryRepository
             JSONSearchIndex
Local/       FileHighlightRepository · FilePositionRepository
Remote/      HTTPSyncClient · TokenStore          (à venir)
```

Chaque type implémente **un** protocole d'`ONTKit`. C'est ici que vit la
connaissance du format JSON produit par le pipeline, du chemin de fichier, du
schéma d'URL — et nulle part ailleurs.

### ONTDesignSystem

```
Tokens/      ONTColors · ONTSpacing · ONTRadius · ONTMotion
Typography/  ONTTextStyle · ONTFonts
Theme/       ONTTheme · ONTTheme+Environment
Surfaces/    ParchmentPage · BurgundyCard · GlassSheet
Controls/    ONTButtonStyle · ColorSwatchRow · StatusPill
Text/        ONTTextRenderer      ← le rendu des trois niveaux
Catalog/     DSCatalog + une section par famille de jetons
```

### ONTFeatures — un dossier par feature, en couches

```
ReadingFeature/
  Application/   ReadingModel        (@Observable, orchestre les dépôts)
  Presentation/  BookListView · ChapterView · VerseRow · SettingsSheet
```

Le domaine et les données sont **partagés**, pas dupliqués par feature :
contrairement à Coco où chaque feature a son propre domaine, ici Bible,
Lexique et Recherche lisent tous **le même corpus**. Le dupliquer créerait
trois vérités.

---

## 3. Le design system

### Couleurs — validées

Relevées **au pixel** sur `La Bible ONT - Combination Mark.png`. Le logo est la
source unique : l'icône de l'app (`ONT.icon`) porte la même teinte, convertie
en Display P3.

| Jeton | Valeur | Emploi |
|---|---|---|
| `burgundy` | `#421B26` | fond des cartes, accent, titres de section |
| `gold` | `#CDBE83` | texte sur bordeaux, filets, numéros de verset |
| `goldDeep` | `#A6874F` | intraduisibles sur fond clair (contraste suffisant) |
| `parchment` | `#FAF5EA` | fond de lecture |
| `ink` | `#2A211C` | corps du texte |

Plus la palette de surlignage (or · olive · ciel · rose · violet), pensée pour
se poser sur un texte qu'on lit longtemps sans crier.

### Typographie — le vrai travail

C'est là que l'ONT diffère de toute autre app. Six styles, chacun adossé à un
niveau du texte (`CLAUDE.md` §2.1) :

| Style | Niveau | Rôle |
|---|---|---|
| `.display` | — | titres d'unité (Frank Ruhl Libre) |
| `.corpus` | 1 | le corps de la traduction |
| `.term` | 1 | les intraduisibles |
| `.gloss` | 2 | la voix du projet, en retrait |
| `.translit` | 3 | la translittération, latine italique |
| `.hebrew` | 3 | Ezra SIL, RTL, niqqud et te'amim |

Le renderer ne connaîtra plus une seule taille en dur : il lira ces styles.
Aujourd'hui `.custom("Georgia", size: 19)` traîne dans quatre fichiers.

### Catalogue

Repris tel quel de Pinkha, y compris la règle : **un composant ajouté sans sa
ligne de catalogue est un composant qu'on oubliera**.

---

## 4. Ce que ça corrige, concrètement

Ce que j'ai écrit vite pour vous montrer quelque chose qui tourne, et qui ne
tiendra pas :

| Problème actuel | Principe | Correction |
|---|---|---|
| `Library` charge les fichiers **et** met en cache **et** répond aux requêtes | S | trois dépôts, un rôle chacun |
| `Store` mêle surlignages, position et persistance | S | deux dépôts + un adaptateur de persistance |
| Les vues appellent `library.book(id)` directement | D | elles dépendent d'un protocole, injecté |
| `ONTText` fige les fontes et les tailles | O | il lit les jetons du thème |
| Impossible de tester une vue sans le bundle réel | D | dépôts en doublure, comme le backend |

---

## 5. Deux défauts que je n'ai pas signalés jusqu'ici

**L'accessibilité.** Mes tailles de texte sont en points fixes. Elles ignorent
donc Dynamic Type — le réglage système de taille de police. Pour une liseuse,
et pour un lectorat qui n'a pas vingt ans, c'est un vrai défaut, pas un détail.
Pinkha le fait bien : ses jetons d'espacement sont des `@ScaledMetric`
relatifs à `.body`, donc ils grandissent avec le réglage. Je reprends ça.

**Le thème sombre est à moitié fait.** `ReadingSettings.Theme` ne s'applique
qu'à l'écran de lecture ; le reste de l'app suit le système. Il faut que le
thème soit une décision unique, portée par l'environnement.

---

## 6. État — fait

Les quatre étapes sont appliquées.

| | État | Vérification |
|---|---|---|
| `ONTDesignSystem` | ✅ | jetons, six styles de texte, surfaces, catalogue |
| `ONTKit` | ✅ | zéro dépendance — **16 tests hors simulateur** |
| `ONTData` | ✅ | dépôts bundle + disque derrière les protocoles |
| `ONTFeatures` | ✅ | cinq features, un modèle chacune |
| Tests sur doublures | ✅ | **6 tests** du modèle de lecture, sans bundle |

Le catalogue du design system est accessible depuis l'onglet « Vous » en build
de développement.

### Ce qui a changé, mesurable

- **Plus une seule fonte ni taille en dur** dans les vues : tout passe par
  `theme.type`.
- **Dynamic Type** est respecté — les espacements et le corps du texte suivent
  le réglage système, ce qui n'était pas le cas.
- **Le thème est unique** et porté par l'environnement, au lieu de ne
  s'appliquer qu'à l'écran de lecture.
- **Les conformités rétroactives ont disparu** (`String: Identifiable`,
  `Int: Identifiable`), remplacées par `LemmaSelection` et `VerseSelection` :
  une conformité rétroactive est globale et entre en conflit dès qu'une
  bibliothèque en déclare une autre.
- **Un test de modèle se écrit en trois lignes de doublure**, là où il aurait
  fallu un bundle complet.
