//! La diffusion d'une parution aux appareils.
//!
//! ## Ce qu'on garde, et ce qu'on refuse de garder
//!
//! Un jeton d'appareil, une date, rien d'autre. **Aucun lien avec un compte**,
//! aucune trace de ce qui est lu ni de quand.
//!
//! Ce n'est pas de la frugalité : `DailyVerseNotifications`, côté app, l'écrit
//! depuis le début — tenir une liste de qui lit une Bible, c'est traiter une
//! donnée qui révèle des convictions religieuses, catégorie particulière au
//! sens de l'article 9 du RGPD. Le jeton seul le révèle déjà, et c'est
//! irréductible : sans lui, aucune notification n'est possible. Ce qu'on peut
//! encore décider, c'est de **ne rien y attacher**.
//!
//! D'où trois règles que le code tient plutôt que la documentation :
//!
//! - la clé de tri est l'**empreinte** du jeton, jamais un identifiant de
//!   personne — deux enregistrements du même appareil se recouvrent, et rien
//!   ne relie deux appareils entre eux ;
//! - un jeton expire tout seul. Un lecteur qui désinstalle l'app ne peut plus
//!   rien retirer : sans échéance, son jeton resterait indéfiniment ;
//! - Apple répond `410 Gone` pour un jeton mort, et on le supprime aussitôt.
//!   C'est le seul mécanisme qui purge ce qu'on ne peut plus joindre.

use serde::{Deserialize, Serialize};

/// L'appareil à joindre — un jeton, et rien qui dise qui le porte.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Appareil {
    /// Le jeton APNs, tel qu'iOS le donne : 64 octets en hexadécimal.
    pub jeton: String,
    /// `production` ou `sandbox`. Un jeton de développement est refusé par le
    /// serveur de production, et réciproquement — avec une erreur qui ne dit
    /// pas laquelle des deux causes est en jeu.
    pub environnement: Environnement,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Environnement {
    Production,
    Sandbox,
}

impl Environnement {
    /// L'hôte APNs correspondant.
    pub fn hote(self) -> &'static str {
        match self {
            Self::Production => "api.push.apple.com",
            Self::Sandbox => "api.sandbox.push.apple.com",
        }
    }
}

/// Ce qu'un lecteur verra sur son écran verrouillé.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Annonce {
    pub titre: String,
    pub corps: String,
    /// Le livre à ouvrir quand la notification est touchée. Absent pour une
    /// annonce de lexique.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub livre: Option<String>,
}

impl Appareil {
    /// Un jeton APNs est **exactement** 64 caractères hexadécimaux.
    ///
    /// La validation n'est pas une politesse : sans elle, n'importe quelle
    /// chaîne entrerait dans la table et serait poussée à Apple à chaque
    /// parution, pour un refus à chaque fois. Une route ouverte sans compte
    /// est une porte : elle doit refuser ce qui n'est pas un jeton.
    pub fn valide(&self) -> bool {
        self.jeton.len() == 64 && self.jeton.chars().all(|c| c.is_ascii_hexdigit())
    }

    /// L'empreinte qui sert de clé de tri.
    ///
    /// Le jeton lui-même est stocké — il faut bien l'envoyer — mais il ne sert
    /// pas de clé : une clé se retrouve dans les journaux, les traces, les
    /// messages d'erreur. L'empreinte, elle, n'y révèle rien.
    pub fn empreinte(&self) -> String {
        use sha2::{Digest, Sha256};
        let mut h = Sha256::new();
        h.update(self.jeton.as_bytes());
        format!("{:x}", h.finalize())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn jeton(c: char) -> Appareil {
        Appareil {
            jeton: std::iter::repeat_n(c, 64).collect(),
            environnement: Environnement::Production,
        }
    }

    #[test]
    fn un_jeton_de_soixante_quatre_hexa_est_valide() {
        assert!(jeton('a').valide());
    }

    #[test]
    fn ce_qui_n_est_pas_un_jeton_est_refuse() {
        let court = Appareil {
            jeton: "abcd".into(),
            environnement: Environnement::Production,
        };
        assert!(!court.valide());
        assert!(!jeton('z').valide(), "z n'est pas hexadécimal");
    }

    /// Deux enregistrements du même appareil doivent se recouvrir, sans quoi
    /// un lecteur qui rouvre l'app chaque jour multiplierait ses jetons — et
    /// recevrait la même parution autant de fois.
    #[test]
    fn le_meme_jeton_donne_la_meme_empreinte() {
        assert_eq!(jeton('a').empreinte(), jeton('a').empreinte());
        assert_ne!(jeton('a').empreinte(), jeton('b').empreinte());
    }

    #[test]
    fn les_deux_environnements_ont_des_hotes_distincts() {
        assert_ne!(
            Environnement::Production.hote(),
            Environnement::Sandbox.hote()
        );
    }
}
