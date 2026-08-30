//! Le tokeniseur inline — le cœur du pipeline.
//!
//! Il transforme une ligne de markdown ONT en `Vec<Inline>`, en préservant les
//! trois niveaux du §2.1 au lieu de les aplatir en texte riche générique. C'est
//! ce qui permet à la liseuse d'offrir « gloses on/off », « hébreu on/off », et
//! le toucher sur un intraduisible.
//!
//! ## L'ordre de reconnaissance décide de tout
//!
//! Les marqueurs se chevauchent — `*[`, `(*`, `**`, `*` commencent tous par le
//! même caractère, ou presque. Cet ordre n'est donc pas un style, c'est la
//! grammaire :
//!
//! ```text
//! 1. *[ … ]*        la glose        avant l'italique — elle commence par `*`
//! 2. (* … * / …)    le niveau 3     avant l'italique — il commence par `(*`
//! 3. ** … **        l'intraduisible avant l'italique — `**` avant `*`
//! 3b. == … ==       l'accentuation
//! 4. [[ … ]]        le lien
//! 5. * … *          l'italique ordinaire
//! ```
//!
//! ## Il ne se plaint jamais
//!
//! Chaque motif retombe proprement en texte s'il ne se referme pas. Un fichier
//! mal formé produit du texte lisible, jamais une exception — c'est un vault
//! écrit à la main, et une coquille ne doit pas faire échouer un build entier.
//! Le signalement des coquilles est le travail de `lint_markers`, à part.
//!
//! ## Sur les indices
//!
//! Tout est indexé en **octets**, pas en caractères. C'est ce que Rust impose
//! sur `&str`, et c'est sans conséquence ici : les marqueurs cherchés sont tous
//! en ASCII, donc leurs positions tombent toujours sur une frontière de
//! caractère. Le contenu entre marqueurs, lui, n'est jamais découpé au milieu.

use once_cell::sync::Lazy;
use regex::Regex;

use crate::schema::{Inline, TermLevel};

/// L'écriture hébraïque, par sa propriété Unicode.
///
/// Elle couvre les consonnes, le niqqud et les te'amim — sans qu'aucun
/// caractère hébreu n'ait à figurer dans ce fichier.
static HEBREW_CHAR: Lazy<Regex> = Lazy::new(|| Regex::new(r"\p{Hebrew}").unwrap());

/// Des mots hébreux consécutifs, séparés par des espaces ou des tirets, sont
/// regroupés en une seule séquence — c'est l'unité de rendu RTL. Les découper
/// mot à mot inverserait leur ordre à l'affichage.
static HEBREW_RUN: Lazy<Regex> =
    Lazy::new(|| Regex::new(r"\p{Hebrew}+(?:[\s-]*\p{Hebrew}+)*").unwrap());

/// Les marques combinantes — diacritiques à retirer pour la mise en clé.
static COMBINING_MARK: Lazy<Regex> = Lazy::new(|| Regex::new(r"\p{M}").unwrap());

/// `(*translittération* / hébreu)` — le niveau 3.
///
/// La translittération ne peut pas contenir d'astérisque : le §2.5 exclut le
/// balisage à l'intérieur du niveau 3, ce qui rend la reconnaissance non
/// ambiguë. Un `(*Bereshit* 12:6 — …)` — un renvoi en italique dans une glose —
/// ne correspond pas, faute du séparateur ` / `.
static TRANSLIT: Lazy<Regex> =
    Lazy::new(|| Regex::new(r"^\(\*([^*\n]+?)\*\s*/\s*([^)\n]+?)\)").unwrap());

/// `[texte](cible)` — lien markdown.
static MD_LINK: Lazy<Regex> = Lazy::new(|| Regex::new(r"^\[([^\]\n]*)\]\(([^)\n]*)\)").unwrap());

/// Ce qu'un intraduisible ne peut pas être.
///
/// Le §2.5 réserve `**…**` *exclusivement* aux intraduisibles : un terme, pas
/// une proposition. Sans ce garde-fou, un astérisque orphelin — il y en a dans
/// les pieds de page du vault — apparierait deux marqueurs très éloignés et
/// avalerait une phrase entière dans un faux lemme.
const TERM_MAX_LENGTH: usize = 48;

static TERM_FORBIDDEN: Lazy<Regex> = Lazy::new(|| Regex::new(r"[.;!?]\s|\n").unwrap());

fn looks_like_term(value: &str) -> bool {
    !value.is_empty()
        // En **caractères** et non en octets : la borne de quarante-huit vaut
        // pour ce qu'on lit, pas pour ce qu'UTF-8 en fait. Un terme accentué
        // pèse plus d'octets que de lettres, et le compter en octets le
        // rejetterait plus tôt qu'un terme sans accent de même longueur.
        && value.chars().count() <= TERM_MAX_LENGTH
        && !TERM_FORBIDDEN.is_match(value)
        && !slugify(value).is_empty()
}

/// Réduit une forme balisée à sa clé de jointure avec le glossaire.
///
/// Les apostrophes tombent — `mal'akh` → `malakh`, `She'ol` → `sheol` — parce
/// qu'elles appartiennent à la translittération et non au terme ; les
/// diacritiques français tombent aussi. Le reste devient des tirets, ce qui
/// garde distincts les termes composés : `el-elyon`, `ha-satan`, `tov-meod`.
pub fn slugify(input: &str) -> String {
    // Décomposition canonique, puis retrait des marques : c'est ce que fait
    // `normalize('NFD')` en JavaScript. Sans dépendance ICU, on se contente de
    // décomposer les latins accentués, seul cas qui se présente dans le vault.
    let decompose = decomposer(input);
    let sans_marques = COMBINING_MARK.replace_all(&decompose, "");
    let minuscules = sans_marques.to_lowercase();

    let mut out = String::with_capacity(minuscules.len());
    let mut tiret_en_attente = false;
    for c in minuscules.chars() {
        match c {
            // Les trois apostrophes rencontrées dans le vault — droite,
            // courbe, et la modificatrice qu'emploient les translittérations
            // savantes.
            '\'' | '\u{2019}' | '\u{02BC}' => {}
            c if c.is_ascii_alphanumeric() => {
                if tiret_en_attente && !out.is_empty() {
                    out.push('-');
                }
                tiret_en_attente = false;
                out.push(c);
            }
            _ => tiret_en_attente = true,
        }
    }
    out
}

/// Décompose une chaîne en forme canonique NFD.
///
/// C'est ce que fait `normalize('NFD')` en JavaScript : chaque caractère
/// précomposé devient sa lettre de base suivie de ses marques combinantes, que
/// l'appelant retire ensuite.
///
/// ## Une table écrite à la main ne suffit pas
///
/// La première version en était une, justifiée par « le vault est en français,
/// les seuls diacritiques sont ceux-là ». C'était faux, et le portage l'a
/// prouvé : sur 2,1 Mo de sortie, deux enregistrements divergeaient — un `š` de
/// translittération savante, et un `≠` d'un commentaire de traduction. Le
/// second est le plus instructif : il se décompose en `=` suivi d'une barre
/// oblique combinante, ce qu'aucune table de lettres accentuées n'aurait prévu.
///
/// Une normalisation partielle est une normalisation fausse. Elle ne se
/// trompe que sur les caractères auxquels on n'a pas pensé — c'est-à-dire
/// exactement ceux qui posent problème.
pub(crate) fn decomposer_public(input: &str) -> String {
    decomposer(input)
}

fn decomposer(input: &str) -> String {
    use unicode_normalization::UnicodeNormalization;
    input.nfd().collect()
}

/// Vrai si la chaîne porte au moins un caractère d'écriture hébraïque.
pub fn has_hebrew(input: &str) -> bool {
    HEBREW_CHAR.is_match(input)
}

/// La première séquence en écriture hébraïque d'un texte.
///
/// Sert à récupérer le titre hébreu d'un terme que le §2.5 énonce en passant —
/// « les éveillés, les gardiens (עִירִין) » — quand aucune table du §3 ne le
/// donne.
pub fn extract_hebrew(input: &str) -> Option<String> {
    HEBREW_RUN.find(input).map(|m| m.as_str().to_string())
}

/// Découpe un fragment de texte nu en alternant latin et hébreu.
fn split_scripts(text: &str) -> Vec<Inline> {
    if !has_hebrew(text) {
        return if text.is_empty() {
            Vec::new()
        } else {
            vec![Inline::Text {
                v: text.to_string(),
            }]
        };
    }

    let mut out = Vec::new();
    let mut last = 0;
    for m in HEBREW_RUN.find_iter(text) {
        if m.start() > last {
            out.push(Inline::Text {
                v: text[last..m.start()].to_string(),
            });
        }
        out.push(Inline::Heb {
            v: m.as_str().to_string(),
        });
        last = m.end();
    }
    if last < text.len() {
        out.push(Inline::Text {
            v: text[last..].to_string(),
        });
    }
    out
}

/// Trouve le `]*` qui referme une glose ouverte en `*[`.
///
/// On compte la profondeur des crochets : une glose peut en contenir — renvois,
/// incises — et seul le crochet de profondeur nulle suivi d'un astérisque
/// referme réellement.
fn find_gloss_end(src: &[u8], from: usize) -> Option<usize> {
    let mut depth = 1;
    let mut i = from;
    while i < src.len() {
        match src[i] {
            b'[' => depth += 1,
            b']' => {
                depth -= 1;
                if depth == 0 {
                    return if src.get(i + 1) == Some(&b'*') {
                        Some(i)
                    } else {
                        None
                    };
                }
            }
            _ => {}
        }
        i += 1;
    }
    None
}

/// Trouve l'astérisque qui referme une italique.
///
/// Un `**` rencontré en chemin est un intraduisible imbriqué : on l'enjambe
/// plutôt que de le prendre pour la fermeture.
fn find_em_end(src: &[u8], from: usize) -> Option<usize> {
    let mut i = from;
    while i < src.len() {
        if src[i] != b'*' {
            i += 1;
            continue;
        }
        if src.get(i + 1) == Some(&b'*') {
            i += 2;
            continue;
        }
        return if i > from { Some(i) } else { None };
    }
    None
}

/// Parse une ligne de markdown ONT en arbre inline.
///
/// Le texte reçu ne doit pas contenir de saut de ligne : les blocs sont
/// recollés en amont, ce qui garantit qu'aucun marqueur n'a à franchir une
/// frontière de ligne.
pub fn parse_inline(src: &str) -> Vec<Inline> {
    let bytes = src.as_bytes();
    let mut out: Vec<Inline> = Vec::new();
    let mut buffer = String::new();
    let mut i = 0usize;

    macro_rules! flush {
        () => {
            if !buffer.is_empty() {
                out.extend(split_scripts(&buffer));
                buffer.clear();
            }
        };
    }

    while i < bytes.len() {
        let c = bytes[i];

        // 1. La glose — `*[ … ]*`
        if c == b'*' && bytes.get(i + 1) == Some(&b'[') {
            if let Some(end) = find_gloss_end(bytes, i + 2) {
                flush!();
                out.push(Inline::Gloss {
                    children: parse_inline(&src[i + 2..end]),
                });
                i = end + 2;
                continue;
            }
        }

        // 2. Le niveau 3 — `(*translittération* / hébreu)`
        if c == b'(' {
            if let Some(m) = TRANSLIT.captures(&src[i..]) {
                let hebrew = m.get(2).unwrap().as_str();
                // L'hébreu doit être réellement en écriture hébraïque : c'est
                // ce qui écarte les parenthèses ordinaires porteuses d'une
                // barre oblique.
                if has_hebrew(hebrew) {
                    flush!();
                    out.push(Inline::Translit {
                        translit: m.get(1).unwrap().as_str().trim().to_string(),
                        hebrew: hebrew.trim().to_string(),
                    });
                    i += m.get(0).unwrap().len();
                    continue;
                }
            }
        }

        // 3. L'intraduisible — `** … **`
        //
        // **Trois astérisques ne sont pas un intraduisible.** `***Elohim**`
        // ouvre une emphase *puis* un intraduisible — c'est ce qu'écrivent les
        // pieds d'unité : « `- ***Elohim** / אֱלֹהִים — laissé en hébreu*` ».
        //
        // Sans cette garde, la branche mordait au **premier** astérisque,
        // cherchait le `**` suivant, et capturait `*Elohim` comme **valeur**
        // du terme. Le lemme, lui, restait juste — `slugify` écarte
        // l'astérisque —, donc la fiche s'ouvrait bien : seul l'affichage était
        // atteint. L'astérisque de fermeture de l'emphase, restée orpheline,
        // s'imprimait telle quelle en fin de ligne.
        //
        // Le défaut se voyait dans les trois consommateurs du corpus, et nulle
        // part il ne ressemblait à une panne — juste à une coquille du vault.
        //
        // On laisse donc l'emphase prendre le premier : `find_em_end` saute
        // déjà les paires `**`, il a été écrit pour ce cas.
        if c == b'*'
            && bytes.get(i + 1) == Some(&b'*')
            && bytes.get(i + 2) != Some(&b'*')
        {
            if let Some(rel) = src[i + 2..].find("**") {
                let end = i + 2 + rel;
                if end > i + 2 {
                    let value = &src[i + 2..end];
                    if looks_like_term(value) {
                        flush!();
                        out.push(Inline::Term {
                            v: value.to_string(),
                            lemma: slugify(value),
                        });
                        i = end + 2;
                        continue;
                    }
                }
            }
            // Marqueur non appariable : il redevient du texte, et la suite de
            // la ligne se parse normalement.
            buffer.push_str("**");
            i += 2;
            continue;
        }

        // 3b. L'accentuation — `== … ==`
        //
        // **Après** l'intraduisible et avant l'emphase : une accentuation
        // peut contenir de l'emphase, l'inverse n'a pas de sens.
        if c == b'=' && bytes.get(i + 1) == Some(&b'=') {
            if let Some(rel) = src[i + 2..].find("==") {
                let end = i + 2 + rel;
                if end > i + 2 {
                    flush!();
                    out.push(Inline::Accentuation {
                        children: parse_inline(&src[i + 2..end]),
                    });
                    i = end + 2;
                    continue;
                }
            }
            buffer.push_str("==");
            i += 2;
            continue;
        }

        // 4a. Le Shem — `[[Nom]]`, le lien natif d'Obsidian
        //
        // ## La marque est le discriminant, pas la forme de la cible
        //
        // On aurait pu émettre un `Link` et laisser chaque liseuse reconnaître
        // un Shem à ce que son `href` n'a « ni schéma ni barre oblique ». C'est
        // une règle qui casse au premier cas particulier — et il y en a :
        // l'apostrophe de `Na'amah`, le composé de `Tuval-Qayin`, un jour un
        // renvoi interne écrit en relatif.
        //
        // Elle casserait de trois manières différentes, aussi, puisque trois
        // liseuses la referaient chacune de son côté. Mesuré avant de trancher :
        // le site classe extérieur tout `href` qui ne commence pas par son
        // adresse, et un Shem y devenait un lien souligné ouvrant un onglet neuf
        // vers une page inexistante.
        //
        // La syntaxe `[[…]]` **est** la marque du Shem. Rien à interpréter.
        //
        // ## Les vrais liens gardent la leur
        //
        // Les renvois s'écrivent `[texte](url)` — étape 4b — et le corpus n'en
        // compte que trois, tous vers l'extérieur. Les deux notations ne se
        // disputent rien.
        //
        // ## Une fiche absente ne dégrade pas
        //
        // Le Shem est émis même sans fiche. Le §2.10 veut qu'une fiche dise ce
        // qui reste à venir, et le vault porte des renvois vers des porteurs
        // pas encore écrits : ce sont des marques de travail à faire, pas des
        // erreurs. C'est au contrôle de les nommer, et il le fait — dégrader en
        // texte nu ferait disparaître la liste de ce qui manque.
        if c == b'[' && bytes.get(i + 1) == Some(&b'[') {
            if let Some(rel) = src[i + 2..].find("]]") {
                let end = i + 2 + rel;
                if end > i + 2 {
                    let target = &src[i + 2..end];
                    // `[[cible|libellé]]` — la cible joint, le libellé s'affiche.
                    let (cible, libelle) = match target.split_once('|') {
                        Some((c, l)) => (c.trim(), l.trim()),
                        None => (target.trim(), target.trim()),
                    };
                    if !cible.is_empty() {
                        flush!();
                        out.push(Inline::Shem {
                            v: libelle.to_string(),
                            lemma: slugify(cible),
                        });
                        i = end + 2;
                        continue;
                    }
                }
            }
        }

        // 4b. Le lien markdown — `[texte](cible)`
        if c == b'[' {
            if let Some(m) = MD_LINK.captures(&src[i..]) {
                flush!();
                out.push(Inline::Link {
                    href: m.get(2).unwrap().as_str().to_string(),
                    children: parse_inline(m.get(1).unwrap().as_str()),
                });
                i += m.get(0).unwrap().len();
                continue;
            }
        }

        // 5. L'italique ordinaire — `* … *`
        if c == b'*' {
            if let Some(end) = find_em_end(bytes, i + 1) {
                flush!();
                out.push(Inline::Em {
                    children: parse_inline(&src[i + 1..end]),
                });
                i = end + 1;
                continue;
            }
        }

        // Un caractère ordinaire. On avance d'un **caractère** entier, jamais
        // d'un octet : couper au milieu d'un caractère multi-octets
        // produirait de l'UTF-8 invalide.
        let largeur = largeur_du_caractere(bytes[i]);
        buffer.push_str(&src[i..i + largeur]);
        i += largeur;
    }

    flush!();
    out
}

/// La largeur en octets d'un caractère UTF-8, lue sur son premier octet.
fn largeur_du_caractere(premier: u8) -> usize {
    match premier {
        0x00..=0x7F => 1,
        0xC0..=0xDF => 2,
        0xE0..=0xEF => 3,
        _ => 4,
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Projections — extraire une vue à plat d'un arbre inline
// ─────────────────────────────────────────────────────────────────────────────

/// Ce qu'on garde en aplatissant.
#[derive(Debug, Clone, Copy, Default)]
pub struct PlainOptions {
    /// Inclure les gloses (niveau 2). Faux par défaut — c'est la voix du projet.
    pub gloss: bool,
    /// Inclure l'hébreu et les translittérations (niveau 3). Faux par défaut.
    pub level3: bool,
}

/// Aplatit un arbre inline en texte nu.
///
/// Par défaut, ne rend que le **corps de la traduction** — le niveau 1 plus les
/// intraduisibles. C'est la vue qu'il faut pour un extrait de recherche ou un
/// partage de verset : la voix du texte, sans l'appareil.
pub fn plain_text(nodes: &[Inline], options: PlainOptions) -> String {
    let mut out = String::new();
    for node in nodes {
        match node {
            Inline::Text { v } => out.push_str(v),
            // Un Shem est du corps de texte : le nom **est** ce que la phrase
            // dit. L'éteindre laisserait un trou là où le lecteur attend un
            // sujet — au contraire de l'appareil, qu'on retire sans rien perdre.
            Inline::Term { v, .. } | Inline::Shem { v, .. } => out.push_str(v),
            Inline::Heb { v } => {
                if options.level3 {
                    out.push_str(v);
                }
            }
            Inline::Translit { translit, hebrew } => {
                if options.level3 {
                    out.push('(');
                    out.push_str(translit);
                    out.push_str(" / ");
                    out.push_str(hebrew);
                    out.push(')');
                }
            }
            Inline::Gloss { children } => {
                if options.gloss {
                    out.push('[');
                    out.push_str(&plain_text(children, options));
                    out.push(']');
                }
            }
            Inline::Accentuation { children } | Inline::Em { children } => {
                out.push_str(&plain_text(children, options));
            }
            Inline::Link { children, .. } => out.push_str(&plain_text(children, options)),
            Inline::Break => {}
        }
    }
    out
}

static ESPACES: Lazy<Regex> = Lazy::new(|| Regex::new(r"\s+").unwrap());
static AVANT_PONCTUATION: Lazy<Regex> = Lazy::new(|| Regex::new(r"\s+([,.\u{2026}])").unwrap());
static APRES_PARENTHESE: Lazy<Regex> = Lazy::new(|| Regex::new(r"\(\s+").unwrap());
static AVANT_PARENTHESE: Lazy<Regex> = Lazy::new(|| Regex::new(r"\s+\)").unwrap());
static DOUBLE_ESPACE: Lazy<Regex> = Lazy::new(|| Regex::new(r"\s{2,}").unwrap());

/// Normalise les espaces d'un texte aplati.
///
/// Retirer un niveau laisse des espaces doubles, qu'il faut resserrer. Mais on
/// ne touche **pas** à l'espace qui précède « : ; ! ? » ni au guillemet
/// fermant — la typographie française l'exige, et le corps du texte ONT le
/// porte déjà correctement. Le rabattre donnerait « la Lumière: « Jour» » au
/// lieu de « la Lumière : « Jour » ».
pub fn tidy(text: &str) -> String {
    let s = ESPACES.replace_all(text, " ");
    let s = AVANT_PONCTUATION.replace_all(&s, "$1");
    let s = APRES_PARENTHESE.replace_all(&s, "(");
    let s = AVANT_PARENTHESE.replace_all(&s, ")");
    let s = DOUBLE_ESPACE.replace_all(&s, " ");
    s.trim().to_string()
}

/// Repère les marqueurs déséquilibrés d'une ligne.
///
/// Le tokeniseur, lui, ne se plaint jamais : il rend toujours quelque chose de
/// lisible. Ce contrôle-ci existe pour que le build **signale** les coquilles du
/// vault au lieu de les absorber — un `**` orphelin fait basculer un mot
/// ordinaire dans le style « Transliteration » d'Affinity au copier-coller
/// (§2.5), et ça doit se voir.
pub fn lint_markers(line: &str) -> Vec<String> {
    let bytes = line.as_bytes();
    let (mut bold, mut gloss_open, mut gloss_close, mut em) = (0u32, 0u32, 0u32, 0u32);

    let mut i = 0usize;
    while i < bytes.len() {
        if bytes[i] != b'*' {
            i += 1;
            continue;
        }
        if bytes.get(i + 1) == Some(&b'[') {
            gloss_open += 1;
            i += 2;
        } else if bytes.get(i + 1) == Some(&b'*') {
            bold += 1;
            i += 2;
        } else if i > 0 && bytes[i - 1] == b']' {
            gloss_close += 1;
            i += 1;
        } else {
            em += 1;
            i += 1;
        }
    }

    let mut issues = Vec::new();
    if bold % 2 != 0 {
        issues.push("intraduisible `**` non refermé".to_string());
    }
    if gloss_open != gloss_close {
        issues.push("glose `*[ … ]*` non refermée".to_string());
    }
    if em % 2 != 0 {
        issues.push("italique `*` non refermée".to_string());
    }
    issues
}

/// Un intraduisible rencontré, avec le niveau où il l'a été.
#[derive(Debug, Clone, PartialEq)]
pub struct FoundTerm {
    pub v: String,
    pub lemma: String,
    pub level: TermLevel,
}

/// Collecte tous les nœuds `term` d'un arbre, dans l'ordre du texte.
pub fn collect_terms(nodes: &[Inline], level: TermLevel, into: &mut Vec<FoundTerm>) {
    for node in nodes {
        match node {
            Inline::Term { v, lemma } => into.push(FoundTerm {
                v: v.clone(),
                lemma: lemma.clone(),
                level,
            }),
            // Une glose fait basculer le niveau, et **ne revient jamais** :
            // un intraduisible cité dans une glose appartient au commentaire,
            // même s'il y est mis en emphase.
            Inline::Gloss { children } => collect_terms(children, TermLevel::Gloss, into),
            Inline::Em { children }
            | Inline::Accentuation { children }
            | Inline::Link { children, .. } => collect_terms(children, level, into),
            _ => {}
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn le_shem_naît_de_la_marque_obsidian() {
        let n = parse_inline("Et [[Qayin]] connut sa femme");
        assert_eq!(types(&n), ["text", "shem", "text"]);
        match &n[1] {
            Inline::Shem { v, lemma } => {
                assert_eq!(v, "Qayin");
                assert_eq!(lemma, "qayin");
            }
            autre => panic!("attendu un Shem, obtenu {autre:?}"),
        }
    }

    #[test]
    fn le_shem_garde_la_casse_et_normalise_la_clé() {
        // `v` s'affiche, `lemma` joint — et la clé passe par la même
        // normalisation que les intraduisibles : l'apostrophe tombe.
        let n = parse_inline("[[Na'amah]]");
        match &n[0] {
            Inline::Shem { v, lemma } => {
                assert_eq!(v, "Na'amah");
                assert_eq!(lemma, "naamah");
            }
            autre => panic!("attendu un Shem, obtenu {autre:?}"),
        }
    }

    #[test]
    fn le_composé_reste_distinct() {
        // `Tuval-Qayin` ne doit pas se confondre avec `Tuval` ni avec `Qayin` :
        // le tiret est porteur, comme pour `el-elyon`.
        match &parse_inline("[[Tuval-Qayin]]")[0] {
            Inline::Shem { lemma, .. } => assert_eq!(lemma, "tuval-qayin"),
            autre => panic!("attendu un Shem, obtenu {autre:?}"),
        }
    }

    #[test]
    fn le_libellé_s_affiche_et_la_cible_joint() {
        match &parse_inline("[[Qayin|son frère]]")[0] {
            Inline::Shem { v, lemma } => {
                assert_eq!(v, "son frère");
                assert_eq!(lemma, "qayin");
            }
            autre => panic!("attendu un Shem, obtenu {autre:?}"),
        }
    }

    #[test]
    fn le_renvoi_markdown_reste_un_lien() {
        // Les deux notations ne se disputent rien : `[[…]]` est un Shem,
        // `[texte](url)` est un renvoi. Le corpus en compte trois, tous
        // extérieurs.
        let n = parse_inline("voir [la source](https://example.org)");
        assert_eq!(types(&n), ["text", "link"]);
    }

    #[test]
    fn le_shem_est_du_corps_de_texte() {
        // Il ne s'éteint pas avec l'appareil : le nom **est** ce que la phrase
        // dit, et l'ôter laisserait la phrase sans sujet.
        let n = parse_inline("[[Qayin]] bâtit une ville");
        let nu = plain_text(&n, PlainOptions::default());
        assert_eq!(nu, "Qayin bâtit une ville");
    }

    /// Le type d'un nœud, en un mot — pour comparer des formes d'arbre sans
    /// écrire la structure entière.
    fn types(nodes: &[Inline]) -> Vec<&'static str> {
        nodes
            .iter()
            .map(|n| match n {
                Inline::Text { .. } => "text",
                Inline::Term { .. } => "term",
                Inline::Translit { .. } => "translit",
                Inline::Heb { .. } => "heb",
                Inline::Gloss { .. } => "gloss",
                Inline::Accentuation { .. } => "accentuation",
                Inline::Em { .. } => "em",
                Inline::Shem { .. } => "shem",
                Inline::Link { .. } => "link",
                Inline::Break => "break",
            })
            .collect()
    }

    #[test]
    fn les_trois_niveaux_sont_separes_jamais_aplatis() {
        // Bereshit 18:1, verrouillé.
        let nodes = parse_inline(
            "**YHWH** se laissa voir (*vayera elav YHWH* / וַיֵּרָא אֵלָיו יְהוָה) \
             *[niphal de *ra'ah* — l'initiative appartient à **YHWH**]* par lui.",
        );

        assert_eq!(
            types(&nodes),
            ["term", "text", "translit", "text", "gloss", "text"]
        );

        let Inline::Term { v, lemma } = &nodes[0] else {
            panic!("le premier nœud doit être un intraduisible")
        };
        assert_eq!(v, "YHWH");
        assert_eq!(lemma, "yhwh");

        let Inline::Translit { translit, hebrew } = &nodes[2] else {
            panic!("le troisième nœud doit être un niveau 3")
        };
        assert_eq!(translit, "vayera elav YHWH");
        assert_eq!(hebrew, "וַיֵּרָא אֵלָיו יְהוָה");
    }

    #[test]
    fn une_glose_garde_ses_italiques_et_ses_intraduisibles() {
        let nodes = parse_inline("*[niphal de *ra'ah* — appartient à **YHWH**]*");
        let Inline::Gloss { children } = &nodes[0] else {
            panic!("ce doit être une glose")
        };
        assert_eq!(types(children), ["text", "em", "text", "term"]);
    }

    /// Une emphase qui **enveloppe** un intraduisible — la forme des pieds
    /// d'unité.
    ///
    /// `- ***Elohim** / … *` : trois astérisques, deux grammaires imbriquées.
    /// La branche de l'intraduisible mordait au premier, capturait `*Elohim`
    /// comme lemme, et laissait l'astérisque de fermeture orpheline en fin de
    /// ligne — visible telle quelle dans les trois consommateurs du corpus.
    #[test]
    fn une_emphase_peut_envelopper_un_intraduisible() {
        let nodes = parse_inline("***Elohim** — laissé en hébreu*");

        assert_eq!(types(&nodes), ["em"], "toute la ligne est en emphase");

        let Inline::Em { children } = &nodes[0] else {
            panic!("attendu une emphase");
        };
        assert_eq!(types(children), ["term", "text"]);

        let Inline::Term { v, lemma } = &children[0] else {
            panic!("attendu un intraduisible");
        };
        assert_eq!(v, "Elohim", "l'astérisque de l'emphase n'appartient pas au terme");
        assert_eq!(lemma, "elohim");

        let rendu = plain_text(&nodes, PlainOptions::default());
        assert!(
            !rendu.contains('*'),
            "aucune astérisque ne doit survivre au rendu : {rendu}"
        );
    }

    /// Et l'intraduisible seul continue de marcher — la garde ne doit pas
    /// l'emporter avec elle.
    #[test]
    fn un_intraduisible_seul_reste_un_intraduisible() {
        let nodes = parse_inline("le **chesed** de YHWH");
        assert_eq!(types(&nodes), ["text", "term", "text"]);
    }

    #[test]
    fn un_renvoi_entre_parentheses_n_est_pas_un_niveau_3() {
        // Bereshit 18:4 — la parenthèse contient une barre oblique ET de
        // l'hébreu, mais ce n'est pas la forme `(*translit* / hébreu)`.
        let nodes = parse_inline(
            "(*Bereshit* 12:6 — de *moreh* / מֹרֶה : celui qui enseigne, l'arbre-oracle)",
        );
        assert!(!types(&nodes).contains(&"translit"), "aucun niveau 3");
        assert!(
            types(&nodes).contains(&"em"),
            "le renvoi reste une italique"
        );
        assert!(types(&nodes).contains(&"heb"), "l'hébreu isolé est repéré");
    }

    #[test]
    fn les_mots_hebreux_consecutifs_restent_une_sequence() {
        let nodes = parse_inline("voici כָּל-הָאָרֶץ שֹׁפֵט la suite");
        let hebreux: Vec<_> = nodes
            .iter()
            .filter_map(|n| match n {
                Inline::Heb { v } => Some(v.as_str()),
                _ => None,
            })
            .collect();
        assert_eq!(hebreux.len(), 1, "une seule séquence, pas un nœud par mot");
        assert_eq!(hebreux[0], "כָּל-הָאָרֶץ שֹׁפֵט");
    }

    #[test]
    fn deux_intraduisibles_accoles_restent_deux_termes() {
        // §2.5 : « s'écrit seul ou combiné : **Adonai** **YHWH** ».
        let nodes = parse_inline("**Adonai** **YHWH**");
        let mut trouves = Vec::new();
        collect_terms(&nodes, TermLevel::Body, &mut trouves);
        let lemmes: Vec<_> = trouves.iter().map(|t| t.lemma.as_str()).collect();
        assert_eq!(lemmes, ["adonai", "yhwh"]);
    }

    #[test]
    fn les_formes_se_reduisent_au_lemme_attendu() {
        assert_eq!(slugify("mal'akh"), "malakh");
        assert_eq!(slugify("She'ol"), "sheol");
        assert_eq!(slugify("El Elyon"), "el-elyon");
        assert_eq!(slugify("ha-satan"), "ha-satan");
        assert_eq!(slugify("tov me'od"), "tov-meod");
        assert_eq!(slugify("Elohim"), slugify("elohim"));
        assert_eq!(slugify("l'Être façonné du sol"), "letre-faconne-du-sol");
    }

    #[test]
    fn le_corps_par_defaut_ne_porte_ni_glose_ni_niveau_3() {
        let nodes = parse_inline(
            "**YHWH** se laissa voir (*vayera* / וַיֵּרָא) *[niphal de *ra'ah*]* par lui.",
        );
        assert_eq!(
            tidy(&plain_text(&nodes, PlainOptions::default())),
            "YHWH se laissa voir par lui."
        );
        assert!(plain_text(
            &nodes,
            PlainOptions {
                gloss: true,
                ..Default::default()
            }
        )
        .contains("niphal"));
        assert!(plain_text(
            &nodes,
            PlainOptions {
                level3: true,
                ..Default::default()
            }
        )
        .contains("וַיֵּרָא"));
    }

    #[test]
    fn l_espacement_francais_survit_au_retrait_d_un_niveau() {
        // Bereshit 1:5. Une fois le niveau 3 retiré, il reste des espaces
        // doubles — les resserrer ne doit pas emporter l'espace avant « : »
        // ni avant « » ».
        let nodes = parse_inline(
            "Elohim nomma la Lumière (*vayiqra* / וַיִּקְרָא) : **« Jour »** (*yom* / יוֹם).",
        );
        assert_eq!(
            tidy(&plain_text(&nodes, PlainOptions::default())),
            "Elohim nomma la Lumière : « Jour »."
        );
    }

    #[test]
    fn un_marqueur_non_referme_ne_perd_aucun_mot() {
        // Un astérisque orphelin est une coquille du vault. Le contrat n'est
        // pas de deviner l'intention — c'est de rendre tout le texte lisible.
        let nodes = parse_inline("un **terme jamais refermé et *une italique ouverte");
        let rendu = plain_text(&nodes, PlainOptions::default());
        for mot in ["terme", "jamais", "refermé", "une", "italique", "ouverte"] {
            assert!(rendu.contains(mot), "« {mot} » doit survivre");
        }
    }

    #[test]
    fn les_marqueurs_desequilibres_sont_signales() {
        assert!(lint_markers("sain **terme** (*a* / א) *[glose *incise*]* fini").is_empty());
        assert!(!lint_markers("un **terme jamais refermé").is_empty());
        assert!(!lint_markers("une *[glose jamais refermée").is_empty());
    }

    #[test]
    fn un_nom_propre_se_marque_jusque_dans_une_glose() {
        // Depuis la généralisation du §2.5 bis du vault, **tout** nom propre
        // porte `==…==` — corps du texte et gloses comprises. La glose est
        // reconnue avant l'accentuation dans l'ordre du tokeniseur ; c'est sa
        // récursion sur ses enfants qui rend le marquage possible dedans, et
        // rien ne le garantissait avant ce test.
        let nodes = parse_inline("les fils de ==Noach== *[dont ==Cham==, père de ==Kena'an==]*");

        let Inline::Accentuation { children } = &nodes[1] else {
            panic!("le nom propre du corps doit être une accentuation")
        };
        assert!(matches!(children.first(), Some(Inline::Text { v }) if v == "Noach"));

        let Some(Inline::Gloss { children }) =
            nodes.iter().find(|n| matches!(n, Inline::Gloss { .. }))
        else {
            panic!("la glose doit survivre")
        };
        let dedans: Vec<&str> = children
            .iter()
            .filter_map(|n| match n {
                Inline::Accentuation { children } => match children.first() {
                    Some(Inline::Text { v }) => Some(v.as_str()),
                    _ => None,
                },
                _ => None,
            })
            .collect();
        assert_eq!(
            dedans,
            vec!["Cham", "Kena'an"],
            "les deux noms propres de la glose doivent être marqués"
        );
    }

    #[test]
    fn une_accentuation_porte_des_enfants() {
        // Il peut contenir un intraduisible : l'aplatir perdrait le lien vers
        // sa fiche, en silence.
        let nodes = parse_inline("le ==nom de **YHWH**== est saint");
        let Inline::Accentuation { children } = &nodes[1] else {
            panic!("ce doit être une accentuation")
        };
        assert!(types(children).contains(&"term"));
    }
}
