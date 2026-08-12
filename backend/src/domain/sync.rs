//! Ce que le lecteur produit, et qui doit suivre d'un appareil à l'autre.
//!
//! **Attention — données de catégorie particulière.** Les surlignages et les
//! notes d'un lecteur de Bible, rattachés à une identité, révèlent des
//! convictions religieuses : article 9 du RGPD. Conséquences inscrites dans
//! la conception :
//!
//! - la synchronisation est **facultative** — l'app fonctionne entièrement
//!   sans compte, et c'est le comportement par défaut ;
//! - on stocke le strict nécessaire : pas de texte du verset, seulement sa
//!   *référence*. Le corpus est déjà dans l'app.
//! - tout est effaçable d'un coup (`DELETE /me`).

use serde::{Deserialize, Serialize};

/// Un surlignage, posé sur un verset.
///
/// La référence est `(unité, verset)` et jamais un décalage de caractères :
/// une révision du texte déplacerait les caractères et rendrait le
/// surlignage faux, alors qu'un numéro de verset reste juste.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Highlight {
    pub id: String,
    pub book_id: String,
    pub chapter_id: String,
    pub verse: u32,
    pub color: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
    /// Millisecondes epoch — sert d'arbitre en cas de conflit.
    pub updated_at: i64,
    /// Un objet supprimé est conservé comme pierre tombale jusqu'à son TTL :
    /// sans ça, un appareil resté hors ligne ressusciterait ce qu'un autre
    /// vient d'effacer.
    #[serde(default)]
    pub deleted: bool,
}

impl Highlight {
    pub fn sort_key(&self) -> String {
        format!("HL#{}#{:05}", self.chapter_id, self.verse)
    }
}

/// Où le lecteur en était.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Position {
    pub book_id: String,
    pub chapter_id: String,
    pub chapter_title: String,
    pub verse: u32,
    pub updated_at: i64,
}

/// Ce que le client envoie.
#[derive(Debug, Clone, Deserialize)]
pub struct PushRequest {
    #[serde(default)]
    pub highlights: Vec<Highlight>,
    #[serde(default)]
    pub position: Option<Position>,
}

/// Ce que le client reçoit.
#[derive(Debug, Clone, Serialize)]
pub struct PullResponse {
    pub highlights: Vec<Highlight>,
    pub position: Option<Position>,
    /// L'horodatage du serveur — le client le renvoie au prochain `since`.
    pub server_time: i64,
}

/// Arbitre un conflit entre deux versions du même objet.
///
/// **Dernier écrit gagné**, arbitré par `updated_at`. C'est le bon compromis
/// ici : un surlignage est un objet minuscule, sans structure interne, qu'une
/// seule personne modifie depuis ses propres appareils. Une fusion à trois
/// branches serait de la complexité sans bénéfice — personne ne modifie
/// simultanément la couleur d'un même verset sur deux téléphones.
///
/// À égalité d'horodatage, le serveur garde sa version : deux appareils dont
/// les horloges concordent à la milliseconde près sont plus probablement le
/// même écrit rejoué qu'un vrai conflit.
pub fn resolve(server: &Highlight, incoming: &Highlight) -> bool {
    incoming.updated_at > server.updated_at
}

#[cfg(test)]
mod tests {
    use super::*;

    fn highlight(updated_at: i64, color: &str) -> Highlight {
        Highlight {
            id: "1".into(),
            book_id: "bereshit".into(),
            chapter_id: "bereshit-18".into(),
            verse: 19,
            color: color.into(),
            note: None,
            updated_at,
            deleted: false,
        }
    }

    #[test]
    fn le_plus_recent_gagne() {
        let server = highlight(1_000, "gold");
        let incoming = highlight(2_000, "sky");
        assert!(resolve(&server, &incoming));
    }

    #[test]
    fn un_ecrit_plus_ancien_est_ignore() {
        let server = highlight(2_000, "gold");
        let incoming = highlight(1_000, "sky");
        assert!(!resolve(&server, &incoming));
    }

    #[test]
    fn a_egalite_le_serveur_garde_sa_version() {
        let server = highlight(1_000, "gold");
        let incoming = highlight(1_000, "sky");
        assert!(!resolve(&server, &incoming));
    }

    #[test]
    fn la_cle_de_tri_ordonne_les_versets_numeriquement() {
        // Sans le remplissage à cinq chiffres, le verset 10 se rangerait avant
        // le verset 9 — l'ordre lexicographique de DynamoDB n'est pas
        // l'ordre numérique.
        let mut keys = vec![
            highlight_at(9).sort_key(),
            highlight_at(10).sort_key(),
            highlight_at(2).sort_key(),
        ];
        keys.sort();

        assert_eq!(
            keys,
            vec![
                highlight_at(2).sort_key(),
                highlight_at(9).sort_key(),
                highlight_at(10).sort_key(),
            ]
        );
    }

    fn highlight_at(verse: u32) -> Highlight {
        Highlight {
            verse,
            ..highlight(0, "gold")
        }
    }
}
