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
use std::collections::BTreeMap;
use std::sync::OnceLock;

use crate::schema::{Inline, PorteeDeLaReference, TermLevel};

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
            // Les apostrophes et les demi-anneaux rencontrés dans le vault :
            // droite, courbe, la modificatrice, puis **les deux vrais signes
            // savants** — ʾ pour l'alef, ʿ pour le ayin.
            //
            // Ces deux-là manquaient, alors que le commentaire annonçait déjà
            // « la modificatrice qu'emploient les translittérations savantes ».
            // L'intention y était, les caractères non : `ʾ` est U+02BE et `ʿ`
            // est U+02BF, pas U+02BC.
            //
            // Ce qu'ils coûtaient : tombant dans le cas général, ils devenaient
            // un tiret. `malʾakh` aurait donné le lemme `mal-akh` au lieu de
            // `malakh` — **tous les lemmes changés, tous les liens morts**, et
            // rien pour le dire puisque le slug reste bien formé.
            '\'' | '\u{2019}' | '\u{02BC}' | '\u{02BE}' | '\u{02BF}' => {}
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
                        // **Le parseur ne résout pas.** Il ne sait pas quelles
                        // fiches existent, ni lesquelles sont publiées ; la
                        // construction le sait. Trancher ici obligerait à le
                        // faire sans l'information.
                        cible: None,
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
        if c == b'*' && bytes.get(i + 1) == Some(&b'*') && bytes.get(i + 2) != Some(&b'*') {
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
        // ── `((cible|libellé))` — un renvoi d'une chuqqah vers une autre ──
        //
        // Posé **avant** le niveau 3, qui lit aussi une parenthèse ouvrante :
        // celui-ci exige de l'hébreu, un renvoi n'en a pas, donc les deux ne se
        // disputent rien. L'ordre n'est qu'une commodité de lecture.
        //
        // Détection **locale** : on ne cherche pas si la cible existe. Le vault
        // porte des renvois vers des chuqqot pas encore écrites, et les typer
        // d'après leur résolution les ferait sortir en `Shem` — la faute que la
        // marque à part existe pour éviter.
        if c == b'(' && bytes.get(i + 1) == Some(&b'(') {
            if let Some(rel) = src[i + 2..].find("))") {
                let end = i + 2 + rel;
                if end > i + 2 {
                    let brut = &src[i + 2..end];
                    let (cible, libelle) = match brut.split_once('|') {
                        Some((c, l)) => (c.trim(), l.trim()),
                        None => (brut.trim(), brut.trim()),
                    };
                    if !cible.is_empty() {
                        flush!();
                        out.push(Inline::Renvoi {
                            v: libelle.to_string(),
                            cible: slugify(cible),
                        });
                        i = end + 2;
                        continue;
                    }
                }
            }
        }

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

        // 4c. La référence — `*Genèse* 4:25`, `Bereshit 9:8`
        //
        // **Avant l'italique, et c'est tout le point.** Dans `*Genèse* 4:25`,
        // l'italique se ferme AVANT les chiffres : le cas 5 produirait un `Em`
        // puis un texte nu, et la référence sortirait coupée en deux.
        //
        // La branche ne mord que sur une majuscule ou une astérisque, et
        // seulement si la liste blanche connaît le nom — `*Pharaon* 4:25` a
        // exactement la même forme et n'en est pas une.
        if c == b'*' || c.is_ascii_uppercase() || c >= 0xC0 {
            if let Some(livres) = LIVRES.get() {
                if let Some(r) = detecter_une_reference(&src[i..], livres) {
                    flush!();
                    out.push(Inline::Reference {
                        v: r.texte,
                        livre: r.livre,
                        systeme: match r.systeme {
                            Systeme::Recu => "recu".to_string(),
                            Systeme::Ont => "ont".to_string(),
                        },
                        chapitre: r.chapitre,
                        // La détection rend deux `Option` parce qu'elle lit
                        // une forme de surface ; le schéma, lui, refuse
                        // l'état illégal. La conversion se fait ici, une fois.
                        portee: match (r.verset, r.dernier) {
                            (Some(premier), Some(dernier)) => {
                                PorteeDeLaReference::Plage { premier, dernier }
                            }
                            (Some(n), None) => PorteeDeLaReference::Verset { n },
                            _ => PorteeDeLaReference::Chapitre,
                        },
                        // **Nulle ici, et c'est le seul état possible.** La
                        // résolution demande la table des plages de tout le
                        // corpus, et l'on est en train de lire un chapitre :
                        // les autres n'existent pas encore. Elle est posée
                        // plus tard, par `renvois::resoudre_les_references`.
                        cible: None,
                    });
                    i += r.largeur;
                    continue;
                }
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

// ───────────────────────────────────────────────────────────────────────────
// La référence — `*Genèse* 4:25`, `Bereshit 9:8`, `*Genèse* 1:11-12`
// ───────────────────────────────────────────────────────────────────────────

/// Laquelle des deux numérotations une référence emploie.
///
/// Décision de l'auteur du 10 septembre 2026 : **le nom du livre le dit**.
/// `Genèse 9:25` est le verset 25 du chapitre 9 de la Genèse reçue ;
/// `Bereshit 9:8` est le verset ⁸ de l'unité ONT n° 9. Ce sont le même verset,
/// et la forme double est permise.
///
/// La règle ne signale pas l'exception — **elle supprime le cas d'exception**.
/// Une notation qui repose sur le contexte se lit juste tant qu'on connaît le
/// contexte ; un nom se lit seul.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Systeme {
    /// Le nom français — la numérotation des Bibles reçues.
    Recu,
    /// Le nom ONT — l'unité et sa numérotation propre, qui repart de ¹ (§2.2).
    Ont,
}

/// Une référence repérée dans le texte, **sans aucune résolution**.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReferenceDetectee {
    /// Le syntagme entier, tel qu'il s'affiche — italiques comprises.
    pub texte: String,
    /// Le nom du livre, sans les italiques.
    pub livre: String,
    pub systeme: Systeme,
    pub chapitre: u32,
    /// Absent sur `Genèse 3`, qui ne vise pas un verset.
    pub verset: Option<u32>,
    /// Présent sur une plage — `1:11-12`.
    pub dernier: Option<u32>,
    /// Longueur consommée dans la source, en octets.
    pub largeur: usize,
}

/// Les livres que la détection reconnaît, posés une fois par construction.
///
/// ## Pourquoi un registre global, et ce qu'il coûte
///
/// `parse_inline` est récursive et appelée de partout ; y faire passer la liste
/// en paramètre la ferait rippler dans tout le fichier et chez ses appelants,
/// pour une donnée qui **ne change jamais pendant une construction** — elle est
/// lue une fois dans les répertoires du §2.6.
///
/// Le prix est réel et il faut le nommer : un état global se teste mal, et deux
/// constructions dans le même processus se partageraient le registre. C'est
/// pourquoi `detecter_une_reference` prend la liste **en paramètre** et reste
/// pure — le global ne sert qu'au branchement, et les tests ne le touchent pas.
static LIVRES: OnceLock<BTreeMap<String, Systeme>> = OnceLock::new();

/// Déclare les livres pour toute la construction. Sans appel, aucune référence
/// n'est détectée — le texte reste tel quel, ce qui est le bon défaut : mieux
/// vaut ne rien poser que poser faux.
pub fn declarer_les_livres(livres: BTreeMap<String, Systeme>) {
    let _ = LIVRES.set(livres);
}

/// **Deux écritures du même renvoi, et le vault emploie les deux.**
///
/// `Bereshit 1:4` est la forme courte. Mais la prose du corpus écrit aussi
/// « écho délibéré de *Bereshit 1*, verset 2 » — le verset en toutes lettres,
/// après une virgule, parce que la phrase le dit plutôt qu'elle ne le note.
///
/// Le motif ne connaissait que la première. Le renvoi s'arrêtait donc au
/// chapitre, et « , verset 2 » restait du texte ordinaire à côté du lien :
/// à l'écran, l'ambre couvrait « Bereshit 1 » et le doigt n'avait aucun moyen
/// d'atteindre le verset 2. Relevé par l'auteur, capture à l'appui — « ici ça
/// risque pas de pouvoir me ramener à Bereshit 1:2, c'est pas correctement
/// agencé ». Quinze renvois du corpus sont dans ce cas.
///
/// `v.` et `vv.` entrent avec, parce qu'ils paraissent dans le même corpus et
/// disent la même chose.
static REFERENCE: Lazy<Regex> = Lazy::new(|| {
    Regex::new(concat!(
        r"^(\*?)([\p{Lu}][\p{L}\p{M}ʾʿ'’-]*(?: [\p{Lu}][\p{L}\p{M}ʾʿ'’-]*)*)(\*?)[  ]+(\d+)",
        r"(?::(\d+)(?:\s*[-–]\s*(\d+))?",
        r"|,?[  ]*(?:versets?|vv?\.)[  ]*(\d+)(?:\s*[-–]\s*(\d+))?)?"
    ))
    .unwrap()
});

/// Repère une référence **au début** de `src`, si la liste blanche la connaît.
///
/// ## Pourquoi une liste blanche, et pas un motif
///
/// C'est la leçon que le vault a payée trois fois en une journée : un balayage
/// par exclusion — « ce qui n'est pas du français » — a failli convertir
/// *Pharaon*, *Euphrate* et *orphelin*. **On énumère ce qu'on vise ; on ne
/// soustrait pas le reste.** Et une liste blanche ne protège que de ce qu'elle
/// exclut : c'est en y faisant entrer un mauvais nom qu'une passe a fondu deux
/// **Shemot** distincts.
///
/// ## Aucune résolution
///
/// Comme `Renvoi` : on type sur place, on ne cherche pas si la cible existe.
/// La grande majorité des renvois du corpus vise des livres **pas encore
/// écrits** — les typer sur leur cible les rendrait tous inertes, et il
/// faudrait tout reprendre à chaque livre traduit.
pub fn detecter_une_reference(
    src: &str,
    livres: &BTreeMap<String, Systeme>,
) -> Option<ReferenceDetectee> {
    let c = REFERENCE.captures(src)?;
    let livre = c.get(2)?.as_str().trim().to_string();
    let systeme = *livres.get(&livre)?;

    // Les italiques doivent s'apparier : `*Genèse 4:25` sans fermeture est une
    // emphase qui court, pas une référence — la laisser passer mangerait le
    // marqueur et déséquilibrerait la suite de la ligne.
    let ouvre = !c.get(1)?.as_str().is_empty();
    let ferme = !c.get(3)?.as_str().is_empty();
    if ouvre != ferme {
        return None;
    }

    let nombre = |n: usize| c.get(n).and_then(|m| m.as_str().parse::<u32>().ok());
    let tout = c.get(0)?;

    Some(ReferenceDetectee {
        texte: tout.as_str().to_string(),
        livre,
        systeme,
        chapitre: nombre(4)?,
        // Les deux écritures remplissent deux jeux de groupes, et une seule
        // branche du motif peut mordre : `or` les réunit sans qu'aucune
        // priorité n'ait à être décidée.
        verset: nombre(5).or_else(|| nombre(7)),
        dernier: nombre(6).or_else(|| nombre(8)),
        largeur: tout.len(),
    })
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
            // Un renvoi est du corps de texte au même titre qu'un Shem : la
            // phrase le nomme, l'éteindre laisserait un trou.
            // Une référence aussi : « comme en *Genèse* 4:25 » perd son sens
            // si le syntagme disparaît de l'extrait.
            Inline::Term { v, .. }
            | Inline::Shem { v, .. }
            | Inline::Renvoi { v, .. }
            | Inline::Reference { v, .. } => out.push_str(v),
            Inline::Heb { v } => {
                if options.level3 {
                    out.push_str(v);
                }
            }
            Inline::Translit {
                translit, hebrew, ..
            } => {
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
                Inline::Renvoi { .. } => "renvoi",
                Inline::Reference { .. } => "reference",
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

        let Inline::Translit {
            translit, hebrew, ..
        } = &nodes[2]
        else {
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
        assert_eq!(
            v, "Elohim",
            "l'astérisque de l'emphase n'appartient pas au terme"
        );
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

#[cfg(test)]
mod triple_asterisque {
    use super::*;

    /// **Trois astérisques ne sont pas un intraduisible**, et c'est ce que les
    /// pieds d'unité écrivent :
    ///
    ///     - ***Elohim** / אֱלֹהִים — laissé en hébreu*
    ///
    /// L'emphase prend la première astérisque, l'intraduisible les deux
    /// suivantes. Sans la garde, l'analyseur mordait au premier astérisque et
    /// capturait `*Elohim` comme **valeur** du terme : le mot d'or portait
    /// l'astérisque, et celle de fermeture restait orpheline en fin de ligne.
    ///
    /// Vingt-six mots de *Bereshit* étaient dans ce cas, et le défaut ne
    /// ressemblait nulle part à une panne — juste à une coquille du vault.
    #[test]
    fn l_italique_prend_la_premiere() {
        let rendu = parse_inline("***Elohim** / hébreu*");
        let texte = format!("{rendu:?}");
        assert!(
            !texte.contains("*Elohim"),
            "le nom du terme ne doit pas porter l'astérisque : {texte}"
        );
    }

    /// **Et quand l'italique ne se referme jamais ?**
    ///
    /// C'est le cas qu'une seconde correction, restée en attente, traitait en
    /// plus — en faisant retomber l'astérisque orpheline en texte. Mesuré :
    /// la correction retenue le tient déjà, sans le nommer.
    ///
    /// L'épreuve reste, précisément parce que personne ne l'avait écrite : ce
    /// qui tient par accident tient jusqu'à la prochaine retouche.
    #[test]
    fn une_italique_jamais_refermee_ne_mange_pas_le_terme() {
        let rendu = parse_inline("***Elohim** et rien ne referme");
        let texte = format!("{rendu:?}");
        assert!(
            !texte.contains("*Elohim"),
            "l'astérisque orpheline est entrée dans le terme : {texte}"
        );
    }
    /// **Les demi-anneaux savants disparaissent, ils ne deviennent pas des
    /// tirets.**
    ///
    /// `ʾ` (U+02BE, alef) et `ʿ` (U+02BF, ayin) remplacent l'apostrophe unique
    /// depuis le 8 septembre 2026 : celle-ci était visible et ambiguë — on
    /// voyait qu'il y avait une lettre sans pouvoir dire laquelle.
    ///
    /// Ils manquaient à `slugify`, donc ils tombaient dans le cas général et
    /// devenaient un tiret. `malʾakh` aurait donné `mal-akh` : **tous les
    /// lemmes changés, tous les liens morts**, et rien pour le dire puisque le
    /// slug reste bien formé.
    #[test]
    fn les_demi_anneaux_savants_ne_coupent_pas_le_lemme() {
        assert_eq!(slugify("malʾakh"), "malakh");
        assert_eq!(slugify("Kenaʿan"), "kenaan");
        assert_eq!(slugify("Gevurot ha-Neviʾim"), "gevurot-ha-neviim");
    }

    /// Et les trois apostrophes d'avant continuent de disparaître — sans quoi
    /// le vault, qui n'est pas converti d'un coup, produirait deux lemmes pour
    /// le même mot pendant la transition.
    #[test]
    fn les_trois_apostrophes_tiennent_toujours() {
        assert_eq!(slugify("mal'akh"), "malakh");
        assert_eq!(slugify("mal\u{2019}akh"), "malakh");
        assert_eq!(slugify("mal\u{02BC}akh"), "malakh");
    }

    /// `((cible|libellé))` — un renvoi d'une chuqqah vers une autre.
    ///
    /// La marque est à part de `[[…]]` parce que ce dernier devient un `Shem`
    /// **sans regarder la cible** : le vault porte des renvois vers des
    /// porteurs pas encore écrits, et distinguer sur la cible ferait sortir en
    /// `Shem` tout renvoi vers une chuqqah non encore écrite — le cas le plus
    /// fréquent, puisque le corpus s'écrit.
    #[test]
    fn un_renvoi_ne_devient_pas_un_shem() {
        let n = parse_inline("voir ((l-olam-est-un-regard|L'olam est un regard)) plus loin");
        let renvoi = n
            .iter()
            .find_map(|x| match x {
                Inline::Renvoi { v, cible } => Some((v.clone(), cible.clone())),
                _ => None,
            })
            .expect("un renvoi est attendu");
        assert_eq!(renvoi.0, "L'olam est un regard");
        assert_eq!(renvoi.1, "l-olam-est-un-regard");
        assert!(
            !n.iter().any(|x| matches!(x, Inline::Shem { .. })),
            "aucun Shem ne doit naître d'une double parenthèse"
        );
    }

    /// Sans barre, la cible sert de libellé — même convention que `[[…]]`.
    #[test]
    fn un_renvoi_sans_libelle_prend_sa_cible() {
        let n = parse_inline("((yhwh-ha-maqom))");
        assert!(matches!(
            n.first(),
            Some(Inline::Renvoi { v, cible })
                if v == "yhwh-ha-maqom" && cible == "yhwh-ha-maqom"
        ));
    }

    /// **Le voisinage du niveau 3, qui lit aussi une parenthèse ouvrante.**
    ///
    /// `(*translittération* / hébreu)` exige de l'hébreu ; un renvoi n'en a
    /// pas. Les deux ne se disputent rien — et cette épreuve le tient, pour que
    /// personne ne les réordonne en croyant que l'ordre n'a pas d'importance.
    #[test]
    fn le_niveau_trois_reste_intact() {
        let n = parse_inline("le mot (*davar* / דָּבָר) ici");
        assert!(
            n.iter().any(|x| matches!(x, Inline::Translit { .. })),
            "le niveau 3 doit survivre à l'arrivée des doubles parenthèses"
        );
        assert!(!n.iter().any(|x| matches!(x, Inline::Renvoi { .. })));
    }

    /// Une parenthèse simple reste du texte : la marque exige les deux.
    #[test]
    fn une_parenthese_simple_reste_du_texte() {
        let n = parse_inline("une remarque (entre parenthèses) ordinaire");
        assert!(!n.iter().any(|x| matches!(x, Inline::Renvoi { .. })));
    }
}

#[cfg(test)]
mod tests_de_la_reference {
    use super::*;

    fn livres() -> BTreeMap<String, Systeme> {
        BTreeMap::from([
            ("Genèse".to_string(), Systeme::Recu),
            ("Ésaïe".to_string(), Systeme::Recu),
            ("Bereshit".to_string(), Systeme::Ont),
            ("Sefar Gibbaraya".to_string(), Systeme::Ont),
        ])
    }

    #[test]
    fn le_nom_du_livre_decide_de_la_numerotation() {
        //
        // La décision de l'auteur du 10 septembre, faite code : le même
        // chiffre ne désigne pas la même chose selon le nom qui le précède.
        let l = livres();
        let recu = detecter_une_reference("*Genèse* 9:25", &l).expect("une référence");
        assert_eq!(recu.systeme, Systeme::Recu);
        assert_eq!((recu.chapitre, recu.verset), (9, Some(25)));

        let ont = detecter_une_reference("Bereshit 9:8", &l).expect("une référence");
        assert_eq!(ont.systeme, Systeme::Ont);
        assert_eq!((ont.chapitre, ont.verset), (9, Some(8)));
    }

    #[test]
    fn la_reference_enjambe_la_fermeture_de_l_italique() {
        //
        // LE piège de l'étape. Dans `*Genèse* 4:25`, l'italique se ferme
        // AVANT les chiffres : le cas 5 de la grammaire produirait un `Em`
        // puis un texte nu, et la référence serait coupée en deux. La branche
        // doit donc passer avant lui, et consommer le syntagme entier.
        let r =
            detecter_une_reference("*Genèse* 4:25 — et Qayin", &livres()).expect("une référence");
        assert_eq!(r.texte, "*Genèse* 4:25");
        assert_eq!(r.largeur, "*Genèse* 4:25".len());
    }

    #[test]
    fn une_plage_et_un_chapitre_seul_se_lisent() {
        let l = livres();
        let plage = detecter_une_reference("*Genèse* 1:11-12", &l).expect("une plage");
        assert_eq!((plage.verset, plage.dernier), (Some(11), Some(12)));

        let seul = detecter_une_reference("*Genèse* 3", &l).expect("un chapitre");
        assert_eq!((seul.chapitre, seul.verset), (3, None));
    }

    #[test]
    fn un_nom_hors_liste_blanche_n_est_pas_une_reference() {
        //
        // La garde qui compte, et le vault l'a payée trois fois en un jour :
        // une passe par exclusion — « ce qui n'est pas du français » — a
        // failli convertir *Pharaon*, *Euphrate* et *orphelin*.
        //
        // `*Pharaon* 4:25` a exactement la forme d'une référence. Seule la
        // liste blanche l'en sépare.
        let l = livres();
        assert_eq!(detecter_une_reference("*Pharaon* 4:25", &l), None);
        assert_eq!(detecter_une_reference("*Euphrate* 2:14", &l), None);
        assert_eq!(detecter_une_reference("Memphis 1:1", &l), None);
    }

    #[test]
    fn un_nom_compose_se_lit_en_entier() {
        let r = detecter_une_reference("*Sefar Gibbaraya* 4:10", &livres()).expect("une référence");
        assert_eq!(r.livre, "Sefar Gibbaraya");
    }

    #[test]
    fn branchee_la_reference_sort_entiere_du_parseur() {
        //
        // Le seul test qui touche au registre global — il est posé une fois
        // pour tout le processus, donc un seul test peut le faire.
        //
        // Ce qu'il vérifie est le piège de l'étape : sans la branche 4c, le
        // cas de l'italique produirait `Em["Genèse"]` puis `Text[" 4:25"]`, et
        // la référence sortirait EN DEUX MORCEAUX.
        declarer_les_livres(livres());
        let noeuds = parse_inline("comme en *Genèse* 4:25 — et Qayin");
        let reference = noeuds.iter().find_map(|n| match n {
            Inline::Reference {
                v,
                livre,
                systeme,
                chapitre,
                portee,
                ..
            } => Some((
                v.clone(),
                livre.clone(),
                systeme.clone(),
                *chapitre,
                portee.clone(),
            )),
            _ => None,
        });
        assert_eq!(
            reference,
            Some((
                "*Genèse* 4:25".to_string(),
                "Genèse".to_string(),
                "recu".to_string(),
                4,
                PorteeDeLaReference::Verset { n: 25 }
            ))
        );
        // Et rien n'a été mangé autour.
        let entier: String = plain_text(&noeuds, PlainOptions::default());
        assert!(entier.contains("comme en"), "« {entier} »");
        assert!(entier.contains("et Qayin"), "« {entier} »");
    }

    #[test]
    fn un_italique_depareille_n_est_pas_une_reference() {
        //
        // `*Genèse 4:25` sans fermeture est une emphase qui court. La prendre
        // mangerait le marqueur et déséquilibrerait la suite de la ligne —
        // c'est le défaut des « trois astérisques » du cas 3, une branche plus
        // haut, qui laissait une astérisque orpheline s'imprimer.
        let l = livres();
        assert_eq!(detecter_une_reference("*Genèse 4:25", &l), None);
        assert_eq!(detecter_une_reference("Genèse* 4:25", &l), None);
    }
}
