/**
 * Le build — le vault devient des données consommables par une liseuse.
 *
 * Rien ici n'est propre à une plateforme : la sortie est du JSON que Swift,
 * Kotlin et TypeScript lisent aussi bien. Le choix du socle de l'app ne
 * change pas une ligne de ce fichier.
 *
 *   dist/corpus.json        l'arborescence de navigation, les 70 slots
 *   dist/books/<id>.json    le contenu complet d'un livre
 *   dist/glossary.json      le lexique des intraduisibles
 *   dist/occurrences.json   lemme → toutes ses occurrences
 *   dist/daily.json         le vivier du verset du jour (widget, notification)
 *   dist/report.md          l'état du corpus et les anomalies repérées
 */

import fs from 'node:fs/promises';
import path from 'node:path';

import { OUT, SKELETON, TREES, VAULT, displayName } from './config.ts';
import { parseChapter } from './chapter.ts';
import { collectTerms, plainText, tidy } from './inline.ts';
import { readReference } from './reference.ts';
import { indexChapter, type SearchRecord } from './search.ts';
import { readTree, type VaultBook } from './vault.ts';
import type {
  DailyVerse,
  Block,
  Book,
  Chapter,
  Corpus,
  GlossaryEntry,
  Inline,
  Manifest,
  Mode,
  Occurrence,
  Status,
} from './types.ts';

interface Issue {
  file: string;
  line: number;
  message: string;
}

/** Une forme balisée dans le texte qu'aucune entrée du glossaire ne couvre. */
interface Unknown {
  count: number;
  /** La forme exacte, casse comprise. */
  form: string;
  /** Où on l'a vue la première fois — `bereshit-18:24`. */
  where: string;
  sample: string;
}

/**
 * Cherche le lemme connu dont la forme inconnue pourrait dériver.
 *
 * Purement indicatif : c'est une piste pour l'auteur, pas un verdict. Le
 * critère est le préfixe, ce qui attrape les pluriels et les construits
 * (`tsadiqim` → **tsadiq**, `shaliachim` → **shaliach**) sans prétendre
 * comprendre la morphologie hébraïque.
 */
function guessLemma(form: string, known: Iterable<string>): string | null {
  let best: string | null = null;
  for (const lemma of known) {
    if (lemma.length < 4 || !form.startsWith(lemma) || form === lemma) continue;
    if (!best || lemma.length > best.length) best = lemma;
  }
  return best;
}

/**
 * Parcourt tous les fragments de texte d'une unité, en gardant le numéro de
 * verset quand il y en a un.
 */
function* textUnits(chapter: Chapter): Generator<{ verse: number | null; nodes: Inline[] }> {
  const walk = function* (blocks: Block[]): Generator<{ verse: number | null; nodes: Inline[] }> {
    for (const block of blocks) {
      switch (block.t) {
        case 'verses':
          for (const verse of block.verses) yield { verse: verse.n, nodes: verse.nodes };
          break;
        case 'para':
        case 'heading':
        case 'quote':
          yield { verse: null, nodes: block.nodes };
          break;
        case 'list':
          for (const item of block.items) yield { verse: null, nodes: item };
          break;
        case 'table':
          for (const cell of block.headers) yield { verse: null, nodes: cell };
          for (const row of block.rows) {
            for (const cell of row) yield { verse: null, nodes: cell };
          }
          break;
        case 'rule':
          break;
      }
    }
  };

  yield* walk(chapter.blocks);
  if (chapter.footer) yield* walk(chapter.footer.notes);
}

/**
 * Un extrait de contexte centré sur la forme rencontrée.
 *
 * `from` permet de viser la Nᵉ occurrence : un même verset porte souvent
 * plusieurs fois le même terme (trois **chesed** en *Bereshit* 19:19), et
 * trois extraits identiques ne renseigneraient sur rien.
 */
function makeSnippet(plain: string, form: string, width = 150, from = 0): string {
  const at = plain.indexOf(form, from);
  if (at === -1) return plain.slice(0, width).trim();

  const half = Math.floor((width - form.length) / 2);
  const start = Math.max(0, at - half);
  const end = Math.min(plain.length, at + form.length + half);

  return (
    (start > 0 ? '…' : '') + plain.slice(start, end).trim() + (end < plain.length ? '…' : '')
  );
}

/**
 * Lit toutes les unités d'une arborescence.
 *
 * Les fichiers d'un même livre peuvent venir de `locked/` et de
 * `brouillons/` : la clé de fusion est l'identifiant d'unité, et le brouillon
 * l'emporte (CLAUDE.md §12 — « pour ceux-ci, lire `brouillons/…` »).
 */
async function readChapters(): Promise<{
  chapters: Map<string, Chapter>;
  issues: Issue[];
  superseded: string[];
}> {
  const chapters = new Map<string, Chapter>();
  const issues: Issue[] = [];
  const superseded: string[] = [];

  for (const [status, tree] of Object.entries(TREES) as [Status, string][]) {
    for (const book of await readTree(path.join(VAULT, tree))) {
      for (const file of book.files) {
        const absolute = path.join(book.dir, file);
        const relative = path.relative(VAULT, absolute);
        const text = await fs.readFile(absolute, 'utf8');

        const parsed = parseChapter({ path: relative, text, bookId: book.id, status });
        const key = `${book.id}/${parsed.chapter.id}`;

        const existing = chapters.get(key);
        if (existing && existing.status === 'brouillon') continue;
        if (existing) superseded.push(existing.source);

        chapters.set(key, parsed.chapter);
        for (const issue of parsed.issues) issues.push({ file: relative, ...issue });
      }
    }
  }

  return { chapters, issues, superseded };
}

/** Assemble les livres du squelette et les unités rédigées. */
function assemble(
  skeleton: VaultBook[],
  chapters: Map<string, Chapter>,
  names: Map<string, { translit: string; hebrew: string }>,
): Corpus[] {
  const byBook = new Map<string, Chapter[]>();
  for (const chapter of chapters.values()) {
    const list = byBook.get(chapter.bookId) ?? [];
    list.push(chapter);
    byBook.set(chapter.bookId, list);
  }

  const corpora = new Map<string, Corpus>();

  for (const entry of [...skeleton].sort((a, b) => a.slot - b.slot)) {
    const units = (byBook.get(entry.id) ?? []).sort((a, b) => a.n - b.n);
    const intro = units.find((unit) => unit.kind === 'intro') ?? null;
    const body = units.filter((unit) => unit.kind === 'chapter');

    // Le nom canonique vient du §2.6 ; à défaut, du titre et du sous-titre
    // qu'un chapitre porte déjà.
    const declared = names.get(entry.id);
    const fromTitle = body[0]?.title.replace(/\s+\d+$/, '').trim();
    const fromSubtitle = body[0]?.subtitle ?? intro?.subtitle ?? null;

    const book: Book = {
      id: entry.id,
      slot: entry.slot,
      title: declared?.translit ?? (fromTitle || displayName(entry.id)),
      french: fromSubtitle?.french ?? entry.french,
      hebrew: declared?.hebrew ?? fromSubtitle?.hebrew ?? null,
      corpusId: entry.corpus.id,
      modeId: entry.mode.id,
      groupId: entry.groups.at(-1)?.id ?? null,
      chapters: body,
      intro,
      empty: units.length === 0,
    };

    let corpus = corpora.get(entry.corpus.id);
    if (!corpus) {
      corpus = {
        id: entry.corpus.id,
        title: displayName(entry.corpus.id),
        order: entry.corpus.order,
        modes: [],
      };
      corpora.set(entry.corpus.id, corpus);
    }

    let mode: Mode | undefined = corpus.modes.find((m) => m.id === entry.mode.id);
    if (!mode) {
      mode = {
        id: entry.mode.id,
        title: displayName(entry.mode.id),
        order: entry.mode.order,
        books: [],
      };
      corpus.modes.push(mode);
    }
    mode.books.push(book);
  }

  const result = [...corpora.values()].sort((a, b) => a.order - b.order);
  for (const corpus of result) corpus.modes.sort((a, b) => a.order - b.order);
  return result;
}

/**
 * Construit l'index inversé des intraduisibles.
 *
 * C'est ce qui rend possible l'appui long à la Bible Strong : toucher
 * **chesed** ouvre sa fiche *et* la liste de tous les passages où il paraît.
 */
function indexOccurrences(
  chapters: Iterable<Chapter>,
  glossary: GlossaryEntry[],
  formIndex: Map<string, string>,
): { occurrences: Map<string, Occurrence[]>; unknown: Map<string, Unknown> } {
  const known = new Map(glossary.map((entry) => [entry.lemma, entry]));
  const occurrences = new Map<string, Occurrence[]>();
  const unknown = new Map<string, Unknown>();

  for (const chapter of chapters) {
    for (const unit of textUnits(chapter)) {
      const terms = collectTerms(unit.nodes);
      if (!terms.length) continue;

      // Deux textes de référence : le corps seul, et le corps avec ses gloses.
      // Chaque forme est cherchée dans celui de son niveau, sinon l'extrait ne
      // la contiendrait pas.
      const plainByLevel = {
        body: tidy(plainText(unit.nodes)),
        gloss: tidy(plainText(unit.nodes, { gloss: true })),
      };
      const cursors = new Map<string, number>();

      for (const term of terms) {
        // La règle de déduction du §2.5 : une forme dérivée ouvre la fiche de
        // son lemme.
        const lemma = known.has(term.lemma)
          ? term.lemma
          : (formIndex.get(term.lemma) ?? null);

        const plain = plainByLevel[term.level];
        const cursorKey = `${term.level} ${term.v}`;
        const from = cursors.get(cursorKey) ?? 0;
        const at = plain.indexOf(term.v, from);
        cursors.set(cursorKey, at === -1 ? from : at + term.v.length);

        if (!lemma) {
          const seen = unknown.get(term.lemma);
          if (seen) seen.count++;
          else {
            unknown.set(term.lemma, {
              count: 1,
              form: term.v,
              where: `${chapter.id}${unit.verse ? `:${unit.verse}` : ''}`,
              sample: makeSnippet(plain, term.v, 110, from),
            });
          }
          continue;
        }

        const list = occurrences.get(lemma) ?? [];
        list.push({
          bookId: chapter.bookId,
          chapterId: chapter.id,
          verse: unit.verse,
          form: term.v,
          level: term.level,
          snippet: makeSnippet(plain, term.v, 150, from),
        });
        occurrences.set(lemma, list);
      }
    }
  }

  for (const entry of glossary) {
    const list = occurrences.get(entry.lemma) ?? [];
    entry.count = list.length;
    entry.bodyCount = list.filter((item) => item.level === 'body').length;
    entry.glossCount = list.length - entry.bodyCount;
  }

  return { occurrences, unknown };
}

/** Une vue allégée d'un livre pour l'arborescence de navigation. */
function outline(book: Book) {
  const stub = (chapter: Chapter) => ({
    id: chapter.id,
    n: chapter.n,
    title: chapter.title,
    status: chapter.status,
    verseCount: chapter.verseCount,
    reference: chapter.subtitle?.reference ?? null,
  });

  return {
    id: book.id,
    slot: book.slot,
    title: book.title,
    french: book.french,
    hebrew: book.hebrew,
    groupId: book.groupId,
    empty: book.empty,
    intro: book.intro ? stub(book.intro) : null,
    chapters: book.chapters.map(stub),
  };
}

async function writeJson(file: string, data: unknown): Promise<number> {
  const body = JSON.stringify(data, null, process.env.ONT_PRETTY ? 2 : 0);
  await fs.mkdir(path.dirname(file), { recursive: true });
  await fs.writeFile(file, body, 'utf8');
  return Buffer.byteLength(body);
}

function formatReport(
  corpora: Corpus[],
  glossary: GlossaryEntry[],
  issues: Issue[],
  unknown: Map<string, Unknown>,
  superseded: string[],
): string {
  const books = corpora.flatMap((c) => c.modes.flatMap((m) => m.books));
  const written = books.filter((book) => !book.empty);

  const lines: string[] = [
    '# ONT — rapport de build',
    '',
    `Vault : \`${VAULT}\``,
    '',
    '## Couverture',
    '',
    `- Slots au total : **${books.length}**`,
    `- Slots rédigés : **${written.length}**`,
    `- Unités : **${written.reduce((n, b) => n + b.chapters.length, 0)}** chapitres, ` +
      `**${written.filter((b) => b.intro).length}** feuilles d'introduction`,
    `- Versets : **${written.reduce(
      (n, b) => n + b.chapters.reduce((m, c) => m + c.verseCount, 0),
      0,
    )}**`,
    '',
    '| Livre | Slot | Verrouillés | Brouillons | Intro | Versets |',
    '|---|---:|---:|---:|:-:|---:|',
  ];

  for (const book of written) {
    const locked = book.chapters.filter((c) => c.status === 'locked').length;
    const drafts = book.chapters.filter((c) => c.status === 'brouillon').length;
    const verses = book.chapters.reduce((n, c) => n + c.verseCount, 0);
    lines.push(
      `| *${book.title}* | ${book.slot} | ${locked} | ${drafts} | ` +
        `${book.intro ? '✓' : '—'} | ${verses} |`,
    );
  }

  const used = glossary.filter((entry) => entry.count > 0);
  lines.push(
    '',
    '## Glossaire',
    '',
    `- Entrées : **${glossary.length}** — dont **${glossary.filter((e) => e.tagged).length}** ` +
      'intraduisibles balisés (cibles d\'appui long)',
    `- Entrées attestées dans le corpus rédigé : **${used.length}**`,
    '',
    '### Les vingt intraduisibles les plus présents',
    '',
    'La ventilation dit quelque chose du corpus : un terme qui pèse surtout dans les',
    'gloses est un terme encore en cours de fondation — on l\'explique plus souvent',
    "qu'il ne paraît. Un terme qui pèse dans le corps est acquis.",
    '',
    '| Terme | Hébreu | Corps | Gloses | Total | Premier emploi |',
    '|---|---|---:|---:|---:|---|',
  );

  for (const entry of [...used].sort((a, b) => b.count - a.count).slice(0, 20)) {
    lines.push(
      `| **${entry.title}** | ${entry.hebrew ?? '—'} | ${entry.bodyCount} | ` +
        `${entry.glossCount} | ${entry.count} | ${entry.firstUse ?? '—'} |`,
    );
  }

  const declaredUnused = glossary.filter((entry) => entry.tagged && entry.count === 0);
  if (declaredUnused.length) {
    lines.push(
      '',
      '### Intraduisibles déclarés mais encore absents du corpus',
      '',
      "Rien d'anormal — ces termes attendent le livre qui les emploiera.",
      '',
      declaredUnused.map((entry) => `**${entry.title}**`).join(' · '),
    );
  }

  if (unknown.size) {
    const lemmas = glossary.map((entry) => entry.lemma);
    const rows = [...unknown]
      .map(([slug, info]) => ({ slug, info, guess: guessLemma(slug, lemmas) }))
      .sort((a, b) => b.info.count - a.info.count);

    lines.push(
      '',
      '## Formes en gras absentes du glossaire',
      '',
      'Le §2.5 réserve `**…**` *exclusivement* aux intraduisibles : le gras déclenche le',
      "style « Transliteration » d'Affinity au copier-coller. Chaque forme ci-dessous est",
      "donc soit un intraduisible à déclarer, soit du gras à retirer. La colonne « piste »",
      'est indicative — elle propose un lemme connu dont la forme pourrait dériver.',
      '',
      '| Forme | Occ. | Où | Piste | Contexte |',
      '|---|---:|---|---|---|',
    );

    for (const { info, guess } of rows) {
      const context = info.sample.replace(/\|/g, '\\|');
      lines.push(
        `| \`${info.form}\` | ${info.count} | ${info.where} | ` +
          `${guess ? `dérivé de **${guess}** ?` : '—'} | ${context} |`,
      );
    }
  }

  if (issues.length) {
    const byFile = new Map<string, Issue[]>();
    for (const issue of issues) {
      byFile.set(issue.file, [...(byFile.get(issue.file) ?? []), issue]);
    }
    lines.push('', '## Marqueurs déséquilibrés', '');
    for (const [file, list] of byFile) {
      lines.push(`- \`${file}\``);
      for (const issue of list) lines.push(`  - ligne ${issue.line} — ${issue.message}`);
    }
  }

  if (superseded.length) {
    lines.push(
      '',
      '## Unités verrouillées masquées par un brouillon',
      '',
      ...superseded.map((file) => `- \`${file}\``),
    );
  }

  return lines.join('\n') + '\n';
}

async function main(): Promise<void> {
  const skeleton = await readTree(path.join(VAULT, SKELETON));
  if (!skeleton.length) {
    throw new Error(
      `Aucun slot trouvé sous ${path.join(VAULT, SKELETON)}. ` +
        'Vérifier ONT_VAULT, ou que le vault iCloud est bien descendu localement.',
    );
  }

  const reference = await readReference(VAULT, new Set(skeleton.map((book) => book.id)));
  const { chapters, issues, superseded } = await readChapters();

  const corpora = assemble(skeleton, chapters, reference.bookNames);
  const { occurrences, unknown } = indexOccurrences(
    chapters.values(),
    reference.glossary,
    reference.formIndex,
  );

  const books = corpora.flatMap((c) => c.modes.flatMap((m) => m.books));
  const written = books.filter((book) => !book.empty);

  await fs.rm(OUT, { recursive: true, force: true });

  let bytes = 0;
  bytes += await writeJson(path.join(OUT, 'corpus.json'), {
    schema: 1,
    corpora: corpora.map((corpus) => ({
      id: corpus.id,
      title: corpus.title,
      order: corpus.order,
      modes: corpus.modes.map((mode) => ({
        id: mode.id,
        title: mode.title,
        order: mode.order,
        books: mode.books.map(outline),
      })),
    })),
  });

  for (const book of written) {
    bytes += await writeJson(path.join(OUT, 'books', `${book.id}.json`), book);
  }

  bytes += await writeJson(path.join(OUT, 'glossary.json'), {
    schema: 1,
    entries: reference.glossary,
  });

  bytes += await writeJson(path.join(OUT, 'occurrences.json'), {
    schema: 1,
    byLemma: Object.fromEntries(occurrences),
  });

  // L'index de recherche : un enregistrement par verset, titre ou paragraphe.
  const searchRecords: SearchRecord[] = [];
  for (const book of written) {
    for (const unit of [book.intro, ...book.chapters].filter(Boolean) as Chapter[]) {
      searchRecords.push(...indexChapter(unit));
    }
  }
  bytes += await writeJson(path.join(OUT, 'search.json'), {
    schema: 1,
    records: searchRecords,
  });

  // ── Le vivier du verset du jour ────────────────────────────────────────
  //
  // Un fichier à part, et pas l'index de recherche : celui-ci range un texte
  // *replié* — minuscules, accents retirés — parfait pour chercher, illisible
  // pour afficher. Le widget, lui, a besoin du texte tel qu'on le lit.
  //
  // Il est petit et plat pour une raison précise : un widget iOS dispose d'une
  // trentaine de mégaoctets et doit se dessiner en quelques dizaines de
  // millisecondes. Y charger `books/bereshit.json` et ses 750 Ko d'arbre
  // d'inline le ferait tomber.
  const daily: DailyVerse[] = [];
  for (const book of written) {
    for (const unit of [book.intro, ...book.chapters].filter(Boolean) as Chapter[]) {
      // Seules les unités **verrouillées** : un brouillon ne fait pas
      // référence (§12) et n'a rien à faire sur un écran d'accueil. La règle
      // vit ici, dans la fabrique du vivier, et pas dans chacun des trois
      // endroits qui l'affichent — sinon elle finit appliquée à deux
      // endroits sur trois.
      if (unit.status !== 'locked') continue;
      for (const block of unit.blocks) {
        if (block.t !== 'verses') continue;
        for (const verse of block.verses) {
          // Le corps seul, sans l'appareil : un verset du jour se lit d'une
          // traite. Les gloses de l'ONT font parfois quarante mots.
          const text = tidy(plainText(verse.nodes)).trim();
          // Une fenêtre de longueur, et rien de plus savant. Trop court, le
          // verset est une amorce sans sens propre ; trop long, il déborde du
          // widget et arrive tronqué dans une notification.
          if (text.length < 110 || text.length > 300) continue;
          daily.push({
            b: book.id,
            c: unit.id,
            n: verse.n,
            r: `${unit.title}:${verse.n}`,
            t: text,
          });
        }
      }
    }
  }
  bytes += await writeJson(path.join(OUT, 'daily.json'), {
    schema: 1,
    verses: daily,
  });

  const stats: Manifest['stats'] = {
    books: books.length,
    booksWritten: written.length,
    chapters: written.reduce((n, book) => n + book.chapters.length, 0),
    intros: written.filter((book) => book.intro).length,
    verses: written.reduce(
      (n, book) => n + book.chapters.reduce((m, c) => m + c.verseCount, 0),
      0,
    ),
    glossaryEntries: reference.glossary.length,
    occurrences: [...occurrences.values()].reduce((n, list) => n + list.length, 0),
    unknownTerms: [...unknown.keys()].sort(),
    unusedEntries: reference.glossary
      .filter((entry) => entry.tagged && entry.count === 0)
      .map((entry) => entry.lemma),
  };

  bytes += await writeJson(path.join(OUT, 'manifest.json'), {
    schema: 1,
    generatedAt: new Date().toISOString(),
    vault: VAULT,
    stats,
  } satisfies Manifest);

  const report = formatReport(corpora, reference.glossary, issues, unknown, superseded);
  await fs.writeFile(path.join(OUT, 'report.md'), report, 'utf8');

  console.log(
    [
      `Corpus     ${stats.booksWritten}/${stats.books} slots rédigés`,
      `Unités     ${stats.chapters} chapitres + ${stats.intros} intros — ${stats.verses} versets`,
      `Glossaire  ${stats.glossaryEntries} entrées — ${stats.occurrences} occurrences indexées`,
      `Recherche  ${searchRecords.length} entrées indexées`,
      `Anomalies  ${stats.unknownTerms.length} termes inconnus, ${issues.length} marqueurs déséquilibrés`,
      `Sortie     ${path.relative(process.cwd(), OUT)} — ${(bytes / 1024).toFixed(0)} Ko`,
    ].join('\n'),
  );
}

await main();
