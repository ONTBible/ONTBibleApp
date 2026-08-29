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
