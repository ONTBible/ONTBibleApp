//! Les cas d'usage — la logique, sans axum ni AWS.

use std::sync::Arc;

use time::OffsetDateTime;

use crate::domain::ports::{
    AppareilRepository, Clock, IdentityProvider, Notificateur, SyncRepository, UserRepository,
};
use crate::domain::sync::{resolve, ProfilLecteur, PullResponse, PushRequest};
use crate::domain::token::{RefreshToken, TokenIssuer, UserId, REFRESH_TTL};
use crate::domain::{DomainError, ExternalIdentity, Origine, Provider};

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
    /// L'adresse rendue par le fournisseur, quand il en donne une.
    ///
    /// **On la rend, on ne la garde pas.** Le compte est identifié par le
    /// `subject` du fournisseur, jamais par l'adresse : celle-ci change, se
    /// masque — Apple propose un relais —, et n'a de valeur que pour dire au
    /// lecteur *sous quel compte il est connecté*.
    ///
    /// Absente au rafraîchissement, où l'on n'a pas réinterrogé le
    /// fournisseur. Le client conserve alors celle qu'il avait.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub email: Option<String>,
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

        if created {
            self.amorcer_le_profil(&user, &identity).await;
        }

        self.open_session(user, created, identity.email).await
    }

    /// Pose ce que le fournisseur sait du lecteur, **à la création seulement**.
    ///
    /// ## Pourquoi seulement à la création
    ///
    /// Le profil appartient au lecteur dès qu'il existe. Le réécrire à chaque
    /// connexion écraserait le nom qu'il aurait corrigé chez nous par celui de
    /// son compte GitHub, et il verrait sa correction se défaire sans
    /// comprendre — une fois par connexion, sur chacun de ses appareils.
    ///
    /// ## Pourquoi ça n'échoue pas la connexion
    ///
    /// Un profil non amorcé est un profil vide, et un profil vide est un état
    /// parfaitement valide — c'est celui de tout compte créé avant aujourd'hui.
    /// Refuser la connexion pour ça reviendrait à interdire de lire parce qu'on
    /// n'a pas su écrire un prénom.
    ///
    /// L'échec est donc avalé, et c'est l'un des rares endroits où c'est juste :
    /// **ce qu'on tente est une amélioration, pas une étape.**
    async fn amorcer_le_profil(&self, user: &UserId, identity: &ExternalIdentity) {
        let prenom = identity.prenom.clone().unwrap_or_default();
        let nom = identity.nom.clone().unwrap_or_default();
        let bio = identity.bio.clone().unwrap_or_default();
        if prenom.is_empty() && nom.is_empty() && bio.is_empty() {
            return;
        }

        let profil = ProfilLecteur {
            // **Le nom d'usage reste vide.** C'est le seul champ du profil qui
            // soit un identifiant : c'est par lui qu'un lecteur en nommera un
            // autre dans le Qahal. Le déduire du fournisseur poserait un
            // pseudonyme que le lecteur n'a pas choisi, et qui pourrait déjà
            // être pris.
            nom_dusage: String::new(),
            prenom,
            nom,
            bio,
            portrait: None,
            updated_at: self.clock.now().unix_timestamp(),
        };
        let _ = self.sync.set_profil(user, &profil).await;
    }

    /// Rafraîchissement : un jeton long contre une nouvelle paire.
    ///
    /// Le jeton présenté est consommé — il ne resservira pas. Si quelqu'un
    /// rejoue un jeton déjà utilisé, l'opération échoue, ce qui est le signe
    /// d'une fuite.
    pub async fn refresh(&self, token: &str) -> Result<Session, DomainError> {
        let digest = RefreshToken(token.to_string()).digest();
        let user = self.users.consume_refresh(&digest).await?;
        self.open_session(user, false, None).await
    }

    async fn open_session(
        &self,
        user: UserId,
        created: bool,
        email: Option<String>,
    ) -> Result<Session, DomainError> {
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
            email,
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
            // **Le profil ne suit pas `since`.** Il n'y en a qu'un, minuscule,
            // et un client qui l'a déjà ne perd rien à le relire ; en revanche
            // un client qui vient de se connecter sur un appareil neuf a
            // `since` à jour pour tout le reste et repartirait sans son propre
            // nom.
            profil: self.sync.profil(user).await?,
            server_time: millis(self.clock.now()),
        })
    }

    /// Enregistre ce que le client envoie.
    ///
    /// Chaque surlignage est arbitré individuellement contre sa version
    /// serveur : un appareil resté longtemps hors ligne ne doit pas écraser
    /// en bloc ce qu'un autre a fait entre-temps.
    pub async fn push(&self, user: &UserId, request: PushRequest) -> Result<(), DomainError> {
        // Le profil d'abord, et arbitré comme un surlignage : dernier écrit
        // gagné. Un appareil resté longtemps hors ligne ne doit pas réimposer
        // un nom qu'on a changé ailleurs entre-temps.
        if let Some(entrant) = &request.profil {
            if !entrant.portrait_tient() {
                // **Refusé, et nommé.** Laisser DynamoDB échouer rendrait une
                // erreur de stockage, que le client lit comme une panne — et il
                // réessaierait indéfiniment avec la même image.
                tracing::warn!(
                    taille = entrant.portrait.as_ref().map(|p| p.len()),
                    "portrait trop grand — profil refusé"
                );
                return Err(DomainError::PortraitTropGrand);
            }
            let accepte = match self.sync.profil(user).await? {
                Some(serveur) => entrant.updated_at > serveur.updated_at,
                None => true,
            };
            if accepte {
                self.sync.set_profil(user, entrant).await?;
            }
        }

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
