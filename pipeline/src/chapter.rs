//! Le parseur d'unité ONT — un fichier `.md` du vault devient un `Chapter`.
//!
//! Une « unité » au sens du §2.3 : un bloc fonctionnel, qui se clôt quand une
//! fonction cosmique est accomplie — pas quand un numéro de chapitre biblique
//! change. Les feuilles d'introduction (§2.7) passent par le même chemin, avec
//! `kind: intro`.

use std::collections::BTreeSet;

use once_cell::sync::Lazy;
use regex::Regex;

use crate::blocks::parse_blocks;
use crate::inline::{collect_terms, lint_markers, parse_inline, plain_text, tidy, PlainOptions};
use crate::schema::{
    Block, Chapter, ChapterKind, Footer, Inline, Status, Subtitle, TermLevel, Verse,
};

/// Les exposants de la numérotation des versets (§2.2).
const SUPERSCRIPTS: [char; 10] = ['⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹'];

fn est_exposant(c: char) -> bool {
    SUPERSCRIPTS.contains(&c)
}

/// `¹⁰` → `10`.
fn super_to_int(run: &str) -> u32 {
    let mut chiffres = String::new();
    for c in run.chars() {
        if let Some(i) = SUPERSCRIPTS.iter().position(|s| *s == c) {
            chiffres.push_str(&i.to_string());
        }
    }
    chiffres.parse().unwrap_or(0)
}

/// Les séquences d'exposants d'un texte, avec leur position en octets.
fn sequences_d_exposants(texte: &str) -> Vec<(usize, usize, String)> {
    let mut out = Vec::new();
    let mut debut: Option<usize> = None;
    let mut courant = String::new();

    for (i, c) in texte.char_indices() {
        if est_exposant(c) {
            if debut.is_none() {
                debut = Some(i);
            }
            courant.push(c);
        } else if let Some(d) = debut.take() {
            out.push((d, d + courant.len(), std::mem::take(&mut courant)));
        }
    }
    if let Some(d) = debut {
        out.push((d, d + courant.len(), courant));
    }
    out
}

/// Découpe un paragraphe en versets, si c'en est un.
///
/// Un paragraphe du vault porte souvent plusieurs versets à la suite —
/// `³ Ils cherchèrent… ⁴ Car le sol…`. Rend `None` si le paragraphe ne commence
/// pas par un exposant : c'est alors de la prose, et l'y forcer inventerait des
/// versets là où l'auteur n'en a pas mis.
pub fn split_verses(nodes: &[Inline]) -> Option<Vec<Verse>> {
    let Some(Inline::Text { v }) = nodes.first() else {
        return None;
    };
    if !v.trim_start().starts_with(est_exposant) {
        return None;
    }

    let mut verses: Vec<Verse> = Vec::new();
    let mut current: Option<Verse> = None;

    for node in nodes {
        let Inline::Text { v } = node else {
            if let Some(c) = current.as_mut() {
                c.nodes.push(node.clone());
            }
            continue;
        };

        let mut last = 0usize;
        for (debut, fin, run) in sequences_d_exposants(v) {
            let avant = &v[last..debut];
            if !avant.is_empty() {
                if let Some(c) = current.as_mut() {
                    c.nodes.push(Inline::Text {
                        v: avant.to_string(),
                    });
                }
            }
            if let Some(c) = current.take() {
                verses.push(c);
            }
            current = Some(Verse {
                n: super_to_int(&run),
                nodes: Vec::new(),
            });
            last = fin;
        }

        let reste = &v[last..];
        if !reste.is_empty() {
            if let Some(c) = current.as_mut() {
                c.nodes.push(Inline::Text {
                    v: reste.to_string(),
                });
            }
        }
    }

    if let Some(c) = current {
        verses.push(c);
    }
    if verses.is_empty() {
        return None;
    }

    // Chaque verset s'ouvre sur l'espace qui suivait son exposant : on le
    // retire, sinon tout le corpus commencerait par une espace.
    for verse in &mut verses {
        let vide = match verse.nodes.first_mut() {
            Some(Inline::Text { v }) => {
                *v = v.trim_start().to_string();
                v.is_empty()
            }
            _ => false,
        };
        if vide {
            verse.nodes.remove(0);
        }
    }
    Some(verses)
}

/// Transforme les paragraphes versifiés en blocs de versets.
fn lift_verses(blocks: Vec<Block>) -> Vec<Block> {
    blocks
        .into_iter()
        .map(|block| match &block {
            Block::Para { nodes } => match split_verses(nodes) {
                Some(verses) => Block::Verses { verses },
                None => block,
            },
            _ => block,
        })
        .collect()
}

static PARENTHESES: Lazy<Regex> = Lazy::new(|| Regex::new(r"^\((.+)\)$").unwrap());

/// Lit le sous-titre de référence — `*(Genèse / בְּרֵאשִׁית 18:1-33)*`.
///
/// Le nom français n'est qu'un pont de navigation (§2.6) ; le renvoi biblique
/// est la **seule trace** de la numérotation d'origine, la numérotation ONT
/// repartant toujours de ¹ (§2.2).
pub fn parse_subtitle(block: &Block) -> Option<Subtitle> {
    let Block::Para { nodes } = block else {
        return None;
    };

    let brut = tidy(&plain_text(
        nodes,
        PlainOptions {
            level3: true,
            ..Default::default()
        },
    ));
    let inner = PARENTHESES.captures(&brut)?.get(1)?.as_str().to_string();
    let cut = inner.find(" / ")?;

    let french = inner[..cut].trim().to_string();
    let right = inner[cut + 3..].trim().to_string();

    // L'hébreu ne porte pas de chiffres arabes : le premier chiffre ouvre le
    // renvoi biblique, s'il y en a un. Une introduction n'en a pas — elle ne
    // recouvre aucun verset — et c'est le piège que `#[serde(default)]` ne
    // couvre pas côté liseuse : la clé est là, elle vaut `null`.
    let digit = right.char_indices().find(|(_, c)| c.is_ascii_digit());
    let (hebrew, reference) = match digit {
        None => (right.clone(), None),
        Some((i, _)) => {
            let r = right[i..].trim().to_string();
            (
                right[..i].trim().to_string(),
                if r.is_empty() { None } else { Some(r) },
            )
        }
    };

    Some(Subtitle {
        french,
        hebrew,
        reference,
    })
}

static VERSION: Lazy<Regex> = Lazy::new(|| Regex::new(r"(?i)version\s+([\d.]+)").unwrap());
static VERROUILLE: Lazy<Regex> = Lazy::new(|| Regex::new(r"(?i)verrouill").unwrap());
static PIED: Lazy<Regex> = Lazy::new(|| Regex::new(r"(?i)version|verrouill|à valider").unwrap());

/// Lit le pied de page — version, verrouillage, décisions terminologiques.
fn parse_footer(blocks: &[Block]) -> Option<Footer> {
    if blocks.is_empty() {
        return None;
    }

    let texte = blocks
        .iter()
        .map(|b| match b {
            Block::Para { nodes } => tidy(&plain_text(nodes, PlainOptions::default())),
            _ => String::new(),
        })
        .collect::<Vec<_>>()
        .join(" ");

    if !PIED.is_match(&texte) {
        return None;
    }

    Some(Footer {
        version: VERSION
            .captures(&texte)
            .and_then(|c| c.get(1).map(|m| m.as_str().to_string())),
        locked: VERROUILLE.is_match(&texte),
        notes: blocks[1..].to_vec(),
    })
}

pub struct ChapterSource {
    /// Chemin relatif à la racine du vault.
    pub path: String,
    pub text: String,
    pub book_id: String,
    pub status: Status,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Issue {
    pub line: usize,
    pub message: String,
}

pub struct ParsedChapter {
    pub chapter: Chapter,
    /// Anomalies de balisage repérées, avec leur numéro de ligne.
    pub issues: Vec<Issue>,
}

static NOM_FICHIER: Lazy<Regex> = Lazy::new(|| Regex::new(r"^(.+)-(\d+)(-intro)?$").unwrap());

/// Déduit le numéro d'unité et le type depuis le nom de fichier.
fn read_file_name(path: &str) -> (String, u32, ChapterKind) {
    let id = path
        .rsplit('/')
        .next()
        .unwrap_or(path)
        .trim_end_matches(".md")
        .to_string();

    match NOM_FICHIER.captures(&id) {
        Some(m) => (
            id.clone(),
            m.get(2).and_then(|g| g.as_str().parse().ok()).unwrap_or(0),
            if m.get(3).is_some() {
                ChapterKind::Intro
            } else {
                ChapterKind::Chapter
            },
        ),
        None => (id, 0, ChapterKind::Chapter),
    }
}

/// Où s'arrête ce qui sera publié.
///
/// Rend l'indice de la première ligne du paratexte, ou le nombre de lignes
/// s'il n'y en a pas. La décision est celle de `parse_footer`, pas une règle
/// écrite en double : on cherche le dernier filet dont la suite s'analyse
/// comme un pied de page.
fn fin_du_corps(lines: &[String]) -> usize {
    for (index, ligne) in lines.iter().enumerate().rev() {
        if ligne.trim() != "---" {
            continue;
        }
        if parse_footer(&parse_blocks(&lines[index + 1..])).is_some() {
            return index;
        }
    }
    lines.len()
}

/// Parse un fichier du vault en unité ONT.
pub fn parse_chapter(source: &ChapterSource) -> ParsedChapter {
    let lines: Vec<String> = source
        .text
        .split('\n')
        .map(|l| l.trim_end_matches('\r').to_string())
        .collect();
    let (id, n, kind) = read_file_name(&source.path);

    // **On ne contrôle que ce qui sera publié.**
    //
    // Le contrôle passait sur toutes les lignes du fichier, paratexte compris
    // — le bloc « Décisions terminologiques » qui suit le dernier filet et que
    // `parse_footer` écarte du corps. Or ce paratexte imbrique volontiers
    // italique et gras (`***emunah*`), ce que `lint_markers` signale à juste
    // titre pour un verset et à tort pour une note d'apparat.
    //
    // Le rapport annonçait ainsi vingt-deux anomalies dont **aucune**
    // n'atteignait un lecteur. Un rapport qui crie au loup n'est pas seulement
    // inutile : il enterre le vrai déséquilibre qui viendra un jour dans un
    // verset.
    //
    // La borne n'est pas devinée — elle rejoue la décision de l'analyseur en
    // appelant `parse_footer` lui-même. Une note d'apparat qui cesserait d'en
    // être une redeviendrait donc contrôlée, sans que personne y pense.
    let fin_du_corps = fin_du_corps(&lines);
    let issues: Vec<Issue> = lines
        .iter()
        .take(fin_du_corps)
        .enumerate()
        .flat_map(|(index, line)| {
            lint_markers(line).into_iter().map(move |message| Issue {
                line: index + 1,
                message,
            })
        })
        .collect();

    let blocks = parse_blocks(&lines);

    // En-tête : le titre, puis éventuellement le sous-titre de référence.
    let mut cursor = 0usize;
    let mut title_nodes = parse_inline(&id);
    if let Some(Block::Heading { level: 1, nodes }) = blocks.first() {
        title_nodes = nodes.clone();
        cursor += 1;
    }

    let mut subtitle = None;
    if let Some(bloc) = blocks.get(cursor) {
        subtitle = parse_subtitle(bloc);
        if subtitle.is_some() {
            cursor += 1;
        }
    }

    // Pied de page : ce qui suit le **dernier** filet, s'il s'annonce comme
    // tel. On ne se fie pas à la position mais au contenu — un filet est un
    // ornement fréquent, et prendre le premier venu emporterait du corps.
    let mut body: Vec<Block> = blocks[cursor..].to_vec();
    let mut footer = None;
    if let Some(dernier) = body.iter().rposition(|b| matches!(b, Block::Rule)) {
        let candidat = &body[dernier + 1..];
        footer = parse_footer(candidat);
        if footer.is_some() {
            body.truncate(dernier);
        }
    }

    // Le filet qui sépare l'en-tête du corps n'est qu'un ornement.
    while matches!(body.first(), Some(Block::Rule)) {
        body.remove(0);
    }

    let body = lift_verses(body);

    let verse_count: u32 = body
        .iter()
        .map(|b| match b {
            Block::Verses { verses } => verses.len() as u32,
            _ => 0,
        })
        .sum();

    // `BTreeSet` plutôt qu'un tri après coup : il déduplique et ordonne d'un
    // seul geste, dans l'ordre lexicographique — le même que `Array.sort()`
    // sur des chaînes ASCII, ce que les lemmes sont toujours.
    let mut lemmas = BTreeSet::new();
    for bloc in &body {
        let mut trouves = Vec::new();
        match bloc {
            Block::Verses { verses } => {
                for verse in verses {
                    collect_terms(&verse.nodes, TermLevel::Body, &mut trouves);
                }
            }
            Block::Heading { nodes, .. } | Block::Para { nodes } | Block::Quote { nodes } => {
                collect_terms(nodes, TermLevel::Body, &mut trouves);
            }
            _ => {}
        }
        for t in trouves {
            lemmas.insert(t.lemma);
        }
    }

    ParsedChapter {
        chapter: Chapter {
            id: id.clone(),
            book_id: source.book_id.clone(),
            kind,
            n,
            title: tidy(&plain_text(&title_nodes, PlainOptions::default())),
            title_nodes,
            subtitle,
            status: source.status,
            blocks: body,
            footer,
            verse_count,
            lemmas: lemmas.into_iter().collect(),
            source: source.path.clone(),
        },
        issues,
    }
}

// ───────────────────────────────────────────────────────────────────────────
// L'index des renvois — de la numérotation ONT vers la numérotation reçue
// ───────────────────────────────────────────────────────────────────────────

/// La plage biblique qu'un sous-titre déclare, une fois lue.
///
/// Le sous-titre est la **seule trace** de la numérotation d'origine, celle de
/// l'ONT repartant de ¹ à chaque **parashah** (§2.2). Le vault n'écrit que ces
/// quatre formes — relevées sur les 22 unités qui en portent une, non supposées.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PlageBiblique {
    /// `6` — le chapitre entier. Sa longueur n'est pas déclarée : ce sont les
    /// versets de l'unité qui la donnent.
    ChapitreEntier(u32),
    /// `18:1-33` — une plage de versets dans un seul chapitre. C'est la seule
    /// forme qui déclare son propre compte, donc la seule qui se contrôle.
    Versets {
        chapitre: u32,
        premier: u32,
        dernier: u32,
    },
    /// `7-8` — des chapitres entiers, que la numérotation ONT sépare en autant
    /// de séries puisqu'elle repart de ¹ à chaque frontière.
    Chapitres { premier: u32, dernier: u32 },
    /// `1:1 — 2:3` — la plage traverse une frontière de chapitre.
    Traversee {
        depuis: (u32, u32),
        jusqu_a: (u32, u32),
    },
}

/// Pourquoi une unité n'a pas pu être indexée.
///
/// Elle **refuse** au lieu de deviner, et c'est tout l'objet du type. Une
/// correspondance fausse ne rend pas le renvoi inerte : elle l'envoie **au
/// mauvais verset**, et le lecteur arrive ailleurs sans que rien ne le lui
/// dise. Un renvoi cassé se voit ; un renvoi qui ment, jamais.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IndexRefuse {
    /// Le sous-titre porte une forme qu'on ne sait pas lire.
    PlageIllisible(String),
    /// La plage annonce un nombre de versets, l'unité en porte un autre.
    /// C'est la somme de contrôle, et elle attrape les trous du corpus.
    CompteDiscordant { attendu: u32, reel: u32 },
    /// La plage annonce N chapitres, la numérotation n'y montre pas N séries.
    SeriesDiscordantes { chapitres: u32, series: usize },
    /// L'unité ne porte aucun verset numéroté — une introduction, ou de la prose.
    AucunVerset,
}

static PLAGE_TRAVERSEE: Lazy<Regex> =
    Lazy::new(|| Regex::new(r"^(\d+):(\d+)\s*[—–-]\s*(\d+):(\d+)$").unwrap());
static PLAGE_VERSETS: Lazy<Regex> =
    Lazy::new(|| Regex::new(r"^(\d+):(\d+)\s*[—–-]\s*(\d+)$").unwrap());
static PLAGE_CHAPITRES: Lazy<Regex> = Lazy::new(|| Regex::new(r"^(\d+)\s*[—–-]\s*(\d+)$").unwrap());
static PLAGE_CHAPITRE: Lazy<Regex> = Lazy::new(|| Regex::new(r"^(\d+)$").unwrap());

fn nombre(c: Option<regex::Match<'_>>) -> Option<u32> {
    c?.as_str().parse().ok()
}

/// Lit le renvoi brut du sous-titre — `"18:1-33"` — en plage structurée.
///
/// L'ordre des essais compte : la traversée porte deux `:` et serait happée par
/// la forme à un seul chapitre, qui n'en attend qu'un.
pub fn lire_la_plage(reference: &str) -> Option<PlageBiblique> {
    let r = reference.trim();
    if let Some(c) = PLAGE_TRAVERSEE.captures(r) {
        return Some(PlageBiblique::Traversee {
            depuis: (nombre(c.get(1))?, nombre(c.get(2))?),
            jusqu_a: (nombre(c.get(3))?, nombre(c.get(4))?),
        });
    }
    if let Some(c) = PLAGE_VERSETS.captures(r) {
        return Some(PlageBiblique::Versets {
            chapitre: nombre(c.get(1))?,
            premier: nombre(c.get(2))?,
            dernier: nombre(c.get(3))?,
        });
    }
    if let Some(c) = PLAGE_CHAPITRES.captures(r) {
        return Some(PlageBiblique::Chapitres {
            premier: nombre(c.get(1))?,
            dernier: nombre(c.get(2))?,
        });
    }
    if let Some(c) = PLAGE_CHAPITRE.captures(r) {
        return Some(PlageBiblique::ChapitreEntier(nombre(c.get(1))?));
    }
    None
}

/// Découpe la suite des numéros ONT en séries — une série se rompt quand le
/// numéro cesse de croître, c'est-à-dire à chaque redémarrage du §2.2.
fn series(versets: &[u32]) -> Vec<&[u32]> {
    let mut coupes = vec![0usize];
    for i in 1..versets.len() {
        if versets[i] <= versets[i - 1] {
            coupes.push(i);
        }
    }
    coupes.push(versets.len());
    coupes.windows(2).map(|w| &versets[w[0]..w[1]]).collect()
}

/// Donne, pour chaque verset de l'unité, sa coordonnée dans la numérotation
/// reçue — `(chapitre, verset)`.
///
/// N'a besoin d'aucune Bible : la plage et la structure des versets suffisent,
/// et c'est délibéré. Un pipeline qui devrait embarquer un texte source pour
/// résoudre un renvoi dépendrait d'une donnée que le vault ne contrôle pas.
pub fn indexer(plage: &PlageBiblique, versets: &[u32]) -> Result<Vec<(u32, u32)>, IndexRefuse> {
    if versets.is_empty() {
        return Err(IndexRefuse::AucunVerset);
    }
    match plage {
        // Le chapitre entier : la longueur n'est pas déclarée, donc rien à
        // contrôler. Les numéros ONT sont ceux du chapitre.
        PlageBiblique::ChapitreEntier(c) => Ok(versets.iter().map(|v| (*c, *v)).collect()),

        // La seule forme qui déclare son compte — donc la seule qui se contrôle.
        PlageBiblique::Versets {
            chapitre,
            premier,
            dernier,
        } => {
            let attendu = dernier.saturating_sub(*premier) + 1;
            let reel = versets.len() as u32;
            if attendu != reel {
                return Err(IndexRefuse::CompteDiscordant { attendu, reel });
            }
            Ok(versets
                .iter()
                .map(|v| (*chapitre, premier + v - 1))
                .collect())
        }

        // Des chapitres entiers : c'est la numérotation ONT qui dit où ils se
        // séparent, puisqu'elle repart de ¹ (§2.2).
        PlageBiblique::Chapitres { premier, dernier } => {
            let attendus = dernier.saturating_sub(*premier) + 1;
            let series = series(versets);
            if series.len() != attendus as usize {
                return Err(IndexRefuse::SeriesDiscordantes {
                    chapitres: attendus,
                    series: series.len(),
                });
            }
            Ok(series
                .iter()
                .enumerate()
                .flat_map(|(k, serie)| serie.iter().map(move |v| (premier + k as u32, *v)))
                .collect())
        }

        // La traversée. Le vault la traite de deux façons — `bereshit-7` repart
        // de ¹, `bereshit-1` continue —, et les deux se lisent : deux séries
        // donnent les deux chapitres, une seule se coupe par la queue, dont la
        // plage déclare la longueur.
        PlageBiblique::Traversee { depuis, jusqu_a } => {
            let (c1, v1) = *depuis;
            let (c2, v2) = *jusqu_a;
            let series = series(versets);
            if series.len() == 2 {
                let mut out: Vec<(u32, u32)> = series[0].iter().map(|v| (c1, v1 + v - 1)).collect();
                out.extend(series[1].iter().map(|v| (c2, *v)));
                return Ok(out);
            }
            let total = versets.len() as u32;
            if total <= v2 {
                return Err(IndexRefuse::CompteDiscordant {
                    attendu: v2 + 1,
                    reel: total,
                });
            }
            let tete = total - v2;
            Ok(versets
                .iter()
                .enumerate()
                .map(|(i, v)| {
                    if (i as u32) < tete {
                        (c1, v1 + v - 1)
                    } else {
                        (c2, *v - tete)
                    }
                })
                .collect())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn un_paragraphe_versifie_se_decoupe() {
        let nodes = parse_inline("¹ Au commencement ² Et la terre ³ Et Elohim");
        let versets = split_verses(&nodes).expect("trois versets");
        assert_eq!(versets.len(), 3);
        assert_eq!(versets[0].n, 1);
        assert_eq!(versets[2].n, 3);
    }

    #[test]
    fn un_exposant_a_deux_chiffres_se_lit() {
        let nodes = parse_inline("¹⁰ Le dixième ¹¹ Le onzième");
        let versets = split_verses(&nodes).unwrap();
        assert_eq!(versets[0].n, 10);
        assert_eq!(versets[1].n, 11);
    }

    #[test]
    fn de_la_prose_n_est_pas_versifiee() {
        // Une feuille d'introduction n'a pas de versets. Les inventer
        // donnerait des renvois qui ne correspondent à rien.
        let nodes = parse_inline("Cette introduction ne porte aucun exposant.");
        assert!(split_verses(&nodes).is_none());
    }

    #[test]
    fn l_espace_qui_suit_l_exposant_est_retire() {
        let nodes = parse_inline("¹ Au commencement");
        let versets = split_verses(&nodes).unwrap();
        let Inline::Text { v } = &versets[0].nodes[0] else {
            panic!("du texte")
        };
        assert!(
            !v.starts_with(' '),
            "« {v} » ne doit pas commencer par une espace"
        );
    }

    #[test]
    fn un_sous_titre_separe_le_francais_l_hebreu_et_le_renvoi() {
        let bloc = Block::Para {
            nodes: parse_inline("(Genèse / בְּרֵאשִׁית 18:1-33)"),
        };
        let sous_titre = parse_subtitle(&bloc).expect("un sous-titre");
        assert_eq!(sous_titre.french, "Genèse");
        assert_eq!(sous_titre.reference.as_deref(), Some("18:1-33"));
        assert!(!sous_titre.hebrew.is_empty());
    }

    #[test]
    fn une_introduction_n_a_pas_de_renvoi() {
        //
        // Elle ne recouvre aucun verset. Le champ vaut `null` et non l'absence
        // — un piège pour qui déclare seulement `#[serde(default)]`.
        let bloc = Block::Para {
            nodes: parse_inline("(Genèse / בְּרֵאשִׁית)"),
        };
        let sous_titre = parse_subtitle(&bloc).unwrap();
        assert_eq!(sous_titre.reference, None);
    }

    #[test]
    fn le_nom_de_fichier_donne_le_numero_et_le_type() {
        let (id, n, kind) = read_file_name("locked/…/bereshit-18.md");
        assert_eq!(id, "bereshit-18");
        assert_eq!(n, 18);
        assert_eq!(kind, ChapterKind::Chapter);

        let (id, n, kind) = read_file_name("toledot-adam-ve-chavah-0-intro.md");
        assert_eq!(id, "toledot-adam-ve-chavah-0-intro");
        assert_eq!(n, 0);
        assert_eq!(kind, ChapterKind::Intro);
    }

    #[test]
    fn une_unite_complete_se_parse() {
        let source = ChapterSource {
            path: "locked/bereshit-1.md".into(),
            text: "# Bereshit 1\n\n(Genèse / בְּרֵאשִׁית 1:1-31)\n\n---\n\n\
                   ¹ Quand **Elohim** commença ² Et la terre\n\n---\n\n\
                   *Bereshit 1 — Version 1.0 — verrouillée*\n"
                .into(),
            book_id: "bereshit".into(),
            status: Status::Locked,
        };
        let parsed = parse_chapter(&source);
        let c = parsed.chapter;

        assert_eq!(c.title, "Bereshit 1");
        assert_eq!(c.verse_count, 2);
        assert_eq!(c.lemmas, vec!["elohim"]);
        assert_eq!(c.subtitle.unwrap().reference.as_deref(), Some("1:1-31"));

        let pied = c.footer.expect("un pied de page");
        assert!(pied.locked);
        assert_eq!(pied.version.as_deref(), Some("1.0"));
    }
}

#[cfg(test)]
mod tests_du_paratexte {
    use super::*;

    /// Le paratexte n'est pas contrôlé — il n'est pas publié.
    #[test]
    fn le_paratexte_ne_produit_pas_d_anomalie() {
        let source = ChapterSource {
            path: "locked/bereshit-15.md".into(),
            text: "# Bereshit 15\n\n## La vision\n\n1. Un verset sans défaut.\n\n---\n\n\
                   *Bereshit 15 — Version 1.0 — verrouillée*\n\
                   - ***emunah* (אֱמוּנָה) — intraduisible, avec **YHWH** dedans*\n"
                .into(),
            book_id: "bereshit".into(),
            status: Status::Locked,
        };
        let parsed = parse_chapter(&source);
        assert!(
            parsed.issues.is_empty(),
            "le paratexte a été contrôlé alors qu'il n'est pas publié : {:?}",
            parsed.issues
        );
    }

    /// Et le corps, lui, l'est toujours — c'est ce que la correction ne doit
    /// pas emporter avec elle.
    #[test]
    fn un_desequilibre_dans_le_corps_reste_signale() {
        let source = ChapterSource {
            path: "locked/bereshit-15.md".into(),
            text: "# Bereshit 15\n\n## La vision\n\n1. Un **davar non refermé ici.\n\n---\n\n\
                   *Bereshit 15 — Version 1.0 — verrouillée*\n"
                .into(),
            book_id: "bereshit".into(),
            status: Status::Locked,
        };
        let parsed = parse_chapter(&source);
        assert!(
            parsed
                .issues
                .iter()
                .any(|i| i.message.contains("intraduisible")),
            "un déséquilibre du corps a été perdu : {:?}",
            parsed.issues
        );
    }
}

#[cfg(test)]
mod tests_de_l_index {
    use super::*;

    #[test]
    fn les_quatre_formes_du_vault_se_lisent() {
        //
        // Les quatre seules formes relevées sur les 22 unités qui portent un
        // renvoi. La traversée doit passer AVANT la plage à un chapitre : elle
        // porte deux `:` et serait happée par elle.
        assert_eq!(
            lire_la_plage("18:1-33"),
            Some(PlageBiblique::Versets {
                chapitre: 18,
                premier: 1,
                dernier: 33
            })
        );
        assert_eq!(
            lire_la_plage("1:1 — 2:3"),
            Some(PlageBiblique::Traversee {
                depuis: (1, 1),
                jusqu_a: (2, 3)
            })
        );
        assert_eq!(
            lire_la_plage("7-8"),
            Some(PlageBiblique::Chapitres {
                premier: 7,
                dernier: 8
            })
        );
        assert_eq!(lire_la_plage("6"), Some(PlageBiblique::ChapitreEntier(6)));
        assert_eq!(lire_la_plage("n'importe quoi"), None);
    }

    #[test]
    fn le_verset_huit_de_l_unite_neuf_est_l_arur_sur_kenaan() {
        //
        // LE témoin. C'est ce verset qui a produit les deux seules références
        // fautives du corpus : une glose annonçait l'*arur* sur Kenaʿan et
        // renvoyait à « Bereshit 9:8 », que la lecture biblique menait à
        // l'ouverture de la **berith**. L'unité 9 couvre Gn 9:18-29, donc son
        // verset ⁸ est Gn 9:25 — et Gn 9:25 est bien l'*arur*.
        let plage = lire_la_plage("9:18-29").expect("une plage");
        let versets: Vec<u32> = (1..=12).collect();
        let index = indexer(&plage, &versets).expect("un index");
        assert_eq!(index[7], (9, 25));
        assert_eq!(index[0], (9, 18));
        assert_eq!(index[11], (9, 29));
    }

    #[test]
    fn le_compte_qui_ne_tombe_pas_refuse_au_lieu_de_deviner() {
        //
        // `bereshit-2` annonce Gn 2:4-25, soit 22 versets, et n'en porte que
        // 21 — un trou que le pipeline signale déjà par un autre chemin.
        // L'index ne comble pas : il refuse. Deviner ici décalerait tous les
        // versets suivants d'un rang, et le lecteur arriverait à côté sans que
        // rien ne le lui dise.
        let plage = lire_la_plage("2:4-25").expect("une plage");
        let versets: Vec<u32> = (1..=21).collect();
        assert_eq!(
            indexer(&plage, &versets),
            Err(IndexRefuse::CompteDiscordant {
                attendu: 22,
                reel: 21
            })
        );
    }

    #[test]
    fn deux_chapitres_se_separent_par_le_redemarrage_de_la_numerotation() {
        //
        // `bereshit-7` couvre Gn 7-8 et repart de ¹ à la frontière (§2.2) :
        // 24 versets puis 22. C'est la numérotation qui dit où couper — aucune
        // Bible n'est nécessaire.
        let plage = lire_la_plage("7-8").expect("une plage");
        let mut versets: Vec<u32> = (1..=24).collect();
        versets.extend(1..=22u32);
        let index = indexer(&plage, &versets).expect("un index");
        assert_eq!(index[0], (7, 1));
        assert_eq!(index[23], (7, 24));
        assert_eq!(index[24], (8, 1));
        assert_eq!(index[45], (8, 22));
    }

    #[test]
    fn une_traversee_continue_se_coupe_par_sa_queue() {
        //
        // `bereshit-1` couvre Gn 1:1 — 2:3 et NE repart PAS de ¹ : une seule
        // série de 34. Il s'écarte du §2.2, et l'index le lit quand même — la
        // plage déclare la longueur de la queue, donc la tête s'en déduit.
        let plage = lire_la_plage("1:1 — 2:3").expect("une plage");
        let versets: Vec<u32> = (1..=34).collect();
        let index = indexer(&plage, &versets).expect("un index");
        assert_eq!(index[30], (1, 31));
        assert_eq!(index[31], (2, 1));
        assert_eq!(index[33], (2, 3));
    }

    #[test]
    fn une_unite_sans_verset_refuse() {
        let plage = lire_la_plage("6").expect("une plage");
        assert_eq!(indexer(&plage, &[]), Err(IndexRefuse::AucunVerset));
    }
}
