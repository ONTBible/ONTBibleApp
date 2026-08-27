//! Les cas d'usage — la logique, sans axum ni AWS.

use std::sync::Arc;

use time::OffsetDateTime;

use crate::domain::ports::{
    AppareilRepository, Clock, IdentityProvider, Notificateur, SyncRepository, UserRepository,
};
use crate::domain::sync::{resolve, PullResponse, PushRequest};
use crate::domain::token::{RefreshToken, TokenIssuer, UserId, REFRESH_TTL};
use crate::domain::{DomainError, Origine, Provider};

/// Ce qu'une connexion réussie rend au client.
#[derive(Debug, Clone, serde::Serialize)]
pub struct Session {
    pub access_token: String,
    pub refresh_token: String,
    /// Secondes avant expiration du jeton d'accès.
    pub expires_in: i64,
    /// Vrai si le compte vient d'être créé — le client peut alors proposer
    /// de téléverser les annotations déjà prises hors ligne.
    pub created: bool,
}

#[derive(Clone)]
pub struct App {
    pub identity: Arc<dyn IdentityProvider>,
    /// Le registre des appareils. `None` tant que la clé APNs n'est pas
    /// fournie : les routes répondent alors `503`, et le reste du backend
    /// fonctionne — une notification manquante ne doit pas empêcher de lire.
    pub appareils: Option<Arc<dyn AppareilRepository>>,
    pub notificateur: Option<Arc<dyn Notificateur>>,
    /// Le secret que le déploiement présente pour déclencher une diffusion.
    pub secret_diffusion: Option<String>,
    pub users: Arc<dyn UserRepository>,
    pub sync: Arc<dyn SyncRepository>,
    pub tokens: TokenIssuer,
    pub clock: Arc<dyn Clock>,
}

impl App {
    /// Connexion : code d'autorisation → session.
    ///
    /// Le compte est créé à la volée si l'identité est inconnue. Aucun
    /// formulaire d'inscription : le fournisseur a déjà fait le travail, en
    /// demander plus ne servirait qu'à collecter des données dont on n'a pas
    /// l'usage.
    pub async fn sign_in(
        &self,
        provider: Provider,
        origine: Origine,
        code: &str,
        redirect_uri: &str,
        verifier: Option<&str>,
    ) -> Result<Session, DomainError> {
        let identity = self
            .identity
            .exchange(provider, origine, code, redirect_uri, verifier)
            .await?;

        let (user, created) = match self.users.find_by_identity(&identity).await? {
            Some(existing) => (existing, false),
            None => (self.users.create(&identity).await?, true),
        };

        self.open_session(user, created).await
    }

    /// Rafraîchissement : un jeton long contre une nouvelle paire.
    ///
    /// Le jeton présenté est consommé — il ne resservira pas. Si quelqu'un
    /// rejoue un jeton déjà utilisé, l'opération échoue, ce qui est le signe
    /// d'une fuite.
    pub async fn refresh(&self, token: &str) -> Result<Session, DomainError> {
        let digest = RefreshToken(token.to_string()).digest();
        let user = self.users.consume_refresh(&digest).await?;
        self.open_session(user, false).await
    }

    async fn open_session(&self, user: UserId, created: bool) -> Result<Session, DomainError> {
        let now = self.clock.now();

        let access = self
            .tokens
            .issue(&user, now)
            .map_err(|_| DomainError::SessionInvalid)?;

        let refresh = RefreshToken::generate();
        let expires_at = (now + REFRESH_TTL).unix_timestamp();
        self.users
            .store_refresh(&user, &refresh.digest(), expires_at)
            .await?;

        Ok(Session {
            access_token: access,
            refresh_token: refresh.0,
            expires_in: crate::domain::token::ACCESS_TTL.whole_seconds(),
            created,
        })
    }

    /// Récupère ce qui a changé depuis `since`.
    pub async fn pull(
        &self,
        user: &UserId,
        since: Option<i64>,
    ) -> Result<PullResponse, DomainError> {
        Ok(PullResponse {
            highlights: self.sync.highlights(user, since).await?,
            position: self.sync.position(user).await?,
            server_time: millis(self.clock.now()),
        })
    }

    /// Enregistre ce que le client envoie.
    ///
    /// Chaque surlignage est arbitré individuellement contre sa version
    /// serveur : un appareil resté longtemps hors ligne ne doit pas écraser
    /// en bloc ce qu'un autre a fait entre-temps.
    pub async fn push(&self, user: &UserId, request: PushRequest) -> Result<(), DomainError> {
        let existing = self.sync.highlights(user, None).await?;

        for incoming in &request.highlights {
            let current = existing
                .iter()
                .find(|candidate| candidate.sort_key() == incoming.sort_key());

            let accept = match current {
                Some(server) => resolve(server, incoming),
                None => true,
            };
            if accept {
                self.sync.upsert_highlight(user, incoming).await?;
            }
        }

        if let Some(position) = &request.position {
            let current = self.sync.position(user).await?;
            let accept = current
                .map(|server| position.updated_at > server.updated_at)
                .unwrap_or(true);
            if accept {
                self.sync.set_position(user, position).await?;
            }
        }

        Ok(())
    }

    /// Efface le compte et tout ce qui s'y rattache.
    ///
    /// Exigé par le RGPD, et d'autant moins négociable que ces données
    /// relèvent de l'article 9.
    pub async fn erase(&self, user: &UserId) -> Result<(), DomainError> {
        self.users.erase(user).await
    }
}

fn millis(time: OffsetDateTime) -> i64 {
    time.unix_timestamp() * 1_000 + i64::from(time.millisecond())
}

#[cfg(test)]
mod tests;
