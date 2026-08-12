/**
 * Le tokeniseur inline — le cœur du pipeline.
 *
 * Il transforme une ligne de markdown ONT en arbre `Inline[]`, en préservant
 * les trois niveaux du CLAUDE.md §2.1 au lieu de les aplatir en texte riche
 * générique. C'est ce qui permet à la liseuse d'offrir les interrupteurs
 * « gloses on/off » et « hébreu on/off », et l'appui long sur un
 * intraduisible.
 *
 * Ordre de reconnaissance — il compte, les marqueurs se chevauchent :
 *
 *   1. `*[ … ]*`        la glose        (avant l'italique : elle commence par `*`)
 *   2. `(* … * / …)`    le niveau 3     (avant l'italique : il commence par `(*`)
 *   3. `** … **`        l'intraduisible (avant l'italique : `**` avant `*`)
 *   4. `[[ … ]]`        le lien Obsidian
 *   5. `* … *`          l'italique ordinaire
 *
 * Chaque motif retombe proprement en texte s'il ne se referme pas — un
 * fichier mal formé produit du texte lisible, jamais une exception.
 */

import type { Inline } from './types.ts';

/**
 * L'écriture hébraïque, via la propriété Unicode `Script=Hebrew` : elle
 * couvre les consonnes, le niqqud (voyelles) et les te'amim (cantillation),
 * ainsi que le maqaf — sans qu'aucun caractère hébreu n'ait à figurer
 * littéralement dans ce fichier.
 */
const HEBREW_CHAR = /\p{Script=Hebrew}/u;

/**
 * Des mots hébreux consécutifs, séparés par des espaces ou des tirets, sont
 * regroupés en une seule séquence — c'est l'unité de rendu RTL : les
 * découper mot à mot inverserait leur ordre à l'affichage.
 */
const HEBREW_RUN = /\p{Script=Hebrew}+(?:[\s-]*\p{Script=Hebrew}+)*/gu;

/** Les marques combinantes — diacritiques à retirer pour la mise en clé. */
const COMBINING_MARK = /\p{M}/gu;

/**
 * `(*translittération* / הébreu)` — le niveau 3.
 *
 * La translittération ne peut pas contenir d'astérisque (le §2.5 exclut
 * explicitement le balisage à l'intérieur du niveau 3), ce qui rend la
 * reconnaissance non ambiguë. Un `(*Bereshit* 12:6 — …)` — un renvoi en
 * italique dans une glose — ne correspond pas, faute du séparateur ` / `.
 */
const TRANSLIT = /^\(\*([^*\n]+?)\*\s*\/\s*([^)\n]+?)\)/;

/** `[texte](cible)` — lien markdown. */
const MD_LINK = /^\[([^\]\n]*)\]\(([^)\n]*)\)/;

/**
 * Ce qu'un intraduisible ne peut pas être.
 *
 * Le §2.5 réserve `**…**` *exclusivement* aux intraduisibles : un terme, pas
 * une proposition. Sans ce garde-fou, un astérisque orphelin — il y en a dans
 * les pieds de page du vault — ferait apparier deux marqueurs très éloignés
 * et avalerait une phrase entière dans un faux lemme.
 *
 * Quand la borne est franchie, on rend les deux astérisques au texte et on
 * reprend juste après : le contenu se parse alors normalement, et le vrai
 * intraduisible qui suit sur la ligne est reconnu.
 */
const TERM_MAX_LENGTH = 48;
const TERM_FORBIDDEN = /[.;!?]\s|\n/;

function looksLikeTerm(value: string): boolean {
  return (
    value.length > 0 &&
    value.length <= TERM_MAX_LENGTH &&
    !TERM_FORBIDDEN.test(value) &&
    slugify(value).length > 0
  );
}

/**
 * Réduit une forme balisée à sa clé de jointure avec le glossaire.
 *
 * Les apostrophes tombent (`mal'akh` → `malakh`, `She'ol` → `sheol`) parce
 * qu'elles appartiennent à la translittération et non au terme ; les
 * diacritiques français tombent aussi. Le reste devient des tirets, ce qui
 * garde distincts les termes composés : `el-elyon`, `ha-satan`, `tov-meod`.
 */
export function slugify(input: string): string {
  return input
    .normalize('NFD')
    .replace(COMBINING_MARK, '')
    .toLowerCase()
    .replace(/['’ʼ]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

/** Vrai si la chaîne porte au moins un caractère d'écriture hébraïque. */
export function hasHebrew(input: string): boolean {
  return HEBREW_CHAR.test(input);
}

/**
 * La première séquence en écriture hébraïque d'un texte.
 *
 * Sert à récupérer le titre hébreu d'un terme que le §2.5 énonce en passant —
 * « les éveillés, les gardiens (עִירִין) » — quand aucune table du §3 ne le
 * donne.
 */
export function extractHebrew(input: string): string | null {
  HEBREW_RUN.lastIndex = 0;
  return HEBREW_RUN.exec(input)?.[0] ?? null;
}

/**
 * Découpe un fragment de texte nu en alternant les séquences latines et
 * hébraïques, pour que la liseuse sache où appliquer la fonte hébraïque et
 * basculer en RTL, sans avoir à refaire de la détection d'écriture.
 */
function splitScripts(text: string): Inline[] {
  if (!hasHebrew(text)) return text ? [{ t: 'text', v: text }] : [];

  const out: Inline[] = [];
  let last = 0;

  for (const match of text.matchAll(HEBREW_RUN)) {
    const start = match.index;
    if (start > last) out.push({ t: 'text', v: text.slice(last, start) });
    out.push({ t: 'heb', v: match[0] });
    last = start + match[0].length;
  }
  if (last < text.length) out.push({ t: 'text', v: text.slice(last) });
  return out;
}

/**
 * Trouve le `]*` qui referme une glose ouverte en `*[`.
 *
 * On compte la profondeur des crochets : une glose peut en contenir
 * (renvois, incises), et seul le crochet de profondeur nulle suivi d'un
 * astérisque referme réellement.
 */
function findGlossEnd(src: string, from: number): number {
  let depth = 1;
  for (let i = from; i < src.length; i++) {
    const c = src[i];
    if (c === '[') depth++;
    else if (c === ']') {
      depth--;
      if (depth === 0) return src[i + 1] === '*' ? i : -1;
    }
  }
  return -1;
}

/**
 * Trouve l'astérisque qui referme une italique.
 *
 * Un `**` rencontré en chemin est un intraduisible imbriqué : on l'enjambe
 * plutôt que de le prendre pour la fermeture.
 */
function findEmEnd(src: string, from: number): number {
  for (let i = from; i < src.length; i++) {
    if (src[i] !== '*') continue;
    if (src[i + 1] === '*') {
      i++;
      continue;
    }
    return i > from ? i : -1;
  }
  return -1;
}

/**
 * Parse une ligne de markdown ONT en arbre inline.
 *
 * Le texte reçu ne doit pas contenir de saut de ligne — les blocs sont
 * recollés en amont (voir `blocks.ts`), ce qui garantit qu'aucun marqueur
 * n'a à franchir une frontière de ligne.
 */
export function parseInline(src: string): Inline[] {
  const out: Inline[] = [];
  let buffer = '';
  let i = 0;

  const flush = (): void => {
    if (buffer) {
      out.push(...splitScripts(buffer));
      buffer = '';
    }
  };

  while (i < src.length) {
    const c = src[i];

    // 1. La glose — `*[ … ]*`
    if (c === '*' && src[i + 1] === '[') {
      const end = findGlossEnd(src, i + 2);
      if (end >= 0) {
        flush();
        out.push({ t: 'gloss', children: parseInline(src.slice(i + 2, end)) });
        i = end + 2;
        continue;
      }
    }

    // 2. Le niveau 3 — `(*translittération* / hébreu)`
    if (c === '(') {
      const m = TRANSLIT.exec(src.slice(i));
      // L'hébreu doit être réellement en écriture hébraïque : c'est ce qui
      // écarte les parenthèses ordinaires porteuses d'une barre oblique.
      if (m && hasHebrew(m[2]!)) {
        flush();
        out.push({ t: 'translit', translit: m[1]!.trim(), hebrew: m[2]!.trim() });
        i += m[0].length;
        continue;
      }
    }

    // 3. L'intraduisible — `** … **`
    if (c === '*' && src[i + 1] === '*') {
      const end = src.indexOf('**', i + 2);
      if (end > i + 2) {
        const value = src.slice(i + 2, end);
        if (looksLikeTerm(value)) {
          flush();
          out.push({ t: 'term', v: value, lemma: slugify(value) });
          i = end + 2;
          continue;
        }
      }
      // Marqueur non appariable : il redevient du texte, et la suite de la
      // ligne se parse normalement.
      buffer += '**';
      i += 2;
      continue;
    }

    // 3b. Le terme important — `== … ==`
    //
    // **Après** l'intraduisible et avant l'emphase : l'ordre de
    // reconnaissance est ce qui décide de tout dans ce tokeniseur, et un
    // terme important peut contenir de l'emphase, l'inverse n'a pas de sens.
    if (c === '=' && src[i + 1] === '=') {
      const end = src.indexOf('==', i + 2);
      if (end > i + 2) {
        flush();
        out.push({ t: 'important', children: parseInline(src.slice(i + 2, end)) });
        i = end + 2;
        continue;
      }
      // Marqueur orphelin : il redevient du texte, comme pour `**`.
      buffer += '==';
      i += 2;
      continue;
    }

    // 4a. Le lien Obsidian — `[[cible]]`
    if (c === '[' && src[i + 1] === '[') {
      const end = src.indexOf(']]', i + 2);
      if (end > i + 2) {
        const target = src.slice(i + 2, end);
        const [href, label] = target.split('|');
        flush();
        out.push({
          t: 'link',
          href: href!.trim(),
          children: parseInline((label ?? href!).trim()),
        });
        i = end + 2;
        continue;
      }
    }

    // 4b. Le lien markdown — `[texte](cible)`
    if (c === '[') {
      const m = MD_LINK.exec(src.slice(i));
      if (m) {
        flush();
        out.push({ t: 'link', href: m[2]!, children: parseInline(m[1]!) });
        i += m[0].length;
        continue;
      }
    }

    // 5. L'italique ordinaire — `* … *`
    if (c === '*') {
      const end = findEmEnd(src, i + 1);
      if (end >= 0) {
        flush();
        out.push({ t: 'em', children: parseInline(src.slice(i + 1, end)) });
        i = end + 1;
        continue;
      }
    }

    buffer += c;
    i++;
  }

  flush();
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// Projections — extraire une vue à plat d'un arbre inline
// ─────────────────────────────────────────────────────────────────────────────

export interface PlainOptions {
  /** Inclure les gloses (niveau 2). Faux par défaut — c'est la voix du projet. */
  gloss?: boolean;
  /** Inclure l'hébreu et les translittérations (niveau 3). Faux par défaut. */
  level3?: boolean;
}

/**
 * Aplatit un arbre inline en texte nu.
 *
 * Par défaut, ne rend que le **corps de la traduction** — le niveau 1 plus
 * les intraduisibles. C'est la vue qu'il faut pour un extrait de recherche ou
 * un partage de verset : la voix du texte, sans l'appareil.
 */
export function plainText(nodes: Inline[], options: PlainOptions = {}): string {
  let out = '';
  for (const node of nodes) {
    switch (node.t) {
      case 'text':
        out += node.v;
        break;
      case 'term':
        out += node.v;
        break;
      case 'heb':
        if (options.level3) out += node.v;
        break;
      case 'translit':
        if (options.level3) out += `(${node.translit} / ${node.hebrew})`;
        break;
      case 'gloss':
        if (options.gloss) out += `[${plainText(node.children, options)}]`;
        break;
      case 'important':
        out += plainText(node.children, options);
        break;
      case 'em':
      case 'link':
        out += plainText(node.children, options);
        break;
    }
  }
  return out;
}

/**
 * Normalise les espaces d'un texte aplati.
 *
 * Retirer un niveau laisse des espaces doubles, qu'il faut resserrer. Mais on
 * ne touche **pas** à l'espace qui précède « : ; ! ? » ni au guillemet
 * fermant — la typographie française l'exige, et le corps du texte ONT le
 * porte déjà correctement. Le rabattre donnerait « la Lumière: « Jour» »
 * au lieu de « la Lumière : « Jour » ».
 */
export function tidy(text: string): string {
  return text
    .replace(/\s+/g, ' ')
    .replace(/\s+([,.\u2026])/g, '$1')
    .replace(/\(\s+/g, '(')
    .replace(/\s+\)/g, ')')
    .replace(/\s{2,}/g, ' ')
    .trim();
}

/**
 * Repère les marqueurs déséquilibrés d'une ligne.
 *
 * Le tokeniseur, lui, ne se plaint jamais : il rend toujours quelque chose de
 * lisible. Ce contrôle-ci existe pour que le build sache *signaler* les
 * coquilles du vault au lieu de les absorber en silence — un `**` orphelin
 * fait basculer un mot ordinaire dans le style « Transliteration » d'Affinity
 * au copier-coller (CLAUDE.md §2.5), ce qui doit se voir.
 */
export function lintMarkers(line: string): string[] {
  let bold = 0;
  let glossOpen = 0;
  let glossClose = 0;
  let em = 0;

  for (let i = 0; i < line.length; i++) {
    if (line[i] !== '*') continue;
    if (line[i + 1] === '[') {
      glossOpen++;
      i++;
    } else if (line[i + 1] === '*') {
      bold++;
      i++;
    } else if (i > 0 && line[i - 1] === ']') {
      glossClose++;
    } else {
      em++;
    }
  }

  const issues: string[] = [];
  if (bold % 2 !== 0) issues.push('intraduisible `**` non refermé');
  if (glossOpen !== glossClose) issues.push('glose `*[ … ]*` non refermée');
  if (em % 2 !== 0) issues.push('italique `*` non refermée');
  return issues;
}

/**
 * Le niveau du texte où une forme a été rencontrée (CLAUDE.md §2.1).
 *
 * `body` : le corps de la traduction — ce que l'hébreu dit.
 * `gloss` : une glose — la voix du projet qui explicite l'implicite hébreu.
 *
 * La distinction n'est pas cosmétique : un intraduisible qui *paraît* dans le
 * texte et un intraduisible qui y est *expliqué* ne se cherchent pas de la
 * même façon. Les confondre reviendrait à aplatir les niveaux que tout l'ONT
 * s'emploie à tenir séparés.
 */
export type TermLevel = 'body' | 'gloss';

export interface FoundTerm {
  v: string;
  lemma: string;
  level: TermLevel;
}

/** Collecte tous les nœuds `term` d'un arbre, dans l'ordre du texte. */
export function collectTerms(
  nodes: Inline[],
  level: TermLevel = 'body',
  into: FoundTerm[] = [],
): FoundTerm[] {
  for (const node of nodes) {
    if (node.t === 'term') into.push({ v: node.v, lemma: node.lemma, level });
    else if (node.t === 'gloss') collectTerms(node.children, 'gloss', into);
    else if (node.t === 'em' || node.t === 'important' || node.t === 'link') {
      collectTerms(node.children, level, into);
    }
  }
  return into;
}
