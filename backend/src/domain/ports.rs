//! Les ports — ce que le domaine attend du monde extérieur.
//!
//! Des traits plutôt que des appels directs à DynamoDB ou à reqwest : c'est
//! ce qui permet de tester la logique d'authentification et de fusion sans
//! réseau ni compte AWS. Les implémentations réelles vivent dans
//! `infrastructure/`.

use async_trait::async_trait;

use super::diffusion::{Annonce, Appareil};
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

/// Le registre des appareils à joindre.
///
/// Séparé de `UserRepository` **à dessein**, et pas seulement pour la forme :
/// un appareil n'appartient à personne ici. Mettre ces méthodes sur le dépôt
/// des comptes rendrait la jointure tentante, et un jour quelqu'un la ferait.
#[async_trait]
pub trait AppareilRepository: Send + Sync {
    /// Enregistre, ou recouvre si l'appareil est déjà connu.
    async fn enregistrer(&self, appareil: &Appareil) -> Result<(), DomainError>;

    /// Retire un appareil — au retrait du consentement, ou sur un `410` d'Apple.
    async fn oublier(&self, empreinte: &str) -> Result<(), DomainError>;

    /// Tous les appareils à joindre.
    ///
    /// Une diffusion les prend d'un bloc : il n'y a pas de ciblage, et il ne
    /// doit pas y en avoir. Tout le monde reçoit la même annonce, ou personne.
    async fn tous(&self) -> Result<Vec<Appareil>, DomainError>;
}

/// L'envoi proprement dit, chez Apple.
#[async_trait]
pub trait Notificateur: Send + Sync {
    /// Rend les empreintes des appareils qu'Apple déclare morts — `410 Gone`.
    ///
    /// C'est le seul moyen de purger : un lecteur qui désinstalle l'app ne
    /// peut plus rien retirer lui-même, et son jeton resterait sinon
    /// indéfiniment dans la table.
    async fn diffuser(
        &self,
        appareils: &[Appareil],
        annonce: &Annonce,
    ) -> Result<Vec<String>, DomainError>;
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
