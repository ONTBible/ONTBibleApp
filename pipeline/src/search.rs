//! L'index de recherche.
//!
//! Le corpus ONT permet une recherche que les liseuses ordinaires ne peuvent
//! pas offrir, parce qu'elles n'ont ni ses niveaux ni son hébreu :
//!
//! 1. **Par niveau** — chercher dans le corps seul, dans les gloses, ou
//!    partout. « Où le texte dit-il *chesed* » et « où l'explique-t-on » sont
//!    deux questions distinctes (§2.1).
//! 2. **En hébreu, sans les voyelles.** Le lecteur tape au clavier hébreu
//!    ordinaire ; le texte porte le niqqud et les te'amim. On indexe la forme
//!    **dénudée** pour que les deux se rencontrent — sans ça, la recherche
//!    hébraïque ne trouve jamais rien.
//! 3. **Par translittération** — taper « chesed » trouve aussi les passages où
//!    seul l'hébreu figure, via le lemme du glossaire.
//! 4. **Insensible aux diacritiques.**
//!
//! L'index reste un tableau à plat : à l'échelle du corpus — quelques dizaines
//! de milliers d'entrées une fois les 70 slots rédigés — un balayage de
//! sous-chaînes est instantané sur un téléphone. Un index inversé serait de la
//! complexité sans gain mesurable.

use once_cell::sync::Lazy;
use regex::Regex;
use serde::{Deserialize, Serialize};

use crate::inline::{collect_terms, plain_text, tidy, PlainOptions};
use crate::schema::{Block, Chapter, Inline, TermLevel};

static MARQUES: Lazy<Regex> = Lazy::new(|| Regex::new(r"\p{M}").unwrap());
static ESPACES: Lazy<Regex> = Lazy::new(|| Regex::new(r"\s+").unwrap());
/// La ponctuation hébraïque : maqaf, paseq, sof pasuq, nun hafukha, geresh,
/// gershayim. Elle sépare ou orne, elle ne porte pas de consonne.
static PONCTUATION_HEBRAIQUE: Lazy<Regex> =
    Lazy::new(|| Regex::new(r"[\u{05BE}\u{05C0}\u{05C3}\u{05C6}\u{05F3}\u{05F4}]").unwrap());

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RecordKind {
    Verse,
    Heading,
    Prose,
}

/// Une entrée indexable — un verset, un titre de section, un paragraphe.
///
/// Les noms de champs font une lettre : l'index est embarqué dans le binaire de
/// l'app, et soixante-dix livres en feront un fichier qu'on ne veut pas voir
/// grossir pour des noms lisibles que personne ne lit.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SearchRecord {
    /// Livre.
    pub b: String,
    /// Unité ONT.
    pub c: String,
    /// Numéro de verset ONT, ou `0` hors d'un verset.
    pub v: u32,
    /// Pour classer les résultats.
    pub k: RecordKind,
    /// Le corps de la traduction, plié — minuscules, sans diacritiques.
    pub t: String,
    /// Les gloses, pliées.
    pub g: String,
    /// L'hébreu dénudé de ses voyelles et de sa cantillation.
    pub h: String,
    /// Les lemmes présents, pour la recherche par terme.
    pub l: Vec<String>,
    /// Le texte du corps tel qu'il s'affiche — pour l'extrait de résultat.
    pub x: String,
}

/// Plie une chaîne latine pour la comparaison.
///
/// **Doit rester identique à son homologue Swift**, sinon l'index et la requête
/// ne se rencontrent pas — et l'échec serait muet : la recherche ne trouverait
/// simplement rien, sans que rien ne l'explique.
pub fn fold(input: &str) -> String {
    let decompose = crate::inline::decomposer_public(input);
    let sans_marques = MARQUES.replace_all(&decompose, "");
    let minuscules = sans_marques.to_lowercase();
    let normalisees: String = minuscules
        .chars()
        .map(|c| match c {
            '\u{2019}' | '\u{02BC}' => '\'',
            autre => autre,
        })
        .collect();
    ESPACES.replace_all(&normalisees, " ").trim().to_string()
}

/// Dénude l'hébreu : retire niqqud, te'amim et ponctuation, ne laisse que les
/// consonnes.
///
/// C'est ce qui permet à une saisie au clavier hébreu ordinaire — sans
/// voyelles, comme on écrit l'hébreu tous les jours — de rencontrer un texte
/// biblique intégralement vocalisé.
pub fn strip_hebrew(input: &str) -> String {
    let sans_marques = MARQUES.replace_all(input, "");
    let sans_ponctuation = PONCTUATION_HEBRAIQUE.replace_all(&sans_marques, "");
    ESPACES
        .replace_all(&sans_ponctuation, " ")
        .trim()
        .to_string()
}

/// Récolte toutes les séquences hébraïques d'un arbre inline.
fn hebrew_of(nodes: &[Inline], into: &mut Vec<String>) {
    for node in nodes {
        match node {
            Inline::Heb { v } => into.push(v.clone()),
            Inline::Translit { hebrew, .. } => into.push(hebrew.clone()),
            Inline::Gloss { children }
            | Inline::Em { children }
            | Inline::Important { children }
            | Inline::Link { children, .. } => hebrew_of(children, into),
            _ => {}
        }
    }
}

/// Le texte des gloses **seules**.
///
/// Indexer « corps + gloses » sous l'étiquette « gloses » ferait remonter le
/// corps quand on cherche dans les gloses — la distinction de niveaux serait
/// perdue au moment précis où l'on s'en sert.
fn gloss_text(nodes: &[Inline], into: &mut Vec<String>) {
    for node in nodes {
        match node {
            Inline::Gloss { children } => into.push(plain_text(
                children,
                PlainOptions {
                    gloss: true,
                    ..Default::default()
                },
            )),
            Inline::Em { children } | Inline::Link { children, .. } => gloss_text(children, into),
            _ => {}
        }
    }
}

fn record(
    chapter: &Chapter,
    kind: RecordKind,
    verse: u32,
    nodes: &[Inline],
) -> Option<SearchRecord> {
    let body = tidy(&plain_text(nodes, PlainOptions::default()));

    let mut gloses = Vec::new();
    gloss_text(nodes, &mut gloses);
    let gloss = tidy(&gloses.join(" "));

    if body.is_empty() && gloss.is_empty() {
        return None;
    }

    let mut hebreux = Vec::new();
    hebrew_of(nodes, &mut hebreux);

    let mut termes = Vec::new();
    collect_terms(nodes, TermLevel::Body, &mut termes);
    // Dédoublonné **en gardant l'ordre du texte**, et non trié.
    //
    // C'est ce que fait `[...new Set(…)]` en JavaScript, dont l'ensemble
    // préserve l'ordre d'insertion. Trier serait plus canonique, mais ce champ
    // est déjà embarqué dans l'app : le changer changerait un fichier que
    // personne n'a demandé à voir changer.
    let mut lemmes: Vec<String> = Vec::new();
    for t in termes {
        if !lemmes.contains(&t.lemma) {
            lemmes.push(t.lemma);
        }
    }

    Some(SearchRecord {
        b: chapter.book_id.clone(),
        c: chapter.id.clone(),
        v: verse,
        k: kind,
        t: fold(&body),
        g: fold(&gloss),
        h: strip_hebrew(&hebreux.join(" ")),
        l: lemmes,
        x: body,
    })
}

/// Construit l'index d'une unité.
pub fn index_chapter(chapter: &Chapter) -> Vec<SearchRecord> {
    let mut records = Vec::new();

    for block in &chapter.blocks {
        match block {
            Block::Verses { verses } => {
                for verse in verses {
                    if let Some(e) = record(chapter, RecordKind::Verse, verse.n, &verse.nodes) {
                        records.push(e);
                    }
                }
            }
            Block::Heading { nodes, .. } => {
                if let Some(e) = record(chapter, RecordKind::Heading, 0, nodes) {
                    records.push(e);
                }
            }
            Block::Para { nodes } | Block::Quote { nodes } => {
                if let Some(e) = record(chapter, RecordKind::Prose, 0, nodes) {
                    records.push(e);
                }
            }
            Block::List { items, .. } => {
                for item in items {
                    if let Some(e) = record(chapter, RecordKind::Prose, 0, item) {
                        records.push(e);
                    }
                }
            }
            _ => {}
        }
    }

    records
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::inline::parse_inline;

    #[test]
    fn le_pliage_efface_diacritiques_et_casse() {
        assert_eq!(fold("Élohim"), "elohim");
        assert_eq!(fold("Tsedaqah"), "tsedaqah");
        assert_eq!(fold("  deux   espaces  "), "deux espaces");
    }

    #[test]
    fn les_apostrophes_se_normalisent_sans_disparaitre() {
        // Contrairement à `slugify`, qui les supprime : ici on garde le
        // caractère, on unifie seulement sa forme. Une recherche « mal'akh »
        // doit rencontrer « mal’akh ».
        assert_eq!(fold("mal’akh"), fold("mal'akh"));
        assert!(fold("mal'akh").contains('\''));
    }

    #[test]
    fn l_hebreu_se_denude_de_ses_voyelles() {
        // C'est le point qui fait exister la recherche hébraïque : le lecteur
        // tape sans voyelles, le texte en est couvert.
        let vocalise = "חֶסֶד";
        let nu = strip_hebrew(vocalise);
        assert!(
            nu.chars().count() < vocalise.chars().count(),
            "les marques doivent tomber"
        );
        assert_eq!(nu, strip_hebrew(&nu), "dénuder est idempotent");
    }

    #[test]
    fn le_maqaf_tombe_avec_le_reste() {
        let avec = strip_hebrew("כָּל־הָאָרֶץ");
        assert!(!avec.contains('\u{05BE}'), "le maqaf ne doit pas rester");
    }

    #[test]
    fn les_gloses_s_indexent_a_part_du_corps() {
        // Si le corps remontait sous l'étiquette « gloses », la distinction
        // de niveaux serait perdue au moment même où l'on s'en sert.
        let nodes = parse_inline("le corps *[la glose]* la suite");
        let mut gloses = Vec::new();
        gloss_text(&nodes, &mut gloses);
        let g = gloses.join(" ");
        assert!(g.contains("glose"));
        assert!(!g.contains("corps"), "le corps n'appartient pas aux gloses");
    }
}
