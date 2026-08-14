//! Le découpage en blocs — la structure de la page, au-dessus de l'inline.
//!
//! On n'implémente pas markdown en général : seulement ce que le vault ONT
//! emploie réellement — titres, paragraphes, listes, citations, tableaux,
//! filets. Un sous-ensemble assumé vaut mieux qu'un parseur générique qui
//! inventerait des cas que le corpus ne contient pas, et dont on ne saurait
//! pas dire s'ils sont justes.
//!
//! Une règle porte tout le reste : **les lignes qui se suivent sans ligne vide
//! gardent leur coupure**. Le vault écrit un paragraphe par ligne, donc une
//! suite de lignes est toujours intentionnelle — c'est le bloc de référence
//! d'une feuille d'introduction (§2.7), pas de la prose à recoller.

use once_cell::sync::Lazy;
use regex::Regex;

use crate::inline::parse_inline;
use crate::schema::{Block, Inline};

static HEADING: Lazy<Regex> = Lazy::new(|| Regex::new(r"^(#{1,6})\s+(.*)$").unwrap());
static UNORDERED_ITEM: Lazy<Regex> = Lazy::new(|| Regex::new(r"^\s*[-+]\s+(.*)$").unwrap());
static ASTERISK_ITEM: Lazy<Regex> = Lazy::new(|| Regex::new(r"^\s*\*\s+(.*)$").unwrap());
static ORDERED_ITEM: Lazy<Regex> = Lazy::new(|| Regex::new(r"^\s*\d+[.)]\s+(.*)$").unwrap());
static QUOTE: Lazy<Regex> = Lazy::new(|| Regex::new(r"^\s*>\s?(.*)$").unwrap());
static TABLE_ROW: Lazy<Regex> = Lazy::new(|| Regex::new(r"^\s*\|(.*)\|\s*$").unwrap());
static TABLE_SEPARATOR: Lazy<Regex> = Lazy::new(|| Regex::new(r"^\s*\|[\s:|-]+\|\s*$").unwrap());

/// Le filet horizontal — `---`, `***`, `___`.
///
/// La version TypeScript employait une **référence arrière** (`\1`) pour exiger
/// trois fois le même caractère. Le moteur de Rust ne les gère pas, par choix
/// de conception : elles rendent le temps d'exécution imprévisible. On énumère
/// donc les trois formes, ce qui revient au même et se lit mieux.
static RULE: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r"^\s*(?:-\s*-\s*-[-\s]*|\*\s*\*\s*\*[*\s]*|_\s*_\s*_[_\s]*)$").unwrap()
});

fn is_rule(line: &str) -> bool {
    RULE.is_match(line)
}

/// Parse plusieurs lignes en un seul flux inline, coupures préservées.
fn parse_lines(lines: &[String]) -> Vec<Inline> {
    let mut out = Vec::new();
    for (index, line) in lines.iter().enumerate() {
        if index > 0 {
            out.push(Inline::Break);
        }
        out.extend(parse_inline(line.trim()));
    }
    out
}

/// Découpe une ligne de tableau en cellules.
fn table_cells(line: &str) -> Vec<Vec<Inline>> {
    let inner = TABLE_ROW
        .captures(line)
        .and_then(|c| c.get(1).map(|m| m.as_str().to_string()))
        .unwrap_or_default();
    inner.split('|').map(|c| parse_inline(c.trim())).collect()
}

fn is_item_start(line: &str) -> bool {
    UNORDERED_ITEM.is_match(line) || ORDERED_ITEM.is_match(line) || ASTERISK_ITEM.is_match(line)
}

/// Découpe un document markdown ONT en blocs.
///
/// Les lignes reçues sont celles du fichier, sans transformation préalable.
pub fn parse_blocks(lines: &[String]) -> Vec<Block> {
    let mut blocks = Vec::new();
    let mut i = 0usize;

    while i < lines.len() {
        let line = &lines[i];

        // Ligne vide — simple séparateur.
        if line.trim().is_empty() {
            i += 1;
            continue;
        }

        // Filet horizontal.
        if is_rule(line) {
            blocks.push(Block::Rule);
            i += 1;
            continue;
        }

        // Titre.
        if let Some(m) = HEADING.captures(line) {
            blocks.push(Block::Heading {
                level: m.get(1).unwrap().as_str().len() as u8,
                nodes: parse_inline(m.get(2).unwrap().as_str().trim()),
            });
            i += 1;
            continue;
        }

        // Tableau — une ligne d'en-tête, une ligne de séparation, puis les
        // lignes. C'est la séparation qui distingue un vrai tableau d'un
        // paragraphe qui contiendrait des barres verticales.
        let suivante = lines.get(i + 1).map(String::as_str).unwrap_or("");
        if TABLE_ROW.is_match(line) && TABLE_SEPARATOR.is_match(suivante) {
            let headers = table_cells(line);
            let mut rows = Vec::new();
            i += 2;
            while i < lines.len() && TABLE_ROW.is_match(&lines[i]) {
                rows.push(table_cells(&lines[i]));
                i += 1;
            }
            blocks.push(Block::Table { headers, rows });
            continue;
        }

        // Citation.
        if QUOTE.is_match(line) {
            let mut quoted = Vec::new();
            while i < lines.len() && QUOTE.is_match(&lines[i]) {
                quoted.push(
                    QUOTE
                        .captures(&lines[i])
                        .and_then(|c| c.get(1).map(|m| m.as_str().to_string()))
                        .unwrap_or_default(),
                );
                i += 1;
            }
            blocks.push(Block::Quote {
                nodes: parse_lines(&quoted),
            });
            continue;
        }

        // Liste — les lignes de continuation appartiennent à l'item courant.
        if is_item_start(line) {
            let ordered = ORDERED_ITEM.is_match(line);
            let mut items: Vec<Vec<Inline>> = Vec::new();
            let mut current: Vec<String> = Vec::new();

            while i < lines.len() {
                let candidate = &lines[i];
                if candidate.trim().is_empty() || is_rule(candidate) || HEADING.is_match(candidate)
                {
                    break;
                }

                let debut = UNORDERED_ITEM
                    .captures(candidate)
                    .or_else(|| ORDERED_ITEM.captures(candidate))
                    .or_else(|| ASTERISK_ITEM.captures(candidate));

                match debut {
                    Some(m) => {
                        if !current.is_empty() {
                            items.push(parse_lines(&current));
                            current.clear();
                        }
                        current.push(m.get(1).unwrap().as_str().to_string());
                    }
                    None => current.push(candidate.trim().to_string()),
                }
                i += 1;
            }
            if !current.is_empty() {
                items.push(parse_lines(&current));
            }
            blocks.push(Block::List { ordered, items });
            continue;
        }

        // Paragraphe — toutes les lignes jusqu'à la prochaine frontière.
        //
        // **La première ligne est toujours prise**, et c'est ce qui empêche la
        // boucle de tourner à vide. Sans ça, une ligne de tableau sans ligne de
        // séparation n'est reconnue ni comme tableau ni comme paragraphe : elle
        // arrive ici, la condition d'arrêt la rejette immédiatement, `i`
        // n'avance pas, et le pipeline tourne jusqu'à épuiser la mémoire.
        //
        // Le défaut existait à l'identique dans la version TypeScript. Le vault
        // ne contient aucun tableau mal formé, donc il n'est jamais apparu —
        // mais c'était une coquille de frappe qui séparait de la panne.
        let mut paragraph = vec![lines[i].clone()];
        i += 1;
        while i < lines.len() {
            let candidate = &lines[i];
            if candidate.trim().is_empty()
                || is_rule(candidate)
                || HEADING.is_match(candidate)
                || QUOTE.is_match(candidate)
                || is_item_start(candidate)
                || TABLE_ROW.is_match(candidate)
            {
                break;
            }
            paragraph.push(candidate.clone());
            i += 1;
        }
        blocks.push(Block::Para {
            nodes: parse_lines(&paragraph),
        });
    }

    blocks
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lignes(texte: &str) -> Vec<String> {
        texte.lines().map(str::to_string).collect()
    }

    fn genre(bloc: &Block) -> &'static str {
        match bloc {
            Block::Heading { .. } => "heading",
            Block::Verses { .. } => "verses",
            Block::Para { .. } => "para",
            Block::List { .. } => "list",
            Block::Quote { .. } => "quote",
            Block::Table { .. } => "table",
            Block::Rule => "rule",
        }
    }

    #[test]
    fn les_trois_formes_de_filet_sont_reconnues() {
        // La version TypeScript employait une référence arrière, que le moteur
        // de Rust refuse. Ce test garde l'équivalence des trois formes.
        for filet in ["---", "***", "___", "- - -", "----"] {
            let blocs = parse_blocks(&lignes(filet));
            assert_eq!(genre(&blocs[0]), "rule", "« {filet} » doit être un filet");
        }
    }

    #[test]
    fn un_paragraphe_de_tirets_n_est_pas_un_filet() {
        let blocs = parse_blocks(&lignes("- un item de liste"));
        assert_eq!(genre(&blocs[0]), "list");
    }

    #[test]
    fn les_lignes_qui_se_suivent_gardent_leur_coupure() {
        // La règle qui porte tout ce module : le vault écrit un paragraphe par
        // ligne, donc une suite de lignes est intentionnelle.
        let blocs = parse_blocks(&lignes("première ligne\nseconde ligne"));
        let Block::Para { nodes } = &blocs[0] else {
            panic!("un paragraphe")
        };
        assert!(
            nodes.iter().any(|n| matches!(n, Inline::Break)),
            "la coupure doit survivre"
        );
    }

    #[test]
    fn un_tableau_demande_sa_ligne_de_separation() {
        let avec = parse_blocks(&lignes("| a | b |\n|---|---|\n| 1 | 2 |"));
        assert_eq!(genre(&avec[0]), "table");

        // Sans séparation, ce sont des paragraphes — pas un tableau deviné.
        let sans = parse_blocks(&lignes("| a | b |\n| 1 | 2 |"));
        assert_eq!(genre(&sans[0]), "para");
    }

    #[test]
    fn une_ligne_de_continuation_reste_dans_son_item() {
        let blocs = parse_blocks(&lignes("- premier\n  suite du premier\n- second"));
        let Block::List { items, .. } = &blocs[0] else {
            panic!("une liste")
        };
        assert_eq!(items.len(), 2, "deux items, pas trois");
    }
}
