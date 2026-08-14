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

pub mod blocks;
pub mod chapter;
pub mod inline;
pub mod schema;
pub mod vault;
