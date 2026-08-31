//! Les cas d'usage, éprouvés sur des doublures en mémoire.
//!
//! Aucun réseau, aucun compte AWS : c'est tout l'intérêt des ports. On teste
//! la logique — rotation des jetons, arbitrage des conflits, création de
//! compte — et non la capacité d'AWS à répondre.

use std::collections::HashMap;
use std::sync::Mutex;

use super::*;
use crate::domain::sync::{Highlight, Position, ProfilLecteur};
use crate::domain::ExternalIdentity;

// ─────────────────────────────────────────────────────────────────────────────
// Doublures
// ─────────────────────────────────────────────────────────────────────────────

pub(crate) struct FakeProvider {
    identity: ExternalIdentity,
    accept: bool,
}

#[async_trait::async_trait]
impl IdentityProvider for FakeProvider {
    async fn exchange(
        &self,
        _provider: Provider,
        _origine: Origine,
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
pub(crate) struct FakeUsers {
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
pub(crate) struct FakeSync {
    highlights: Mutex<Vec<Highlight>>,
    position: Mutex<Option<Position>>,
    profil: Mutex<Option<ProfilLecteur>>,
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

    async fn profil(&self, _user: &UserId) -> Result<Option<ProfilLecteur>, DomainError> {
        Ok(self.profil.lock().unwrap().clone())
    }

    async fn set_profil(&self, _user: &UserId, profil: &ProfilLecteur) -> Result<(), DomainError> {
        *self.profil.lock().unwrap() = Some(profil.clone());
        Ok(())
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

pub(crate) struct FixedClock(OffsetDateTime);

impl Clock for FixedClock {
    fn now(&self) -> OffsetDateTime {
        self.0
    }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Une identité **sans nom** — celle d'Apple, qui n'en donne jamais au serveur.
fn identity() -> ExternalIdentity {
    ExternalIdentity {
        provider: Provider::Apple,
        subject: "001234.abcdef".into(),
        email: Some("lecteur@example.com".into()),
        prenom: None,
        nom: None,
        bio: None,
    }
}

/// Une identité **avec un nom** — celle de Google ou de GitHub.
fn identite_nommee() -> ExternalIdentity {
    ExternalIdentity {
        provider: Provider::Google,
        subject: "google-001".into(),
        email: Some("lecteur@example.com".into()),
        prenom: Some("Gloire".into()),
        nom: Some("Bikouta".into()),
        bio: None,
    }
}

fn app(accept: bool) -> (App, Arc<FakeUsers>, Arc<FakeSync>) {
    app_avec(identity(), accept)
}

/// Le même montage, avec l'identité qu'on veut éprouver.
fn app_avec(identite: ExternalIdentity, accept: bool) -> (App, Arc<FakeUsers>, Arc<FakeSync>) {
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
            identity: identite,
            accept,
        }),
        users: users.clone(),
        sync: sync.clone(),
        tokens: TokenIssuer::new("secret-de-test"),
        clock: Arc::new(FixedClock(OffsetDateTime::now_utc())),
        // Ces épreuves portent sur l'authentification et la synchronisation,
        // pas sur ce qui est installé : on offre tout, pour que l'offre ne soit
        // jamais la raison d'un échec ici.
        capacites: crate::domain::capacites::Capacite::CONNUES
            .into_iter()
            .collect(),
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
        .sign_in(Provider::Apple, Origine::App, "code", "uri", None)
        .await
        .unwrap();

    assert!(session.created, "le compte doit être signalé comme neuf");
    assert!(app.tokens.verify(&session.access_token).is_ok());
}

#[tokio::test]
async fn une_seconde_connexion_retrouve_le_meme_compte() {
    let (app, _, _) = app(true);

    let first = app
        .sign_in(Provider::Apple, Origine::App, "code", "uri", None)
        .await
        .unwrap();
    let second = app
        .sign_in(Provider::Apple, Origine::App, "code", "uri", None)
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
        .sign_in(Provider::Apple, Origine::App, "code", "uri", None)
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
        .sign_in(Provider::Apple, Origine::App, "code", "uri", None)
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
        .sign_in(Provider::Apple, Origine::App, "code", "uri", None)
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
            profil: None,
        },
    )
    .await
    .unwrap();

    app.push(
        &user,
        PushRequest {
            highlights: vec![highlight(19, "sky", 2_000)],
            position: None,
            profil: None,
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
            profil: None,
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
            profil: None,
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
            profil: None,
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

// ─────────────────────────────────────────────────────────────────────────────
// Le profil du lecteur
// ─────────────────────────────────────────────────────────────────────────────

/// Une requête qui ne porte **que** le profil.
fn avec(profil: ProfilLecteur) -> PushRequest {
    PushRequest {
        highlights: vec![],
        position: None,
        profil: Some(profil),
    }
}

fn profil(updated_at: i64, prenom: &str) -> ProfilLecteur {
    ProfilLecteur {
        nom_dusage: "gloiiire_".into(),
        prenom: prenom.into(),
        nom: "Bikouta".into(),
        bio: String::new(),
        portrait: None,
        updated_at,
    }
}

/// **Le profil s'arbitre comme un surlignage** : dernier écrit gagné.
///
/// Un appareil resté longtemps hors ligne ne doit pas réimposer un nom
/// qu'on a changé ailleurs entre-temps.
#[tokio::test]
async fn le_profil_le_plus_recent_gagne() {
    let (app, _, _) = app(true);
    let lecteur = UserId::new();

    app.push(&lecteur, avec(profil(200, "Gloire")))
        .await
        .unwrap();
    app.push(&lecteur, avec(profil(100, "Ancien")))
        .await
        .unwrap();

    let rendu = app.pull(&lecteur, None).await.unwrap().profil.unwrap();
    assert_eq!(rendu.prenom, "Gloire");
}

/// Et il descend **sans condition de `since`**.
///
/// Un appareil neuf reçoit `since` à jour pour tout le reste ; s'il était
/// filtré comme les surlignages, le lecteur repartirait sans son propre nom.
#[tokio::test]
async fn le_profil_descend_meme_avec_un_since_recent() {
    let (app, _, _) = app(true);
    let lecteur = UserId::new();
    app.push(&lecteur, avec(profil(100, "Gloire")))
        .await
        .unwrap();

    let rendu = app.pull(&lecteur, Some(9_999_999)).await.unwrap();
    assert!(rendu.profil.is_some(), "le profil a été filtré par `since`");
}

/// **Un portrait trop grand est refusé, et nommé.**
///
/// Laisser DynamoDB échouer rendrait une erreur de stockage, que le client
/// lit comme une panne du serveur — et il réessaierait indéfiniment avec la
/// même image.
#[tokio::test]
async fn un_portrait_trop_grand_est_refuse() {
    let (app, _, _) = app(true);
    let lecteur = UserId::new();

    let mut trop = profil(100, "Gloire");
    trop.portrait = Some("A".repeat(crate::domain::sync::PORTRAIT_MAX + 1));

    let erreur = app
        .push(&lecteur, avec(trop))
        .await
        .expect_err("un portrait hors borne ne peut pas être accepté");
    assert!(matches!(erreur, DomainError::PortraitTropGrand));

    // Et rien n'a été écrit : un envoi refusé ne laisse pas la moitié de
    // lui-même derrière lui.
    assert!(app.pull(&lecteur, None).await.unwrap().profil.is_none());
}

// ─────────────────────────────────────────────────────────────────────────────
// Le profil amorcé par le fournisseur

/// **Ce que Google et GitHub savent, le compte le sait dès sa première ligne.**
///
/// Sans ça, un lecteur qui vient de se connecter voit « Vous » dans sa barre
/// latérale alors que son fournisseur venait de dire comment il s'appelle. On
/// lui demanderait de retaper ce qu'on avait sous la main.
#[tokio::test]
async fn un_compte_neuf_porte_le_nom_du_fournisseur() {
    let (app, _, sync) = app_avec(identite_nommee(), true);

    let session = app
        .sign_in(Provider::Google, Origine::App, "code", "app://retour", None)
        .await
        .expect("la connexion aboutit");
    assert!(session.created, "le compte est neuf");

    let profil = sync
        .profil(&UserId("peu-importe".into()))
        .await
        .unwrap()
        .expect("le profil a été amorcé");
    assert_eq!(profil.prenom, "Gloire");
    assert_eq!(profil.nom, "Bikouta");
}

/// **Le nom d'usage n'est jamais deviné.**
///
/// C'est le seul champ du profil qui soit un identifiant : c'est par lui qu'un
/// lecteur en nommera un autre dans le Qahal. Le déduire du fournisseur
/// poserait un pseudonyme que le lecteur n'a pas choisi, et qui pourrait déjà
/// être pris par quelqu'un d'autre.
#[tokio::test]
async fn le_nom_d_usage_reste_au_lecteur() {
    let (app, _, sync) = app_avec(identite_nommee(), true);

    app.sign_in(Provider::Google, Origine::App, "code", "app://retour", None)
        .await
        .unwrap();

    let profil = sync.profil(&UserId("x".into())).await.unwrap().unwrap();
    assert!(profil.nom_dusage.is_empty());
}

/// **Apple ne donne rien au serveur, et on n'écrit donc rien.**
///
/// Écrire un profil vide serait pire que ne rien écrire : il porterait une date
/// de mise à jour, et la fusion — dernier écrit gagné — ferait alors effacer par
/// le serveur le nom que le client venait de poser. Apple ne donne le nom qu'au
/// client, et c'est lui qui l'écrit.
#[tokio::test]
async fn une_identite_sans_nom_n_ecrit_aucun_profil() {
    let (app, _, sync) = app(true);

    app.sign_in(Provider::Apple, Origine::App, "code", "app://retour", None)
        .await
        .unwrap();

    assert!(
        sync.profil(&UserId("x".into())).await.unwrap().is_none(),
        "aucun profil ne doit être écrit quand le fournisseur ne dit rien"
    );
}

/// **Une reconnexion ne réécrit pas le profil.**
///
/// Le profil appartient au lecteur dès qu'il existe. Le réécrire à chaque
/// connexion écraserait le nom qu'il aurait corrigé chez nous par celui de son
/// compte GitHub — une fois par connexion, sur chacun de ses appareils, et sans
/// qu'il comprenne pourquoi sa correction se défait.
#[tokio::test]
async fn une_reconnexion_laisse_le_profil_tel_quel() {
    let (app, _, sync) = app_avec(identite_nommee(), true);

    app.sign_in(Provider::Google, Origine::App, "code", "app://retour", None)
        .await
        .unwrap();

    // Le lecteur corrige son nom.
    let mut corrige = sync.profil(&UserId("x".into())).await.unwrap().unwrap();
    corrige.prenom = "Sha'eliel".into();
    sync.set_profil(&UserId("x".into()), &corrige)
        .await
        .unwrap();

    let session = app
        .sign_in(Provider::Google, Origine::App, "code", "app://retour", None)
        .await
        .unwrap();
    assert!(!session.created, "le compte existait déjà");

    let apres = sync.profil(&UserId("x".into())).await.unwrap().unwrap();
    assert_eq!(apres.prenom, "Sha'eliel", "la correction du lecteur a tenu");
}

/// Un `App` monté sur des doublures, pour les épreuves qui n'ont pas besoin
/// d'un vrai stockage.
///
/// Exposé pour que les épreuves de l'interface l'emploient : `/capacites` ne
/// touche ni au stockage ni au réseau, mais `State<App>` en demande quand même
/// — la fabrique évite d'en recopier un jeu là-bas.
pub(crate) fn app_de_test(
    capacites: std::collections::BTreeSet<crate::domain::capacites::Capacite>,
) -> App {
    App {
        appareils: None,
        notificateur: None,
        secret_diffusion: None,
        identity: Arc::new(FakeProvider {
            identity: identity(),
            accept: true,
        }),
        users: Arc::new(FakeUsers::default()),
        sync: Arc::new(FakeSync::default()),
        tokens: TokenIssuer::new("secret-de-test"),
        clock: Arc::new(FixedClock(OffsetDateTime::now_utc())),
        capacites,
    }
}
