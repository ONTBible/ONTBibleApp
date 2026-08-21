//! Les cas d'usage, éprouvés sur des doublures en mémoire.
//!
//! Aucun réseau, aucun compte AWS : c'est tout l'intérêt des ports. On teste
//! la logique — rotation des jetons, arbitrage des conflits, création de
//! compte — et non la capacité d'AWS à répondre.

use std::collections::HashMap;
use std::sync::Mutex;

use super::*;
use crate::domain::sync::{Highlight, Position};
use crate::domain::ExternalIdentity;

// ─────────────────────────────────────────────────────────────────────────────
// Doublures
// ─────────────────────────────────────────────────────────────────────────────

struct FakeProvider {
    identity: ExternalIdentity,
    accept: bool,
}

#[async_trait::async_trait]
impl IdentityProvider for FakeProvider {
    async fn exchange(
        &self,
        _provider: Provider,
        _code: &str,
        _redirect_uri: &str,
        _verifier: Option<&str>,
    ) -> Result<ExternalIdentity, DomainError> {
        if self.accept {
            Ok(self.identity.clone())
        } else {
            Err(DomainError::ProviderRejected)
        }
    }
}

#[derive(Default)]
struct FakeUsers {
    identities: Mutex<HashMap<String, UserId>>,
    refresh: Mutex<HashMap<String, UserId>>,
    erased: Mutex<Vec<UserId>>,
}

#[async_trait::async_trait]
impl UserRepository for FakeUsers {
    async fn find_by_identity(
        &self,
        identity: &ExternalIdentity,
    ) -> Result<Option<UserId>, DomainError> {
        Ok(self
            .identities
            .lock()
            .unwrap()
            .get(&identity.key())
            .cloned())
    }

    async fn create(&self, identity: &ExternalIdentity) -> Result<UserId, DomainError> {
        let user = UserId::new();
        self.identities
            .lock()
            .unwrap()
            .insert(identity.key(), user.clone());
        Ok(user)
    }

    async fn store_refresh(
        &self,
        user: &UserId,
        digest: &str,
        _expires_at: i64,
    ) -> Result<(), DomainError> {
        self.refresh
            .lock()
            .unwrap()
            .insert(digest.to_string(), user.clone());
        Ok(())
    }

    async fn consume_refresh(&self, digest: &str) -> Result<UserId, DomainError> {
        self.refresh
            .lock()
            .unwrap()
            .remove(digest)
            .ok_or(DomainError::SessionInvalid)
    }

    async fn erase(&self, user: &UserId) -> Result<(), DomainError> {
        self.erased.lock().unwrap().push(user.clone());
        Ok(())
    }
}

#[derive(Default)]
struct FakeSync {
    highlights: Mutex<Vec<Highlight>>,
    position: Mutex<Option<Position>>,
}

#[async_trait::async_trait]
impl SyncRepository for FakeSync {
    async fn highlights(
        &self,
        _user: &UserId,
        since: Option<i64>,
    ) -> Result<Vec<Highlight>, DomainError> {
        let all = self.highlights.lock().unwrap().clone();
        Ok(match since {
            Some(cutoff) => all.into_iter().filter(|h| h.updated_at > cutoff).collect(),
            None => all,
        })
    }

    async fn position(&self, _user: &UserId) -> Result<Option<Position>, DomainError> {
        Ok(self.position.lock().unwrap().clone())
    }

    async fn upsert_highlight(
        &self,
        _user: &UserId,
        highlight: &Highlight,
    ) -> Result<(), DomainError> {
        let mut all = self.highlights.lock().unwrap();
        match all
            .iter_mut()
            .find(|h| h.sort_key() == highlight.sort_key())
        {
            Some(existing) => *existing = highlight.clone(),
            None => all.push(highlight.clone()),
        }
        Ok(())
    }

    async fn set_position(&self, _user: &UserId, position: &Position) -> Result<(), DomainError> {
        *self.position.lock().unwrap() = Some(position.clone());
        Ok(())
    }
}

struct FixedClock(OffsetDateTime);

impl Clock for FixedClock {
    fn now(&self) -> OffsetDateTime {
        self.0
    }
}

// ─────────────────────────────────────────────────────────────────────────────

fn identity() -> ExternalIdentity {
    ExternalIdentity {
        provider: Provider::Apple,
        subject: "001234.abcdef".into(),
        email: Some("lecteur@example.com".into()),
    }
}

fn app(accept: bool) -> (App, Arc<FakeUsers>, Arc<FakeSync>) {
    let users = Arc::new(FakeUsers::default());
    let sync = Arc::new(FakeSync::default());

    let app = App {
        // La diffusion n'est pas branchée dans ces tests : ils portent sur
        // l'authentification et la synchronisation, où un appareil n'a rien à
        // faire. `None` est ici l'état correct, pas un raccourci.
        appareils: None,
        notificateur: None,
        secret_diffusion: None,
        identity: Arc::new(FakeProvider {
            identity: identity(),
            accept,
        }),
        users: users.clone(),
        sync: sync.clone(),
        tokens: TokenIssuer::new("secret-de-test"),
        clock: Arc::new(FixedClock(OffsetDateTime::now_utc())),
    };
    (app, users, sync)
}

fn highlight(verse: u32, color: &str, updated_at: i64) -> Highlight {
    Highlight {
        id: format!("h{verse}"),
        book_id: "bereshit".into(),
        chapter_id: "bereshit-18".into(),
        verse,
        color: color.into(),
        note: None,
        updated_at,
        deleted: false,
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Connexion
// ─────────────────────────────────────────────────────────────────────────────

#[tokio::test]
async fn une_premiere_connexion_cree_le_compte() {
    let (app, _, _) = app(true);

    let session = app
        .sign_in(Provider::Apple, "code", "uri", None)
        .await
        .unwrap();

    assert!(session.created, "le compte doit être signalé comme neuf");
    assert!(app.tokens.verify(&session.access_token).is_ok());
}

#[tokio::test]
async fn une_seconde_connexion_retrouve_le_meme_compte() {
    let (app, _, _) = app(true);

    let first = app
        .sign_in(Provider::Apple, "code", "uri", None)
        .await
        .unwrap();
    let second = app
        .sign_in(Provider::Apple, "code", "uri", None)
        .await
        .unwrap();

    assert!(!second.created);
    assert_eq!(
        app.tokens.verify(&first.access_token).unwrap(),
        app.tokens.verify(&second.access_token).unwrap(),
        "la même identité externe doit rendre le même compte"
    );
}

#[tokio::test]
async fn un_code_refuse_par_le_fournisseur_ne_cree_rien() {
    let (app, users, _) = app(false);

    assert!(app
        .sign_in(Provider::Apple, "code", "uri", None)
        .await
        .is_err());
    assert!(users.identities.lock().unwrap().is_empty());
}

// ─────────────────────────────────────────────────────────────────────────────
// Rafraîchissement
// ─────────────────────────────────────────────────────────────────────────────

#[tokio::test]
async fn un_jeton_de_rafraichissement_rend_une_nouvelle_paire() {
    let (app, _, _) = app(true);
    let session = app
        .sign_in(Provider::Apple, "code", "uri", None)
        .await
        .unwrap();

    let renewed = app.refresh(&session.refresh_token).await.unwrap();

    assert!(app.tokens.verify(&renewed.access_token).is_ok());
    assert_ne!(renewed.refresh_token, session.refresh_token);
}

#[tokio::test]
async fn un_jeton_de_rafraichissement_ne_sert_qu_une_fois() {
    let (app, _, _) = app(true);
    let session = app
        .sign_in(Provider::Apple, "code", "uri", None)
        .await
        .unwrap();

    app.refresh(&session.refresh_token).await.unwrap();

    // Rejouer le même jeton est le signe d'une fuite : ça doit échouer.
    assert!(app.refresh(&session.refresh_token).await.is_err());
}

#[tokio::test]
async fn un_jeton_de_rafraichissement_inventé_est_rejeté() {
    let (app, _, _) = app(true);
    assert!(app.refresh("pas-un-vrai-jeton").await.is_err());
}

// ─────────────────────────────────────────────────────────────────────────────
// Synchronisation
// ─────────────────────────────────────────────────────────────────────────────

#[tokio::test]
async fn un_ecrit_plus_recent_ecrase_le_serveur() {
    let (app, _, sync) = app(true);
    let user = UserId::new();

    app.push(
        &user,
        PushRequest {
            highlights: vec![highlight(19, "gold", 1_000)],
            position: None,
        },
    )
    .await
    .unwrap();

    app.push(
        &user,
        PushRequest {
            highlights: vec![highlight(19, "sky", 2_000)],
            position: None,
        },
    )
    .await
    .unwrap();

    let stored = sync.highlights.lock().unwrap();
    assert_eq!(stored.len(), 1, "le même verset ne doit pas se dédoubler");
    assert_eq!(stored[0].color, "sky");
}

#[tokio::test]
async fn un_appareil_en_retard_n_ecrase_pas_le_serveur() {
    let (app, _, sync) = app(true);
    let user = UserId::new();

    app.push(
        &user,
        PushRequest {
            highlights: vec![highlight(19, "sky", 2_000)],
            position: None,
        },
    )
    .await
    .unwrap();

    // Un appareil resté hors ligne renvoie une version plus ancienne.
    app.push(
        &user,
        PushRequest {
            highlights: vec![highlight(19, "gold", 1_000)],
            position: None,
        },
    )
    .await
    .unwrap();

    assert_eq!(sync.highlights.lock().unwrap()[0].color, "sky");
}

#[tokio::test]
async fn la_recuperation_incrementale_ne_rend_que_les_changements() {
    let (app, _, _) = app(true);
    let user = UserId::new();

    app.push(
        &user,
        PushRequest {
            highlights: vec![highlight(1, "gold", 1_000), highlight(2, "sky", 3_000)],
            position: None,
        },
    )
    .await
    .unwrap();

    let all = app.pull(&user, None).await.unwrap();
    assert_eq!(all.highlights.len(), 2);

    let recent = app.pull(&user, Some(2_000)).await.unwrap();
    assert_eq!(recent.highlights.len(), 1);
    assert_eq!(recent.highlights[0].verse, 2);
}

#[tokio::test]
async fn effacer_le_compte_est_transmis_au_stockage() {
    let (app, users, _) = app(true);
    let user = UserId::new();

    app.erase(&user).await.unwrap();

    assert_eq!(users.erased.lock().unwrap().as_slice(), &[user]);
}
