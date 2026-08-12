//! Les ports — ce que le domaine attend du monde extérieur.
//!
//! Des traits plutôt que des appels directs à DynamoDB ou à reqwest : c'est
//! ce qui permet de tester la logique d'authentification et de fusion sans
//! réseau ni compte AWS. Les implémentations réelles vivent dans
//! `infrastructure/`.

use async_trait::async_trait;

use super::sync::{Highlight, Position};
use super::token::UserId;
use super::{DomainError, ExternalIdentity, Provider};

/// Échange un code d'autorisation contre une identité.
///
/// C'est la seule chose qu'on demande à Apple, Google et GitHub — et c'est
/// aussi tout ce qu'on veut savoir d'eux.
#[async_trait]
pub trait IdentityProvider: Send + Sync {
    async fn exchange(
        &self,
        provider: Provider,
        code: &str,
        redirect_uri: &str,
        verifier: Option<&str>,
    ) -> Result<ExternalIdentity, DomainError>;
}

/// Le stockage des comptes et des sessions.
#[async_trait]
pub trait UserRepository: Send + Sync {
    /// Retrouve le compte rattaché à une identité externe, s'il existe.
    async fn find_by_identity(
        &self,
        identity: &ExternalIdentity,
    ) -> Result<Option<UserId>, DomainError>;

    /// Crée le compte et le lie à l'identité externe.
    async fn create(&self, identity: &ExternalIdentity) -> Result<UserId, DomainError>;

    /// Enregistre l'empreinte d'un jeton de rafraîchissement.
    async fn store_refresh(
        &self,
        user: &UserId,
        digest: &str,
        expires_at: i64,
    ) -> Result<(), DomainError>;

    /// Consomme une empreinte : rend le compte, et l'invalide au passage.
    ///
    /// La rotation est délibérée — un jeton de rafraîchissement ne sert
    /// qu'une fois. Si le même est présenté deux fois, c'est qu'il a fuité,
    /// et la seconde présentation échoue.
    async fn consume_refresh(&self, digest: &str) -> Result<UserId, DomainError>;

    /// Efface tout d'un lecteur — comptes, sessions, annotations.
    async fn erase(&self, user: &UserId) -> Result<(), DomainError>;
}

/// Le stockage de ce que le lecteur produit.
#[async_trait]
pub trait SyncRepository: Send + Sync {
    async fn highlights(
        &self,
        user: &UserId,
        since: Option<i64>,
    ) -> Result<Vec<Highlight>, DomainError>;

    async fn position(&self, user: &UserId) -> Result<Option<Position>, DomainError>;

    async fn upsert_highlight(
        &self,
        user: &UserId,
        highlight: &Highlight,
    ) -> Result<(), DomainError>;

    async fn set_position(&self, user: &UserId, position: &Position) -> Result<(), DomainError>;
}

/// L'horloge — injectée pour que les tests d'expiration soient déterministes.
pub trait Clock: Send + Sync {
    fn now(&self) -> time::OffsetDateTime;
}

pub struct SystemClock;

impl Clock for SystemClock {
    fn now(&self) -> time::OffsetDateTime {
        time::OffsetDateTime::now_utc()
    }
}
