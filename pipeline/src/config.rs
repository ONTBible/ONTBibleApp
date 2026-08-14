//! Les chemins et les quelques noms qui ne se déduisent pas.

use std::path::PathBuf;

/// La racine du vault — le dépôt de la traduction.
///
/// Relatif à ce dépôt : les deux sont côte à côte sous `ONTBible/`.
/// Surchargeable par `ONT_VAULT`, pour bâtir depuis un clone ailleurs — c'est
/// ce dont la CI se sert.
pub fn vault() -> PathBuf {
    match std::env::var("ONT_VAULT") {
        Ok(v) => PathBuf::from(v),
        Err(_) => PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("..")
            .join("ONTBibleTranslation"),
    }
}

/// Où le pipeline dépose ses données.
pub fn out() -> PathBuf {
    match std::env::var("ONT_OUT") {
        Ok(v) => PathBuf::from(v),
        Err(_) => PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("dist"),
    }
}

/// Les deux états du flux de validation (§12).
///
/// `locked/` fait référence. `brouillons/` miroite exactement son arborescence
/// et **ne voyage pas** dans la distribution — mais le pipeline le lit quand
/// même, pour que la liseuse d'atelier puisse l'afficher et que le rapport dise
/// où en est le corpus.
pub const TREES: [(&str, &str); 2] = [("locked", "locked"), ("brouillon", "brouillons")];

/// L'arborescence vide des 70 slots — elle définit le squelette du corpus.
pub const SKELETON: &str = "in-writing";

/// Le document de référence : conventions, glossaire, répertoires de noms.
pub const REFERENCE: &str = "CLAUDE.md";

/// Les titres d'affichage des corpus et des modes.
///
/// Les dossiers portent des identifiants sans apostrophe ni majuscule —
/// `neviim`, `berit-hadashah` — parce qu'un nom de fichier doit rester sobre.
/// Ces quelques formes-là ne se déduisent pas mécaniquement de l'identifiant :
/// elles sont donc énoncées ici, et nulle part ailleurs.
const DISPLAY_NAMES: [(&str, &str); 12] = [
    ("kenesset", "Kenesset"),
    ("berit-hadashah", "Berit Hadashah"),
    ("torah", "Torah"),
    ("neviim", "Nevi'im"),
    ("ketouvim", "Ketouvim"),
    ("nistarot", "Nistarot"),
    ("besorot", "Besorot"),
    ("eduyot", "Eduyot"),
    ("trei-asar", "Trei Asar"),
    ("igerot", "Igerot"),
    ("igerot-lifnei-hahurban", "Igerot lifnei haḤurban"),
    ("igerot-aharei-hahurban", "Igerot aḥarei haḤurban"),
];

/// Le titre d'affichage d'un identifiant, à défaut une mise en capitales.
pub fn display_name(id: &str) -> String {
    if let Some((_, nom)) = DISPLAY_NAMES.iter().find(|(k, _)| *k == id) {
        return nom.to_string();
    }
    id.split('-')
        .map(|mot| {
            let mut chars = mot.chars();
            match chars.next() {
                // `to_uppercase` rend un itérateur : une lettre peut en donner
                // plusieurs — « ß » devient « SS ». Ici ce sont des latins
                // simples, mais on ne suppose pas.
                Some(premiere) => premiere.to_uppercase().collect::<String>() + chars.as_str(),
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn les_noms_declares_l_emportent() {
        assert_eq!(display_name("neviim"), "Nevi'im");
        assert_eq!(display_name("trei-asar"), "Trei Asar");
    }

    #[test]
    fn le_reste_se_met_en_capitales() {
        assert_eq!(display_name("bereshit"), "Bereshit");
        assert_eq!(display_name("sefar-gibbaraya"), "Sefar Gibbaraya");
    }
}
