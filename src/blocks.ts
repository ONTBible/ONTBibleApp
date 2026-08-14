/**
 * Le découpage en blocs — la structure de la page, au-dessus de l'inline.
 *
 * On n'implémente pas markdown en général : seulement ce que le vault ONT
 * emploie réellement (titres, paragraphes, listes, citations, tableaux,
 * filets). Un sous-ensemble assumé vaut mieux qu'un parseur générique qui
 * inventerait des cas que le corpus ne contient pas.
 *
 * Une règle porte tout le reste : **les lignes qui se suivent sans ligne vide
 * gardent leur coupure**. Le vault écrit un paragraphe par ligne, donc une
 * suite de lignes est toujours intentionnelle — c'est le bloc de référence
 * d'une feuille d'introduction (§2.7), pas de la prose à recoller.
 */

import { parseInline } from './inline.ts';
import type { Block, Inline } from './types.ts';

const HEADING = /^(#{1,6})\s+(.*)$/;
const RULE = /^\s*([-*_])\s*(?:\1\s*){2,}$/;
const UNORDERED_ITEM = /^\s*[-+]\s+(.*)$/;
const ASTERISK_ITEM = /^\s*\*\s+(.*)$/;
const ORDERED_ITEM = /^\s*\d+[.)]\s+(.*)$/;
const QUOTE = /^\s*>\s?(.*)$/;
const TABLE_ROW = /^\s*\|(.*)\|\s*$/;
const TABLE_SEPARATOR = /^\s*\|[\s:|-]+\|\s*$/;

/** Parse plusieurs lignes en un seul flux inline, coupures préservées. */
function parseLines(lines: string[]): Inline[] {
  const out: Inline[] = [];
  lines.forEach((line, index) => {
    if (index > 0) out.push({ t: 'break' });
    out.push(...parseInline(line.trim()));
  });
  return out;
}

/** Découpe une ligne de tableau en cellules. */
function tableCells(line: string): Inline[][] {
  const inner = TABLE_ROW.exec(line)?.[1] ?? '';
  return inner.split('|').map((cell) => parseInline(cell.trim()));
}

function isItemStart(line: string): boolean {
  return (
    UNORDERED_ITEM.test(line) || ORDERED_ITEM.test(line) || ASTERISK_ITEM.test(line)
  );
}

/**
 * Découpe un document markdown ONT en blocs.
 *
 * Les lignes reçues sont celles du fichier, sans transformation préalable.
 */
export function parseBlocks(lines: string[]): Block[] {
  const blocks: Block[] = [];
  let i = 0;

  while (i < lines.length) {
    const line = lines[i]!;

    // Ligne vide — simple séparateur.
    if (!line.trim()) {
      i++;
      continue;
    }

    // Filet horizontal.
    if (RULE.test(line)) {
      blocks.push({ t: 'rule' });
      i++;
      continue;
    }

    // Titre.
    const heading = HEADING.exec(line);
    if (heading) {
      blocks.push({
        t: 'heading',
        level: heading[1]!.length,
        nodes: parseInline(heading[2]!.trim()),
      });
      i++;
      continue;
    }

    // Tableau — une ligne d'en-tête, une ligne de séparation, puis les lignes.
    if (TABLE_ROW.test(line) && TABLE_SEPARATOR.test(lines[i + 1] ?? '')) {
      const headers = tableCells(line);
      const rows: Inline[][][] = [];
      i += 2;
      while (i < lines.length && TABLE_ROW.test(lines[i]!)) {
        rows.push(tableCells(lines[i]!));
        i++;
      }
      blocks.push({ t: 'table', headers, rows });
      continue;
    }

    // Citation.
    if (QUOTE.test(line)) {
      const quoted: string[] = [];
      while (i < lines.length && QUOTE.test(lines[i]!)) {
        quoted.push(QUOTE.exec(lines[i]!)![1]!);
        i++;
      }
      blocks.push({ t: 'quote', nodes: parseLines(quoted) });
      continue;
    }

    // Liste — les lignes de continuation appartiennent à l'item courant.
    if (isItemStart(line)) {
      const ordered = ORDERED_ITEM.test(line);
      const items: Inline[][] = [];
      let current: string[] = [];

      const commit = (): void => {
        if (current.length) items.push(parseLines(current));
        current = [];
      };

      while (i < lines.length) {
        const candidate = lines[i]!;
        if (!candidate.trim()) break;
        if (RULE.test(candidate) || HEADING.test(candidate)) break;

        const match =
          UNORDERED_ITEM.exec(candidate) ??
          ORDERED_ITEM.exec(candidate) ??
          ASTERISK_ITEM.exec(candidate);

        if (match) {
          commit();
          current.push(match[1]!);
        } else {
          current.push(candidate.trim());
        }
        i++;
      }
      commit();
      blocks.push({ t: 'list', ordered, items });
      continue;
    }

    // Paragraphe — toutes les lignes jusqu'à la prochaine frontière.
    //
    // **La première ligne est toujours prise**, et ce n'est pas une commodité :
    // c'est ce qui empêche la boucle de tourner à vide. Une ligne de tableau
    // sans ligne de séparation n'est reconnue ni comme tableau ni comme
    // paragraphe — elle arrive ici, la condition d'arrêt la rejette
    // immédiatement, `i` n'avance pas, et le build tourne jusqu'à épuiser la
    // mémoire de Node.
    //
    // Le vault ne contient aucun tableau mal formé, donc ça ne s'était jamais
    // produit. Une coquille de frappe séparait de la panne.
    const paragraph: string[] = [lines[i]!];
    i++;
    while (i < lines.length) {
      const candidate = lines[i]!;
      if (!candidate.trim()) break;
      if (RULE.test(candidate) || HEADING.test(candidate)) break;
      if (QUOTE.test(candidate) || isItemStart(candidate)) break;
      if (TABLE_ROW.test(candidate)) break;
      paragraph.push(candidate);
      i++;
    }
    blocks.push({ t: 'para', nodes: parseLines(paragraph) });
  }

  return blocks;
}
