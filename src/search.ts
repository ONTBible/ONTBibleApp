/**
 * L'index de recherche.
 *
 * Le corpus ONT permet une recherche que les liseuses ordinaires ne peuvent
 * pas offrir, parce qu'elles n'ont pas ses niveaux ni son hébreu :
 *
 * 1. **Par niveau** — chercher dans le corps de la traduction seul, ou dans
 *    les gloses, ou partout. « Où le texte dit-il *chesed* » et « où
 *    l'explique-t-on » sont deux questions distinctes (§2.1).
 * 2. **En hébreu, sans les voyelles** — le lecteur tape חסד au clavier
 *    hébreu ordinaire ; le texte porte חֶסֶד avec niqqud et te'amim. On
 *    indexe la forme **dénudée** (consonnes seules) pour que les deux se
 *    rencontrent. Sans ça, la recherche hébraïque ne trouve jamais rien.
 * 3. **Par translittération** — taper « chesed » trouve aussi les passages
 *    où seul l'hébreu figure, via le lemme du glossaire.
 * 4. **Insensible aux diacritiques** — « elohim » trouve **Elohim**,
 *    « tsedaqah » trouve **Tsedaqah**.
 *
 * L'index reste un tableau à plat : à l'échelle du corpus (quelques dizaines
 * de milliers d'entrées une fois les 70 slots rédigés), un balayage de
 * sous-chaînes est instantané sur un téléphone. Un index inversé serait de la
 * complexité sans gain mesurable.
 */

import { collectTerms, plainText, tidy } from './inline.ts';
import type { Block, Chapter, Inline } from './types.ts';

/** Une entrée indexable — un verset, un titre de section, un paragraphe. */
export interface SearchRecord {
  /** Livre. */
  b: string;
  /** Unité ONT. */
  c: string;
  /** Numéro de verset ONT, ou `0` hors d'un verset. */
  v: number;
  /** `verse` | `heading` | `prose` — pour classer les résultats. */
  k: 'verse' | 'heading' | 'prose';
  /** Le corps de la traduction, plié (minuscules, sans diacritiques). */
  t: string;
  /** Les gloses, pliées. */
  g: string;
  /** L'hébreu dénudé de ses voyelles et de sa cantillation. */
  h: string;
  /** Les lemmes d'intraduisibles présents, pour la recherche par terme. */
  l: string[];
  /** Le texte du corps tel qu'il s'affiche — pour l'extrait de résultat. */
  x: string;
}

/**
 * Plie une chaîne latine pour la comparaison : minuscules, diacritiques
 * retirés, apostrophes normalisées.
 *
 * Doit rester **identique** à son homologue Swift, sinon l'index et la requête
 * ne se rencontrent pas.
 */
export function fold(input: string): string {
  return input
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
    .toLowerCase()
    .replace(/['’ʼ]/g, "'")
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Dénude l'hébreu : retire niqqud, te'amim et maqaf, ne laisse que les
 * consonnes.
 *
 * C'est ce qui permet à une saisie au clavier hébreu ordinaire — sans
 * voyelles, comme on écrit l'hébreu tous les jours — de rencontrer un texte
 * biblique intégralement vocalisé.
 */
export function stripHebrew(input: string): string {
  return input
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
    .replace(/[־׀׃׆׳״]/gu, '')
    .replace(/\s+/g, ' ')
    .trim();
}

/** Récolte toutes les séquences hébraïques d'un arbre inline. */
function hebrewOf(nodes: Inline[], into: string[] = []): string[] {
  for (const node of nodes) {
    switch (node.t) {
      case 'heb':
        into.push(node.v);
        break;
      case 'translit':
        into.push(node.hebrew);
        break;
      case 'gloss':
      case 'em':
      case 'important':
      case 'link':
        hebrewOf(node.children, into);
        break;
    }
  }
  return into;
}

/**
 * Le texte des gloses **seules**.
 *
 * Indexer « corps + gloses » sous l'étiquette « gloses » ferait remonter le
 * corps quand on cherche dans les gloses — la distinction de niveaux serait
 * perdue au moment précis où on s'en sert.
 */
function glossText(nodes: Inline[], into: string[] = []): string[] {
  for (const node of nodes) {
    if (node.t === 'gloss') into.push(plainText(node.children, { gloss: true }));
    else if (node.t === 'em' || node.t === 'link') glossText(node.children, into);
  }
  return into;
}

function record(
  chapter: Chapter,
  kind: SearchRecord['k'],
  verse: number,
  nodes: Inline[],
): SearchRecord | null {
  const body = tidy(plainText(nodes));
  const gloss = tidy(glossText(nodes).join(' '));

  if (!body && !gloss) return null;

  return {
    b: chapter.bookId,
    c: chapter.id,
    v: verse,
    k: kind,
    t: fold(body),
    g: fold(gloss),
    h: stripHebrew(hebrewOf(nodes).join(' ')),
    l: [...new Set(collectTerms(nodes).map((term) => term.lemma))],
    x: body,
  };
}

/** Construit l'index d'une unité. */
export function indexChapter(chapter: Chapter): SearchRecord[] {
  const records: SearchRecord[] = [];

  const walk = (blocks: Block[]): void => {
    for (const block of blocks) {
      switch (block.t) {
        case 'verses':
          for (const verse of block.verses) {
            const entry = record(chapter, 'verse', verse.n, verse.nodes);
            if (entry) records.push(entry);
          }
          break;
        case 'heading': {
          const entry = record(chapter, 'heading', 0, block.nodes);
          if (entry) records.push(entry);
          break;
        }
        case 'para':
        case 'quote': {
          const entry = record(chapter, 'prose', 0, block.nodes);
          if (entry) records.push(entry);
          break;
        }
        case 'list':
          for (const item of block.items) {
            const entry = record(chapter, 'prose', 0, item);
            if (entry) records.push(entry);
          }
          break;
      }
    }
  };

  walk(chapter.blocks);
  return records;
}
