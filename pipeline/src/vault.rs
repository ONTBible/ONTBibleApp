//! La lecture du vault — **l'arborescence est l'ordre canonique**.
//!
//! Le `corpus-order.md` le dit : « l'IDE trie alphabétiquement, les préfixes
//! numériques forcent l'ordre fonctionnel ». On lit donc l'ordre dans les noms
//! de dossiers plutôt que de le redéclarer ici — ce qui garantit qu'ajouter un
//! slot dans le vault suffit à le voir paraître dans la liseuse, sans toucher
//! au code.
//!
//! ```text
//! 1. kenesset (le Rassemblement)/       ← corpus
//!   1. torah (la Fondation)/            ← mode
//!     01. bereshit (Genèse)/            ← livre
//!       bereshit-1.md                   ← unité ONT
//! ```
//!
//! La profondeur varie : certains modes intercalent un conteneur — `44.
//! eduyot`, `15. trei-asar`, `49. igerot`. La règle est donc **structurelle et
//! non nominale** : un dossier qui contient des dossiers est un conteneur, un
//! dossier qui n'en contient pas est un livre.

use std::fs;
use std::path::{Path, PathBuf};

use once_cell::sync::Lazy;
use regex::Regex;

/// `01. bereshit (Genèse)` → ordre 1, id `bereshit`, étiquette `Genèse`.
static SLOT: Lazy<Regex> = Lazy::new(|| Regex::new(r"^(\d+)\.\s*(.+?)\s*\((.+)\)\s*$").unwrap());

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SlotName {
    pub order: u32,
    pub id: String,
    pub label: String,
}

pub fn parse_slot_name(name: &str) -> Option<SlotName> {
    let m = SLOT.captures(name)?;
    Some(SlotName {
        order: m.get(1)?.as_str().parse().ok()?,
        id: m.get(2)?.as_str().to_string(),
        label: m.get(3)?.as_str().to_string(),
    })
}

/// Un livre repéré dans une arborescence, avec son chemin canonique.
#[derive(Debug, Clone)]
pub struct VaultBook {
    pub id: String,
    pub slot: u32,
    pub french: String,
    pub corpus: SlotName,
    pub mode: SlotName,
    /// Les conteneurs traversés, du plus large au plus étroit.
    pub groups: Vec<SlotName>,
    /// Chemin absolu du dossier du livre.
    pub dir: PathBuf,
    /// Noms de fichiers `.md` présents, triés.
    pub files: Vec<String>,
}

/// Les sous-dossiers, triés, en écartant les cachés.
///
/// Le tri est explicite et ne suppose rien de l'ordre du système de fichiers :
/// il varie d'une machine à l'autre, et un build doit rendre le même corpus
/// partout.
fn subdirectories(dir: &Path) -> Vec<String> {
    let mut noms: Vec<String> = fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter(|e| e.file_type().map(|t| t.is_dir()).unwrap_or(false))
        .map(|e| e.file_name().to_string_lossy().to_string())
        .filter(|n| !n.starts_with('.'))
        .collect();
    noms.sort();
    noms
}

fn markdown_files(dir: &Path) -> Vec<String> {
    let mut noms: Vec<String> = fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter(|e| e.file_type().map(|t| t.is_file()).unwrap_or(false))
        .map(|e| e.file_name().to_string_lossy().to_string())
        .filter(|n| n.ends_with(".md"))
        .collect();
    noms.sort();
    noms
}

/// Descend un dossier jusqu'aux livres.
///
/// Un dossier qui contient des sous-dossiers est un conteneur — on continue.
/// Un dossier terminal est un livre, **même vide** : un slot non encore rédigé
/// n'existe qu'à travers son `.gitkeep`, et il doit paraître dans la table des
/// matières. C'est l'ampleur du chantier qui se lit, et elle fait partie du
/// propos.
fn descend(
    dir: &Path,
    corpus: &SlotName,
    mode: &SlotName,
    groups: &[SlotName],
    into: &mut Vec<VaultBook>,
) {
    for name in subdirectories(dir) {
        let Some(slot) = parse_slot_name(&name) else {
            continue;
        };

        let child = dir.join(&name);
        if !subdirectories(&child).is_empty() {
            let mut plus_loin = groups.to_vec();
            plus_loin.push(slot);
            descend(&child, corpus, mode, &plus_loin, into);
            continue;
        }

        into.push(VaultBook {
            id: slot.id.clone(),
            slot: slot.order,
            french: slot.label.clone(),
            corpus: corpus.clone(),
            mode: mode.clone(),
            groups: groups.to_vec(),
            files: markdown_files(&child),
            dir: child,
        });
    }
}

/// Parcourt une arborescence — `locked`, `brouillons` ou `in-writing` — et rend
/// tous les livres qu'elle contient.
///
/// Une arborescence absente rend une liste vide plutôt qu'une erreur : le vault
/// peut légitimement n'avoir aucun brouillon.
pub fn read_tree(root: &Path) -> Vec<VaultBook> {
    let mut books = Vec::new();

    for corpus_name in subdirectories(root) {
        let Some(corpus) = parse_slot_name(&corpus_name) else {
            continue;
        };
        let corpus_dir = root.join(&corpus_name);
        for mode_name in subdirectories(&corpus_dir) {
            let Some(mode) = parse_slot_name(&mode_name) else {
                continue;
            };
            descend(&corpus_dir.join(&mode_name), &corpus, &mode, &[], &mut books);
        }
    }

    books
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn un_nom_de_slot_se_decompose() {
        let slot = parse_slot_name("01. bereshit (Genèse)").expect("doit correspondre");
        assert_eq!(slot.order, 1);
        assert_eq!(slot.id, "bereshit");
        assert_eq!(slot.label, "Genèse");
    }

    #[test]
    fn un_dossier_sans_prefixe_est_ignore() {
        // Le préfixe numérique **est** l'ordre. Un dossier sans lui n'a pas de
        // place dans le corpus, et l'ignorer vaut mieux que de l'ajouter à la
        // fin sans que personne ne l'ait décidé.
        assert!(parse_slot_name("bereshit (Genèse)").is_none());
        assert!(parse_slot_name(".obsidian").is_none());
    }

    #[test]
    fn une_etiquette_a_parentheses_garde_les_siennes() {
        // `(le Rassemblement)` — le motif est non gourmand sur l'identifiant et
        // gourmand sur l'étiquette, donc une parenthèse interne survit.
        let slot = parse_slot_name("1. kenesset (le Rassemblement)").unwrap();
        assert_eq!(slot.id, "kenesset");
        assert_eq!(slot.label, "le Rassemblement");
    }

    #[test]
    fn une_arborescence_absente_rend_une_liste_vide() {
        let livres = read_tree(Path::new("/chemin/qui/n/existe/pas"));
        assert!(livres.is_empty(), "pas d'erreur, pas de panique");
    }
}
