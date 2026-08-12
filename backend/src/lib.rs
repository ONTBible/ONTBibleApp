//! Le backend de La Bible ONT.
//!
//! Architecture hexagonale, comme le proxy de Pinkha : le domaine ignore
//! AWS et axum, l'infrastructure les connaît, et les tests portent sur le
//! domaine avec des doublures en mémoire.
//!
//! Le choix structurant est expliqué dans `domain::token` : on émet nos
//! propres jetons plutôt que de passer par Cognito, dont la facturation *par
//! personne* représenterait 96 % du coût à 50 000 lecteurs.

pub mod application;
pub mod domain;
pub mod infrastructure;
pub mod interface;
