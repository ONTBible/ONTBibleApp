/**
 * Le document de référence — `CLAUDE.md` — devient le lexique de la liseuse.
 *
 * C'est ici que se joue l'équivalent ONT de ce que Bible Strong fait avec les
 * numéros Strong : le glossaire des intraduisibles *est* le lexique, et il
 * est déjà écrit. Deux sources s'y combinent :
 *
 *   §2.5  la liste des formes **à baliser** — elle dit ce qui est un
 *         intraduisible, donc ce qui devient une cible d'appui long, et
 *         quelles formes dérivées retombent sur le même lemme.
 *   §3    les tables de terminologie fixée — elles donnent l'hébreu, la
 *         traduction ONT arrêtée, et le champ sémantique complet.
 *
 * §2.6 fournit en plus les répertoires de noms de livres, d'où l'on tire le
 * titre hébreu de chaque slot.
 *
 * On lit `CLAUDE.md` plutôt que de recopier son contenu ici : une décision
 * terminologique prise dans le vault doit se retrouver dans la liseuse au
 * prochain build, sans qu'on ait à toucher au pipeline.
 */

import fs from 'node:fs/promises';
import path from 'node:path';

import {
  extractHebrew,
  hasHebrew,
  parseInline,
  plainText,
  slugify,
  tidy,
} from './inline.ts';
import type { Block, GlossaryEntry } from './types.ts';
import { REFERENCE } from './config.ts';

/** Une forme balisée citée entre accents graves : `` `**chesed**` ``. */
const TAGGED_FORM = /`\*\*([^`*]+)\*\*`/g;

/** « Premier emploi en *Bereshit* 8:20 » → `Bereshit 8:20`. */
const FIRST_USE = /premier emploi[^*]*\*([^*]+)\*\s*([\d]+(?::[\d\-–]+)?)?/i;

const HEADING = /^(#{1,6})\s+(.*)$/;
const TABLE_ROW = /^\s*\|(.*)\|\s*$/;
const TABLE_SEPARATOR = /^\s*\|[\s:|-]+\|\s*$/;

interface Section {
  /** Le numéro de section tel qu'écrit — `2.5`, `3.2`. */
  number: string | null;
  title: string;
  lines: string[];
}

/** Découpe le document en sections, repérées par leur numéro de titre. */
function splitSections(lines: string[]): Section[] {
  const sections: Section[] = [];
  let current: Section = { number: null, title: '(préambule)', lines: [] };

  for (const line of lines) {
    const heading = HEADING.exec(line);
    if (heading) {
      sections.push(current);
      const title = heading[2]!.trim();
      current = {
        number: /^(\d+(?:\.\d+)*)\.?\s/.exec(title)?.[1] ?? null,
        title,
        lines: [],
      };
      continue;
    }
    current.lines.push(line);
  }
  sections.push(current);
  return sections;
}

/** Extrait les lignes de tableau d'une section, en cellules brutes. */
function tableRows(lines: string[]): string[][] {
  const rows: string[][] = [];
  for (const line of lines) {
    if (!TABLE_ROW.test(line) || TABLE_SEPARATOR.test(line)) continue;
    rows.push(TABLE_ROW.exec(line)![1]!.split('|').map((cell) => cell.trim()));
  }
  return rows;
}

/** Le texte nu d'une cellule, hébreu compris. */
function cellText(cell: string): string {
  return tidy(plainText(parseInline(cell), { level3: true }));
}

function asBlocks(text: string): Block[] | null {
  const trimmed = text.trim();
  return trimmed ? [{ t: 'para', nodes: parseInline(trimmed) }] : null;
}

// ─────────────────────────────────────────────────────────────────────────────
// §2.5 — les formes à baliser
// ─────────────────────────────────────────────────────────────────────────────

interface TaggedTerm {
  lemma: string;
  title: string;
  forms: string[];
  note: string;
  firstUse: string | null;
  /** L'hébreu que la note énonce au passage, quand le §3 n'en donne pas. */
  hebrew: string | null;
}

/**
 * Lit la liste des intraduisibles.
 *
 * On n'extrait que les formes citées entre accents graves — le reste de la
 * ligne est de la prose qui peut elle-même contenir du gras d'emphase, et le
 * confondre avec une forme balisée créerait de faux lemmes.
 */
function readTaggedTerms(section: Section): TaggedTerm[] {
  const terms: TaggedTerm[] = [];

  for (const line of section.lines) {
    if (!/^\s*[-+]\s+/.test(line)) continue;

    const forms = [...line.matchAll(TAGGED_FORM)].map((match) => match[1]!.trim());
    if (!forms.length) continue;

    // La prose restante, une fois les formes citées retirées.
    const note = line
      .replace(/^\s*[-+]\s+/, '')
      .replace(TAGGED_FORM, '')
      .replace(/^[\s/,;:—–-]+/, '')
      .trim();

    const firstUseMatch = FIRST_USE.exec(line);
    const firstUse = firstUseMatch
      ? `${firstUseMatch[1]!.trim()}${firstUseMatch[2] ? ` ${firstUseMatch[2]}` : ''}`
      : null;

    // Le lemme vient de la première forme citée ; les formes dérivées
    // annoncées sur la même ligne y retombent (§2.5, règle de déduction).
    const title = forms[0]!;
    terms.push({
      lemma: slugify(title),
      title,
      forms,
      note,
      firstUse,
      hebrew: extractHebrew(note),
    });
  }

  return terms;
}

// ─────────────────────────────────────────────────────────────────────────────
// §3 — les tables de terminologie fixée
// ─────────────────────────────────────────────────────────────────────────────

interface FixedTerm {
  lemma: string;
  title: string;
  hebrew: string | null;
  rendering: string | null;
  definition: string;
  section: string;
}

/**
 * Lit les tables `| Terme hébreu | Translittération | Traduction ONT | … |`.
 *
 * Une ligne peut porter plusieurs termes séparés par une barre oblique
 * (`*ishah* / *ish*`, `*goy* / *goyim*`) : on les dédouble, en appariant les
 * hébreux correspondants quand leur nombre concorde.
 */
function readFixedTerms(section: Section): FixedTerm[] {
  const terms: FixedTerm[] = [];

  for (const cells of tableRows(section.lines)) {
    const [hebrewCell, translitCell, renderingCell, meaningCell] = cells;
    if (!translitCell || !hebrewCell) continue;
    // La ligne d'en-tête n'a pas d'hébreu dans sa première cellule.
    if (!hasHebrew(hebrewCell)) continue;

    const split = (cell: string): string[] =>
      cell.split('/').map((part) => cellText(part)).filter(Boolean);

    const translits = split(translitCell);
    const hebrews = split(hebrewCell);
    const renderings = renderingCell ? split(renderingCell) : [];
    const definition = meaningCell ? meaningCell.trim() : '';

    // Une ligne peut porter plusieurs termes appariés colonne par colonne
    // (`*orlah* / *arel*`). On n'apparie que si les comptes concordent —
    // sinon la cellule entière vaut pour chacun, ce qui reste vrai.
    const pick = (parts: string[], index: number): string | null =>
      parts.length === translits.length ? (parts[index] ?? null) : (parts[0] ?? null);

    translits.forEach((translit, index) => {
      terms.push({
        lemma: slugify(translit),
        title: translit,
        hebrew: pick(hebrews, index),
        rendering: pick(renderings, index),
        definition,
        section: section.number ?? '3',
      });
    });
  }

  return terms;
}

// ─────────────────────────────────────────────────────────────────────────────
// §2.6 — les répertoires de noms de livres
// ─────────────────────────────────────────────────────────────────────────────

/** Le nom d'un livre tel que le CLAUDE.md §2.6 le fixe. */
export interface BookName {
  /** Le nom hébreu translittéré — le vrai titre du livre (§2.6). */
  translit: string;
  /** Le titre en écriture hébraïque. */
  hebrew: string;
}

/**
 * Associe à chaque identifiant de livre son nom canonique.
 *
 * Les répertoires n'ont pas tous la même forme (3 ou 4 colonnes, l'ordre
 * varie) : plutôt que de coder chaque table, on repère dans chaque ligne la
 * cellule qui porte de l'hébreu et celle dont la translittération correspond
 * à un slot connu.
 */
function readBookNames(section: Section, knownIds: Set<string>): Map<string, BookName> {
  const names = new Map<string, BookName>();

  for (const cells of tableRows(section.lines)) {
    const hebrewCell = cells.find((cell) => hasHebrew(cell));
    if (!hebrewCell) continue;

    for (const cell of cells) {
      if (cell === hebrewCell) continue;
      const translit = cellText(cell);
      const id = slugify(translit);
      if (id && knownIds.has(id) && !names.has(id)) {
        names.set(id, { translit, hebrew: cellText(hebrewCell) });
        break;
      }
    }
  }

  return names;
}

// ─────────────────────────────────────────────────────────────────────────────

export interface Reference {
  /** Le glossaire, sans les décomptes — ils sont remplis par le build. */
  glossary: GlossaryEntry[];
  /**
   * Forme dérivée → lemme canonique.
   *
   * C'est la règle de déduction du §2.5 rendue exécutable : « toute forme
   * dérivée d'un terme intraduisible est elle-même intraduisible ». Un
   * `**anashim**` rencontré dans le texte doit ouvrir la fiche d'**ish**, un
   * `**mishpatim**` celle de **mishpat**.
   *
   * Une forme qui possède sa propre entrée (**tov me'od** en a une, distincte
   * de **tov**) n'y figure pas : elle reste son propre lemme.
   */
  formIndex: Map<string, string>;
  /** Identifiant de livre → nom canonique (§2.6). */
  bookNames: Map<string, BookName>;
}

/** Lit `CLAUDE.md` et en tire le glossaire et les noms de livres. */
export async function readReference(
  vault: string,
  knownBookIds: Set<string>,
): Promise<Reference> {
  const text = await fs.readFile(path.join(vault, REFERENCE), 'utf8');
  const sections = splitSections(text.split(/\r?\n/));

  const tagged = sections
    .filter((section) => section.number === '2.5')
    .flatMap(readTaggedTerms);

  const fixed = sections
    .filter((section) => /^3\.[123]$/.test(section.number ?? ''))
    .flatMap(readFixedTerms);

  const bookNames = new Map<string, BookName>();
  for (const section of sections.filter((s) => s.number === '2.6')) {
    for (const [id, name] of readBookNames(section, knownBookIds)) {
      if (!bookNames.has(id)) bookNames.set(id, name);
    }
  }

  // Les intraduisibles d'abord — ils sont la colonne vertébrale du lexique —
  // puis le vocabulaire fixé vient les enrichir ou s'ajouter.
  const entries = new Map<string, GlossaryEntry>();

  for (const term of tagged) {
    entries.set(term.lemma, {
      lemma: term.lemma,
      title: term.title,
      tagged: true,
      forms: [...new Set(term.forms)],
      hebrew: term.hebrew,
      rendering: null,
      definition: null,
      taggingNote: asBlocks(term.note),
      firstUse: term.firstUse,
      sourceSection: '2.5',
      count: 0,
      bodyCount: 0,
      glossCount: 0,
    });
  }

  for (const term of fixed) {
    const existing = entries.get(term.lemma);
    if (existing) {
      existing.hebrew ??= term.hebrew;
      existing.rendering ??= term.rendering;
      existing.definition ??= asBlocks(term.definition);
      existing.sourceSection = `2.5 + ${term.section}`;
      continue;
    }
    entries.set(term.lemma, {
      lemma: term.lemma,
      title: term.title,
      tagged: false,
      forms: [term.title],
      hebrew: term.hebrew,
      rendering: term.rendering,
      definition: asBlocks(term.definition),
      taggingNote: null,
      firstUse: null,
      sourceSection: term.section,
      count: 0,
      bodyCount: 0,
      glossCount: 0,
    });
  }

  // Une forme citée au §2.5 est un intraduisible, même si sa fiche vient
  // d'une table du §3 — c'est le cas de **tov me'od**, listé comme forme de
  // **tov** mais doté de sa propre définition.
  for (const term of tagged) {
    for (const form of term.forms) {
      const entry = entries.get(slugify(form));
      if (entry) entry.tagged = true;
    }
  }

  // Les formes dérivées qui n'ont pas de fiche propre pointent vers leur lemme.
  const formIndex = new Map<string, string>();
  for (const term of tagged) {
    for (const form of term.forms) {
      const slug = slugify(form);
      if (slug !== term.lemma && !entries.has(slug)) formIndex.set(slug, term.lemma);
    }
  }

  return {
    glossary: [...entries.values()].sort((a, b) => a.lemma.localeCompare(b.lemma, 'fr')),
    formIndex,
    bookNames,
  };
}
