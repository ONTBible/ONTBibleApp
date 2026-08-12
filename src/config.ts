import path from 'node:path';

/**
 * La racine du vault de l'ONT — le dépôt de la traduction.
 *
 * Il vivait dans iCloud Drive ; il en est sorti le 12 août 2026 pour être
 * versionné par git. iCloud synchronise le contenu d'un `.git` de façon
 * partielle et asynchrone, ce qui corrompt le dépôt — c'est une combinaison
 * connue pour casser.
 *
 * Le chemin est relatif à ce dépôt : les deux sont côte à côte sous
 * `ONTBible/`. Surchargeable par `ONT_VAULT` pour bâtir depuis un clone
 * ailleurs.
 */
export const VAULT =
  process.env.ONT_VAULT ??
  path.join(import.meta.dirname, '..', '..', 'ONTBibleTranslation');

/** Où le pipeline dépose ses données. */
export const OUT = process.env.ONT_OUT ?? path.join(import.meta.dirname, '..', 'dist');

/**
 * Les deux états du flux de validation (CLAUDE.md §12).
 *
 * `locked/` fait référence. `brouillons/` miroite exactement son arborescence
 * et **ne voyage pas** dans la distribution — mais le pipeline le lit quand
 * même, pour que la liseuse d'atelier puisse l'afficher et que le rapport de
 * build dise où en est le corpus.
 */
export const TREES = {
  locked: 'locked',
  brouillon: 'brouillons',
} as const;

/** L'arborescence vide des 70 slots — elle définit le squelette du corpus. */
export const SKELETON = 'in-writing';

/** Le document de référence : conventions, glossaire, répertoires de noms. */
export const REFERENCE = 'CLAUDE.md';

/**
 * Les titres d'affichage des corpus et des modes.
 *
 * Les dossiers portent des identifiants sans apostrophe ni majuscule
 * (`neviim`, `berit-hadashah`) parce qu'un nom de fichier doit rester sobre.
 * Ces quelques formes-là ne se déduisent pas mécaniquement de l'identifiant —
 * elles sont donc énoncées ici, et nulle part ailleurs.
 */
export const DISPLAY_NAMES: Record<string, string> = {
  kenesset: 'Kenesset',
  'berit-hadashah': 'Berit Hadashah',
  torah: 'Torah',
  neviim: "Nevi'im",
  ketouvim: 'Ketouvim',
  nistarot: 'Nistarot',
  besorot: 'Besorot',
  eduyot: 'Eduyot',
  'trei-asar': 'Trei Asar',
  igerot: 'Igerot',
  'igerot-lifnei-hahurban': 'Igerot lifnei haḤurban',
  'igerot-aharei-hahurban': 'Igerot aḥarei haḤurban',
};

/** Le titre d'affichage d'un identifiant, à défaut une mise en capitales. */
export function displayName(id: string): string {
  return (
    DISPLAY_NAMES[id] ??
    id
      .split('-')
      .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
      .join(' ')
  );
}
