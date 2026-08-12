/**
 * Schéma des données ONT.
 *
 * Ce fichier est le contrat entre le vault Obsidian et les liseuses (iOS,
 * Android, web). Tout ce qui est produit par le pipeline est décrit ici.
 *
 * Le principe directeur vient du CLAUDE.md §2.1 — le texte ONT a **trois
 * niveaux** et ils ne doivent jamais être aplatis :
 *
 *   niveau 1  le corps de la traduction        → `text`
 *   niveau 2  les gloses *[entre crochets]*    → `gloss`
 *   niveau 3  (translittération / הָעִבְרִית)      → `translit`
 *
 * Plus le balisage des intraduisibles (§2.5) → `term`, qui est la porte
 * d'entrée du lexique : toucher un `term` ouvre sa fiche de glossaire.
 */

// ─────────────────────────────────────────────────────────────────────────────
// Niveau inline — l'arbre d'un fragment de texte
// ─────────────────────────────────────────────────────────────────────────────

/** Un nœud de texte ordinaire (niveau 1). */
export interface TextNode {
  t: 'text';
  v: string;
}

/**
 * Un intraduisible (CLAUDE.md §2.5) — balisé `**ainsi**` dans le vault.
 *
 * `v` conserve la casse exacte du texte (**Elohim** vs **elohim**), `lemma`
 * est la clé de jointure vers le glossaire. La liseuse rend `v`, et ouvre la
 * fiche `lemma` à l'appui long.
 */
export interface TermNode {
  t: 'term';
  v: string;
  lemma: string;
}

/**
 * Niveau 3 — `(*translittération* / הָעִבְרִית)`.
 *
 * Les deux parts sont séparées parce qu'elles ne se composent pas pareil :
 * la translittération est en italique dans la fonte latine, l'hébreu demande
 * une fonte hébraïque et une direction RTL.
 */
export interface TranslitNode {
  t: 'translit';
  translit: string;
  hebrew: string;
}

/**
 * Un fragment en écriture hébraïque rencontré hors d'un nœud `translit`.
 *
 * Isolé pour que la liseuse sache exactement où appliquer la fonte hébraïque
 * et le passage en RTL, sans avoir à refaire de la détection d'écriture.
 */
export interface HebrewNode {
  t: 'heb';
  v: string;
}

/** Niveau 2 — une glose `*[entre crochets en italique]*`. */
export interface GlossNode {
  t: 'gloss';
  children: Inline[];
}

/** De l'italique ordinaire `*ainsi*` — renvois de livres, mots hébreux cités. */
/// Un terme **important** — ni corps ordinaire, ni intraduisible.
///
/// La troisième catégorie du texte ONT, et elle est née d'un défaut : des
/// mots mis en gras pour insister se retrouvaient déclarés intraduisibles,
/// donc affichés en or et touchables, ouvrant une fiche de lexique vide.
///
/// L'intention était juste, il lui manquait sa marque. Elle s'écrit
/// `==important==` — le surlignage natif d'Obsidian, visible en écrivant, et
/// qui n'était employé nulle part dans le vault.
export interface ImportantNode {
  t: 'important';
  children: Inline[];
}

export interface EmNode {
  t: 'em';
  children: Inline[];
}

/** Un lien Obsidian `[[cible]]` ou markdown `[texte](cible)`. */
export interface LinkNode {
  t: 'link';
  children: Inline[];
  href: string;
}

/**
 * Un retour à la ligne à l'intérieur d'un bloc.
 *
 * Le vault écrit un paragraphe par ligne ; quand plusieurs lignes se suivent
 * sans ligne vide, c'est délibéré — le bloc de référence d'une feuille
 * d'introduction (§2.7) empile ses champs ainsi. On préserve la coupure au
 * lieu de la fondre en espace.
 */
export interface BreakNode {
  t: 'break';
}

export type Inline =
  | ImportantNode
  | TextNode
  | TermNode
  | TranslitNode
  | HebrewNode
  | GlossNode
  | EmNode
  | LinkNode
  | BreakNode;

// ─────────────────────────────────────────────────────────────────────────────
// Niveau bloc — la structure d'un fichier
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Un verset ONT.
 *
 * `n` est la numérotation **interne** à l'unité ONT (CLAUDE.md §2.2) : elle
 * repart de 1 à chaque unité et ne correspond pas au numéro biblique. Le
 * renvoi biblique vit dans `Chapter.subtitle.reference`.
 */
export interface Verse {
  n: number;
  nodes: Inline[];
}

export interface HeadingBlock {
  t: 'heading';
  level: number;
  nodes: Inline[];
}

/** Un paragraphe de versets — un paragraphe peut en porter plusieurs. */
export interface VersesBlock {
  t: 'verses';
  verses: Verse[];
}

/** De la prose sans numérotation — feuilles d'introduction, notes de pied. */
export interface ParaBlock {
  t: 'para';
  nodes: Inline[];
}

export interface ListBlock {
  t: 'list';
  ordered: boolean;
  items: Inline[][];
}

export interface QuoteBlock {
  t: 'quote';
  nodes: Inline[];
}

export interface TableBlock {
  t: 'table';
  headers: Inline[][];
  rows: Inline[][][];
}

export interface RuleBlock {
  t: 'rule';
}

export type Block =
  | HeadingBlock
  | VersesBlock
  | ParaBlock
  | ListBlock
  | QuoteBlock
  | TableBlock
  | RuleBlock;

// ─────────────────────────────────────────────────────────────────────────────
// Unités ONT
// ─────────────────────────────────────────────────────────────────────────────

/**
 * L'état d'un texte dans le flux de validation (CLAUDE.md §12).
 *
 * `locked` fait référence ; `brouillon` attend la relecture de l'auteur et
 * **ne voyage pas** dans la distribution.
 */
export type Status = 'locked' | 'brouillon';

/** Le sous-titre de référence `*(Genèse / בְּרֵאשִׁית 18:1-33)*`. */
export interface Subtitle {
  french: string;
  hebrew: string;
  /** Le renvoi biblique tel qu'écrit — `18:1-33`, `1:1 — 2:3`. */
  reference: string | null;
}

/** Le pied de page — `*Bereshit 18 — Version 1.0 — verrouillée*` + décisions. */
export interface Footer {
  version: string | null;
  locked: boolean;
  /** Les décisions terminologiques propres à l'unité. */
  notes: Block[];
}

/**
 * Une unité ONT : un chapitre fonctionnel, ou la feuille d'introduction
 * d'un livre (CLAUDE.md §2.7).
 */
export interface Chapter {
  /** `bereshit-18`, `toledot-adam-ve-chavah-0-intro`. */
  id: string;
  bookId: string;
  kind: 'chapter' | 'intro';
  /** Numéro d'unité ONT. `0` pour une feuille d'introduction. */
  n: number;
  /** Le titre en clair — `Bereshit 18`. */
  title: string;
  titleNodes: Inline[];
  subtitle: Subtitle | null;
  status: Status;
  blocks: Block[];
  footer: Footer | null;
  verseCount: number;
  /** Les lemmes d'intraduisibles employés dans l'unité, dédupliqués. */
  lemmas: string[];
  /** Chemin du fichier source, relatif à la racine du vault. */
  source: string;
}

/** Un livre — un slot de `corpus-order.md`. */
export interface Book {
  /** `bereshit`, `toledot-adam-ve-chavah`. */
  id: string;
  /** Le numéro global 01–70 (`corpus-order.md`). */
  slot: number;
  /** Le nom hébreu translittéré — le vrai titre (CLAUDE.md §2.6). */
  title: string;
  /** Le nom français, pont de navigation pour le lecteur occidental. */
  french: string;
  /** Le titre en écriture hébraïque, quand il est connu. */
  hebrew: string | null;
  corpusId: string;
  modeId: string;
  /** Le conteneur intermédiaire éventuel — `eduyot`, `trei-asar`. */
  groupId: string | null;
  chapters: Chapter[];
  intro: Chapter | null;
  /** Vrai tant qu'aucun texte n'a été rédigé pour ce slot. */
  empty: boolean;
}

/** Un mode fonctionnel — Torah, Nevi'im, Ketouvim, Nistarot (CLAUDE.md §1). */
export interface Mode {
  id: string;
  title: string;
  order: number;
  books: Book[];
}

/** Un corpus — la *Kenesset* ou la *Berit Hadashah*. */
export interface Corpus {
  id: string;
  title: string;
  order: number;
  modes: Mode[];
}

// ─────────────────────────────────────────────────────────────────────────────
// Glossaire — le lexique des intraduisibles
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Une entrée du glossaire : un intraduisible, toutes formes confondues.
 *
 * C'est ce que la liseuse affiche à l'appui long sur un `TermNode`. Le
 * contenu vient du `CLAUDE.md` — §2.5 pour les formes à baliser et le premier
 * emploi, §3 pour le champ sémantique complet.
 */
export interface GlossaryEntry {
  /** La clé de jointure avec `TermNode.lemma`. */
  lemma: string;
  /** La forme d'affichage — `chesed`, `El Elyon`, `She'ol`. */
  title: string;
  /**
   * Vrai si le terme est un **intraduisible** balisé dans le texte (§2.5) —
   * il a donc des occurrences et devient une cible d'appui long.
   *
   * Faux pour le reste du vocabulaire fixé (§3) : *bara* → « orchestrer »,
   * *tselem* → « représentant fonctionnel ». Ces termes-là sont traduits dans
   * le corps, donc invisibles au toucher — mais ils méritent leur fiche dans
   * le glossaire consultable.
   */
  tagged: boolean;
  /** Toutes les formes balisées qui retombent sur ce lemme. */
  forms: string[];
  hebrew: string | null;
  /** La traduction ONT fixée, quand le terme en a une (§3). */
  rendering: string | null;
  /** Le champ sémantique complet (§3) — ce que le terme signifie. */
  definition: Block[] | null;
  /** La note de balisage (§2.5) — règles de rendu, formes dérivées. */
  taggingNote: Block[] | null;
  /** Le premier emploi déclaré — `Bereshit 15:6`. */
  firstUse: string | null;
  /** La section du CLAUDE.md dont vient la définition — `3.2`. */
  sourceSection: string | null;
  /** Nombre total d'occurrences dans le corpus rédigé. */
  count: number;
  /** Occurrences dans le corps de la traduction (niveau 1). */
  bodyCount: number;
  /** Occurrences dans les gloses (niveau 2). */
  glossCount: number;
}

/** Une occurrence d'un intraduisible, pour l'index inversé. */
export interface Occurrence {
  bookId: string;
  chapterId: string;
  /** Numéro de verset ONT, ou `null` hors d'un verset (titre, note, intro). */
  verse: number | null;
  /** La forme exacte employée — `Elohim` vs `elohim`. */
  form: string;
  /**
   * Le niveau où la forme paraît (§2.1) : dans le corps de la traduction, ou
   * dans une glose qui l'explicite. La liseuse doit pouvoir n'afficher que le
   * premier — c'est « où ce mot est dans le texte », par opposition à « où on
   * en parle ».
   */
  level: 'body' | 'gloss';
  /** Un extrait de contexte en texte nu, pour la liste de résultats. */
  snippet: string;
}

// ─────────────────────────────────────────────────────────────────────────────
// Sortie du pipeline
// ─────────────────────────────────────────────────────────────────────────────

export interface BuildStats {
  books: number;
  booksWritten: number;
  chapters: number;
  intros: number;
  verses: number;
  glossaryEntries: number;
  occurrences: number;
  /** Termes balisés dans le texte mais absents du glossaire du CLAUDE.md. */
  unknownTerms: string[];
  /** Entrées du glossaire qui n'apparaissent nulle part dans le corpus. */
  unusedEntries: string[];
}

export interface Manifest {
  schema: number;
  generatedAt: string;
  vault: string;
  stats: BuildStats;
}

/// Un verset candidat au verset du jour.
///
/// Volontairement plat et sans arbre d'inline : ce vivier est lu par un widget
/// iOS, qui dispose d'une trentaine de mégaoctets et doit se dessiner en
/// quelques dizaines de millisecondes.
export interface DailyVerse {
  /** Le livre. */
  b: string;
  /** L'unité. */
  c: string;
  /** Le numéro du verset. */
  n: number;
  /** Le renvoi affichable — « Bereshit 1:1 ». */
  r: string;
  /** Le corps de la traduction, seul. */
  t: string;
}
