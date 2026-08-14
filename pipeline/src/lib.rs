//! Le pipeline ONT — le vault devient des données consommables par une liseuse.
//!
//! ## Pourquoi c'est une bibliothèque et pas seulement un programme
//!
//! Le schéma était décrit **trois fois** : ici, dans le site en Rust, dans
//! l'app en Swift. Trois définitions du même contrat finissent par diverger, et
//! quand elles divergent le défaut est muet — la liseuse qui ne connaît pas un
//! type de nœud l'omet, la page s'affiche, et il manque un mot.
//!
//! Le site dépend désormais de `schema` directement, par chemin : les deux
//! dépôts sont côte à côte, en local comme dans la CI. Il en reste deux
//! descriptions, et le Swift est le prochain chantier.

//! ## Ce que le site prend, et ce qu'il ne prend pas
//!
//! `schema` est toujours là. Le reste — tout ce qui *fabrique* les données —
//! est derrière la fonctionnalité `parsers`, active par défaut. Le site déclare
//! `default-features = false` : il lit du JSON déjà produit, et n'a que faire
//! du tokeniseur ni des tables Unicode de `regex` dans un binaire Lambda dont
//! le démarrage à froid se compte déjà en centaines de millisecondes.

pub mod schema;

#[cfg(feature = "parsers")]
pub mod blocks;
#[cfg(feature = "parsers")]
pub mod build;
#[cfg(feature = "parsers")]
pub mod chapter;
#[cfg(feature = "parsers")]
pub mod config;
#[cfg(feature = "parsers")]
pub mod inline;
#[cfg(feature = "parsers")]
pub mod reference;
#[cfg(feature = "parsers")]
pub mod search;
#[cfg(feature = "parsers")]
pub mod vault;
