/**
 * La lecture du vault — l'arborescence *est* l'ordre canonique.
 *
 * Le `corpus-order.md` le dit : « l'IDE trie alphabétiquement — les préfixes
 * numériques forcent l'ordre fonctionnel ». On lit donc l'ordre dans les noms
 * de dossiers plutôt que de le redéclarer ici, ce qui garantit qu'ajouter un
 * slot dans le vault suffit à le voir apparaître dans la liseuse.
 *
 *   1. kenesset (le Rassemblement)/       ← corpus
 *     1. torah (la Fondation)/            ← mode
 *       01. bereshit (Genèse)/            ← livre
 *         bereshit-1.md                   ← unité ONT
 *
 * La profondeur varie : certains modes intercalent un conteneur (`44. eduyot`,
 * `15. trei-asar`, `49. igerot`). La règle est structurelle, pas nominale —
 * un dossier qui contient des dossiers est un conteneur, un dossier qui n'en
 * contient pas est un livre.
 */

import fs from 'node:fs/promises';
import path from 'node:path';

/** `01. bereshit (Genèse)` → ordre 1, id `bereshit`, étiquette `Genèse`. */
const SLOT = /^(\d+)\.\s*(.+?)\s*\((.+)\)\s*$/;

export interface SlotName {
  order: number;
  id: string;
  label: string;
}

export function parseSlotName(name: string): SlotName | null {
  const match = SLOT.exec(name);
  if (!match) return null;
  return {
    order: Number.parseInt(match[1]!, 10),
    id: match[2]!,
    label: match[3]!,
  };
}

/** Un livre repéré dans une arborescence, avec son chemin canonique. */
export interface VaultBook {
  id: string;
  slot: number;
  french: string;
  corpus: SlotName;
  mode: SlotName;
  /** Les conteneurs traversés, du plus large au plus étroit. */
  groups: SlotName[];
  /** Chemin absolu du dossier du livre. */
  dir: string;
  /** Noms de fichiers `.md` présents, triés. */
  files: string[];
}

async function subdirectories(dir: string): Promise<string[]> {
  const entries = await fs.readdir(dir, { withFileTypes: true });
  return entries
    .filter((entry) => entry.isDirectory() && !entry.name.startsWith('.'))
    .map((entry) => entry.name)
    .sort();
}

async function markdownFiles(dir: string): Promise<string[]> {
  const entries = await fs.readdir(dir, { withFileTypes: true });
  return entries
    .filter((entry) => entry.isFile() && entry.name.endsWith('.md'))
    .map((entry) => entry.name)
    .sort();
}

/**
 * Descend un dossier jusqu'aux livres.
 *
 * Un dossier qui contient des sous-dossiers est un conteneur — on continue.
 * Un dossier terminal est un livre, même vide (un slot non encore rédigé
 * n'existe qu'à travers son `.gitkeep`, et il doit apparaître dans la table
 * des matières).
 */
async function descend(
  dir: string,
  corpus: SlotName,
  mode: SlotName,
  groups: SlotName[],
  into: VaultBook[],
): Promise<void> {
  for (const name of await subdirectories(dir)) {
    const slot = parseSlotName(name);
    if (!slot) continue;

    const child = path.join(dir, name);
    const nested = await subdirectories(child);

    if (nested.length) {
      await descend(child, corpus, mode, [...groups, slot], into);
      continue;
    }

    into.push({
      id: slot.id,
      slot: slot.order,
      french: slot.label,
      corpus,
      mode,
      groups,
      dir: child,
      files: await markdownFiles(child),
    });
  }
}

/**
 * Parcourt une arborescence (`locked`, `brouillons` ou `in-writing`) et rend
 * tous les livres qu'elle contient.
 *
 * Une arborescence absente rend une liste vide plutôt qu'une erreur : le
 * vault peut légitimement n'avoir aucun brouillon.
 */
export async function readTree(root: string): Promise<VaultBook[]> {
  const books: VaultBook[] = [];

  let corpora: string[];
  try {
    corpora = await subdirectories(root);
  } catch {
    return books;
  }

  for (const corpusName of corpora) {
    const corpus = parseSlotName(corpusName);
    if (!corpus) continue;

    const corpusDir = path.join(root, corpusName);
    for (const modeName of await subdirectories(corpusDir)) {
      const mode = parseSlotName(modeName);
      if (!mode) continue;
      await descend(path.join(corpusDir, modeName), corpus, mode, [], books);
    }
  }

  return books;
}
