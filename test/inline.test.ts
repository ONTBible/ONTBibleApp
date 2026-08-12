/**
 * Le tokeniseur inline, éprouvé sur des fragments réels du vault.
 *
 * Chaque cas est copié tel quel depuis un fichier verrouillé — c'est la seule
 * façon de vérifier qu'on gère la variance réelle du markdown ONT et non une
 * idée qu'on s'en fait.
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  parseInline,
  plainText,
  slugify,
  collectTerms,
  tidy,
  lintMarkers,
} from '../src/inline.ts';

test('les trois niveaux sont séparés, jamais aplatis', () => {
  // Bereshit 18:1, verrouillé.
  const nodes = parseInline(
    '**YHWH** se laissa voir (*vayera elav YHWH* / וַיֵּרָא אֵלָיו יְהוָה) ' +
      "*[niphal de *ra'ah* — l'initiative appartient à **YHWH**]* par lui.",
  );

  assert.deepEqual(
    nodes.map((n) => n.t),
    ['term', 'text', 'translit', 'text', 'gloss', 'text'],
  );

  const term = nodes[0]!;
  assert.equal(term.t === 'term' && term.v, 'YHWH');
  assert.equal(term.t === 'term' && term.lemma, 'yhwh');

  const translit = nodes[2]!;
  assert.equal(translit.t === 'translit' && translit.translit, 'vayera elav YHWH');
  assert.equal(translit.t === 'translit' && translit.hebrew, 'וַיֵּרָא אֵלָיו יְהוָה');
});

test('une glose garde ses italiques et ses intraduisibles imbriqués', () => {
  const nodes = parseInline("*[niphal de *ra'ah* — appartient à **YHWH**]*");
  const gloss = nodes[0]!;
  assert.equal(gloss.t, 'gloss');
  assert.ok(gloss.t === 'gloss');

  assert.deepEqual(
    gloss.children.map((n) => n.t),
    ['text', 'em', 'text', 'term'],
  );
});

test("un renvoi entre parenthèses n'est pas pris pour un niveau 3", () => {
  // Bereshit 18:4 — la parenthèse contient une barre oblique ET de l'hébreu,
  // mais ce n'est pas la forme `(*translit* / hébreu)`.
  const nodes = parseInline(
    "(*Bereshit* 12:6 — de *moreh* / מֹרֶה : celui qui enseigne, l'arbre-oracle)",
  );

  assert.ok(!nodes.some((n) => n.t === 'translit'), 'aucun niveau 3 ne doit être créé');
  assert.ok(nodes.some((n) => n.t === 'em'), 'le renvoi reste une italique');
  assert.ok(nodes.some((n) => n.t === 'heb'), "l'hébreu isolé est repéré comme tel");
});

test('les mots hébreux consécutifs restent une seule séquence RTL', () => {
  const nodes = parseInline('voici כָּל-הָאָרֶץ שֹׁפֵט la suite');
  const heb = nodes.filter((n) => n.t === 'heb');
  assert.equal(heb.length, 1, 'une seule séquence, pas un nœud par mot');
  assert.equal(heb[0]!.t === 'heb' && heb[0]!.v, 'כָּל-הָאָרֶץ שֹׁפֵט');
});

test('deux intraduisibles accolés restent deux termes', () => {
  // CLAUDE.md §2.5 : « s'écrit seul ou combiné : **Adonai** **YHWH** ».
  const nodes = parseInline('**Adonai** **YHWH**');
  const terms = collectTerms(nodes);
  assert.deepEqual(
    terms.map((t) => t.lemma),
    ['adonai', 'yhwh'],
  );
});

test('les formes se réduisent au lemme attendu', () => {
  assert.equal(slugify("mal'akh"), 'malakh');
  assert.equal(slugify("She'ol"), 'sheol');
  assert.equal(slugify('El Elyon'), 'el-elyon');
  assert.equal(slugify('ha-satan'), 'ha-satan');
  assert.equal(slugify("tov me'od"), 'tov-meod');
  assert.equal(slugify('Elohim'), slugify('elohim'));
  assert.equal(slugify("l'Être façonné du sol"), 'letre-faconne-du-sol');
});

test('le corps de lecture par défaut ne porte ni glose ni niveau 3', () => {
  const nodes = parseInline(
    '**YHWH** se laissa voir (*vayera* / וַיֵּרָא) *[niphal de *ra\'ah*]* par lui.',
  );

  assert.equal(tidy(plainText(nodes)), '**YHWH** se laissa voir par lui.'.replace(/\*\*/g, ''));
  assert.ok(plainText(nodes, { gloss: true }).includes('niphal'));
  assert.ok(plainText(nodes, { level3: true }).includes('וַיֵּרָא'));
});

test("l'espacement français est préservé quand on retire un niveau", () => {
  // Bereshit 1:5. Une fois le niveau 3 retiré, il reste des espaces doubles —
  // les resserrer ne doit pas emporter l'espace avant « : » ni avant « » ».
  const nodes = parseInline(
    'Elohim nomma la Lumière (*vayiqra* / וַיִּקְרָא) : **« Jour »** (*yom* / יוֹם).',
  );

  assert.equal(tidy(plainText(nodes)), 'Elohim nomma la Lumière : « Jour ».');
});

test('un marqueur non refermé ne jette pas et ne perd aucun mot', () => {
  // Un astérisque orphelin est une coquille du vault. Le contrat n'est pas de
  // deviner l'intention — c'est de rendre tout le texte lisible quand même.
  // (Le rapport de build signale ces déséquilibres, voir `lintMarkers`.)
  const nodes = parseInline('un **terme jamais refermé et *une italique ouverte');
  const rendered = plainText(nodes);

  for (const word of ['terme', 'jamais', 'refermé', 'une', 'italique', 'ouverte']) {
    assert.ok(rendered.includes(word), `« ${word} » doit survivre`);
  }
});

test('les marqueurs déséquilibrés sont signalés', () => {
  assert.deepEqual(lintMarkers('sain **terme** (*a* / א) *[glose *incise*]* fini'), []);
  assert.ok(lintMarkers('un **terme jamais refermé').length > 0);
  assert.ok(lintMarkers('une *[glose jamais refermée').length > 0);
});
