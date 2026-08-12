/**
 * Le parseur d'unité ONT — un fichier `.md` du vault devient un `Chapter`.
 *
 * Une « unité » au sens du CLAUDE.md §2.3 : un bloc fonctionnel, qui se clôt
 * quand une fonction cosmique est accomplie — pas quand un numéro de chapitre
 * biblique change. Les feuilles d'introduction (§2.7) passent par le même
 * chemin, avec `kind: 'intro'`.
 */

import { parseBlocks } from './blocks.ts';
import { collectTerms, lintMarkers, parseInline, plainText, tidy } from './inline.ts';
import type { Block, Chapter, Footer, Inline, Status, Subtitle, Verse } from './types.ts';

/** Les exposants de la numérotation des versets (CLAUDE.md §2.2). */
const SUPERSCRIPTS = '⁰¹²³⁴⁵⁶⁷⁸⁹';
const SUPER_RUN = new RegExp(`[${SUPERSCRIPTS}]+`, 'gu');
const SUPER_START = new RegExp(`^\\s*[${SUPERSCRIPTS}]`, 'u');

/** `¹⁰` → `10`. */
function superToInt(run: string): number {
  let digits = '';
  for (const char of run) digits += String(SUPERSCRIPTS.indexOf(char));
  return Number.parseInt(digits, 10);
}

/**
 * Découpe un paragraphe en versets, si c'en est un.
 *
 * Un paragraphe du vault porte souvent plusieurs versets à la suite
 * (`³ Ils cherchèrent… ⁴ Car le sol…`). Rend `null` si le paragraphe ne
 * commence pas par un exposant — c'est alors de la prose.
 */
export function splitVerses(nodes: Inline[]): Verse[] | null {
  const first = nodes[0];
  if (!first || first.t !== 'text' || !SUPER_START.test(first.v)) return null;

  const verses: Verse[] = [];
  let current: Verse | null = null;

  for (const node of nodes) {
    if (node.t !== 'text') {
      current?.nodes.push(node);
      continue;
    }

    let last = 0;
    for (const match of node.v.matchAll(SUPER_RUN)) {
      const before = node.v.slice(last, match.index);
      if (before && current) current.nodes.push({ t: 'text', v: before });
      if (current) verses.push(current);
      current = { n: superToInt(match[0]), nodes: [] };
      last = match.index + match[0].length;
    }

    const rest = node.v.slice(last);
    if (rest && current) current.nodes.push({ t: 'text', v: rest });
  }

  if (current) verses.push(current);
  if (!verses.length) return null;

  // Chaque verset s'ouvre sur l'espace qui suivait son exposant.
  for (const verse of verses) {
    const head = verse.nodes[0];
    if (head?.t === 'text') {
      head.v = head.v.replace(/^\s+/, '');
      if (!head.v) verse.nodes.shift();
    }
  }
  return verses;
}

/** Transforme les paragraphes versifiés en blocs de versets. */
function liftVerses(blocks: Block[]): Block[] {
  return blocks.map((block) => {
    if (block.t !== 'para') return block;
    const verses = splitVerses(block.nodes);
    return verses ? { t: 'verses', verses } : block;
  });
}

/**
 * Lit le sous-titre de référence — `*(Genèse / בְּרֵאשִׁית 18:1-33)*`.
 *
 * Le nom français n'est qu'un pont de navigation (§2.6) ; le renvoi biblique
 * est la seule trace de la numérotation d'origine, la numérotation ONT
 * repartant toujours de ¹ (§2.2).
 */
export function parseSubtitle(block: Block): Subtitle | null {
  if (block.t !== 'para') return null;

  const raw = tidy(plainText(block.nodes, { level3: true }));
  const inner = /^\((.+)\)$/.exec(raw)?.[1];
  if (!inner || !inner.includes(' / ')) return null;

  const cut = inner.indexOf(' / ');
  const french = inner.slice(0, cut).trim();
  const right = inner.slice(cut + 3).trim();

  // L'hébreu ne porte pas de chiffres arabes : le premier chiffre ouvre le
  // renvoi biblique, s'il y en a un.
  const digit = right.search(/\d/);
  const hebrew = (digit === -1 ? right : right.slice(0, digit)).trim();
  const reference = digit === -1 ? null : right.slice(digit).trim() || null;

  return { french, hebrew, reference };
}

/** Lit le pied de page — version, verrouillage, décisions terminologiques. */
function parseFooter(blocks: Block[]): Footer | null {
  if (!blocks.length) return null;

  const text = blocks
    .map((block) => (block.t === 'para' ? tidy(plainText(block.nodes)) : ''))
    .join(' ');

  const looksLikeFooter = /version|verrouill|à valider/i.test(text);
  if (!looksLikeFooter) return null;

  return {
    version: /version\s+([\d.]+)/i.exec(text)?.[1] ?? null,
    locked: /verrouill/i.test(text),
    notes: blocks.slice(1),
  };
}

export interface ChapterSource {
  /** Chemin relatif à la racine du vault. */
  path: string;
  text: string;
  bookId: string;
  status: Status;
}

export interface ParsedChapter {
  chapter: Chapter;
  /** Anomalies de balisage repérées, avec leur numéro de ligne. */
  issues: { line: number; message: string }[];
}

/** Déduit le numéro d'unité et le type depuis le nom de fichier. */
function readFileName(path: string): { n: number; kind: 'chapter' | 'intro'; id: string } {
  const id = path.split('/').pop()!.replace(/\.md$/, '');
  const match = /^(.+)-(\d+)(-intro)?$/.exec(id);
  return {
    id,
    n: match ? Number.parseInt(match[2]!, 10) : 0,
    kind: match?.[3] ? 'intro' : 'chapter',
  };
}

/** Parse un fichier du vault en unité ONT. */
export function parseChapter(source: ChapterSource): ParsedChapter {
  const lines = source.text.split(/\r?\n/);
  const { id, n, kind } = readFileName(source.path);

  const issues = lines.flatMap((line, index) =>
    lintMarkers(line).map((message) => ({ line: index + 1, message })),
  );

  const blocks = parseBlocks(lines);

  // En-tête : le titre, puis éventuellement le sous-titre de référence.
  let cursor = 0;
  let titleNodes: Inline[] = parseInline(id);
  if (blocks[cursor]?.t === 'heading' && (blocks[cursor] as { level: number }).level === 1) {
    titleNodes = (blocks[cursor] as { nodes: Inline[] }).nodes;
    cursor++;
  }

  let subtitle: Subtitle | null = null;
  if (blocks[cursor]) {
    subtitle = parseSubtitle(blocks[cursor]!);
    if (subtitle) cursor++;
  }

  // Pied de page : ce qui suit le dernier filet, s'il s'annonce comme tel.
  let body = blocks.slice(cursor);
  let footer: Footer | null = null;
  const lastRule = body.map((block) => block.t).lastIndexOf('rule');
  if (lastRule !== -1) {
    const candidate = body.slice(lastRule + 1);
    footer = parseFooter(candidate);
    if (footer) body = body.slice(0, lastRule);
  }

  // Le filet qui sépare l'en-tête du corps n'est qu'un ornement.
  while (body[0]?.t === 'rule') body.shift();

  body = liftVerses(body);

  const verses = body.flatMap((block) => (block.t === 'verses' ? block.verses : []));
  const lemmas = [
    ...new Set(
      body
        .flatMap((block) =>
          block.t === 'verses'
            ? block.verses.flatMap((verse) => collectTerms(verse.nodes))
            : block.t === 'heading' || block.t === 'para' || block.t === 'quote'
              ? collectTerms(block.nodes)
              : [],
        )
        .map((term) => term.lemma),
    ),
  ].sort();

  return {
    chapter: {
      id,
      bookId: source.bookId,
      kind,
      n,
      title: tidy(plainText(titleNodes)),
      titleNodes,
      subtitle,
      status: source.status,
      blocks: body,
      footer,
      verseCount: verses.length,
      lemmas,
      source: source.path,
    },
    issues,
  };
}
