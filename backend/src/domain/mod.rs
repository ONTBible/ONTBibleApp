//! Le domaine — ce que le backend sait, indépendamment d'AWS et d'axum.

pub mod diffusion;
pub mod ports;
pub mod sync;
pub mod token;

use serde::{Deserialize, Serialize};

/// Les fournisseurs d'identité acceptés.
///
/// « Sign in with Apple » figure en premier parce que la revue App Store
/// l'exige dès qu'un autre fournisseur tiers est proposé — ce n'est pas une
/// préférence, c'est une règle de publication.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Provider {
    Apple,
    Google,
    Github,
}

impl Provider {
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "apple" => Some(Self::Apple),
            "google" => Some(Self::Google),
            "github" => Some(Self::Github),
            _ => None,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Apple => "apple",
            Self::Google => "google",
            Self::Github => "github",
        }
    }
}

/// Ce qu'un fournisseur nous apprend d'une personne.
///
/// Volontairement maigre. On ne demande que ce dont on a besoin pour
/// reconnaître quelqu'un d'une session à l'autre — la minimisation n'est pas
/// qu'une exigence du RGPD, c'est aussi ce qui limite les dégâts d'une fuite.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExternalIdentity {
    pub provider: Provider,
    /// L'identifiant stable chez le fournisseur.
    pub subject: String,
    /// Facultatif — Apple ne le donne qu'à la toute première autorisation, et
    /// GitHub seulement si l'adresse est publique.
    pub email: Option<String>,
}

impl ExternalIdentity {
    /// La clé de recherche « ce fournisseur, cette personne ».
    pub fn key(&self) -> String {
        format!("IDP#{}#{}", self.provider.as_str(), self.subject)
    }
}

#[derive(Debug, thiserror::Error)]
pub enum DomainError {
    #[error("le fournisseur a refusé le code d'autorisation")]
    ProviderRejected,
    /// Le fournisseur n'a **pas** d'identifiants sur ce déploiement.
    ///
    /// Distinct de [`ProviderRejected`], et la distinction n'est pas cosmétique :
    /// un identifiant absent était rapporté comme un refus, c'est-à-dire comme
    /// le résultat d'un échange **qui n'a jamais eu lieu**. Celui qui exploite
    /// voyait alors exactement ce que voit un lecteur dont le code a expiré, et
    /// n'avait aucun moyen de distinguer « j'ai oublié le secret » de « ce code
    /// est périmé ».
    ///
    /// Il ne renseigne pas un attaquant : la liste des fournisseurs proposés est
    /// déjà publique — l'écran de connexion la montre. Savoir que l'un d'eux
    /// n'est pas installé sur ce déploiement ne donne aucune prise.
    #[error("le fournisseur n'est pas configuré sur ce déploiement")]
    ProviderNotConfigured,
    #[error("le fournisseur est injoignable")]
    ProviderUnreachable,
    #[error("session inconnue ou révoquée")]
    SessionInvalid,
    #[error("erreur de stockage")]
    Storage,
    /// Une panne de la chaîne de notification — clé illisible, signature
    /// impossible, charge non sérialisable.
    ///
    /// Distincte de `Storage` : celle-ci ne dit rien au lecteur et ne doit
    /// jamais faire échouer autre chose. Une parution non annoncée est un
    /// agrément perdu ; le texte, lui, est arrivé.
    #[error("la notification n'a pas pu partir : {0}")]
    Notification(String),
}
