//! Les routes HTTP.
//!
//! ```text
//! POST   /auth/:provider   code d'autorisation → session
//! POST   /auth/refresh     jeton long → nouvelle session
//! GET    /sync?since=…     ce qui a changé
//! PUT    /sync             ce que le client a produit
//! DELETE /me               effacement du compte (RGPD)
//! GET    /health           sonde
//!
//! Et ce qui s'adresse à un navigateur ou à iOS — voir `web` :
//!
//! ```text
//! GET    /.well-known/apple-app-site-association
//! GET    /fr/lire/{livre}/{unité}
//! ```

use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::{delete, get, post};
use axum::{Json, Router};
use serde::Deserialize;

use crate::application::App;
use crate::domain::sync::PushRequest;
use crate::domain::token::UserId;
use crate::domain::{DomainError, Provider};

pub mod web;

pub fn router(app: App) -> Router {
    Router::new()
        .route("/health", get(health))
        .route("/auth/refresh", post(refresh))
        .route("/auth/{provider}", post(sign_in))
        .route("/auth/{provider}/callback", get(oauth_callback))
        .route("/sync", get(pull).put(push))
        .route("/me", delete(erase))
        // Les liens publics. Sans état : ni compte, ni jeton, ni base — ces
        // deux routes doivent répondre à un iPhone qui vient d'installer
        // l'app, donc avant toute connexion.
        .route(
            "/.well-known/apple-app-site-association",
            get(web::apple_app_site_association),
        )
        .route("/fr/lire/{livre}/{unite}", get(web::passage))
        .with_state(app)
}

async fn health() -> &'static str {
    "ok"
}

/// Le retour du navigateur, pour Google et GitHub.
///
/// Ces deux-là exigent une adresse de retour en **HTTPS** — un schéma
/// personnalisé comme `ont://` leur est refusé. On leur en donne une, et on
/// rebondit aussitôt vers l'app.
///
/// Rien n'est échangé ici : on ne fait que faire suivre le code. Il reste
/// inutilisable sans le secret client, qui ne quitte jamais cette Lambda —
/// et sans le vérificateur PKCE, que seule l'app détient.
async fn oauth_callback(
    Path(provider): Path<String>,
    Query(params): Query<std::collections::HashMap<String, String>>,
) -> Response {
    let target = match (params.get("code"), params.get("error")) {
        (Some(code), _) => format!(
            "ont://auth/callback?provider={}&code={}",
            urlencode(&provider),
            urlencode(code)
        ),
        (None, Some(error)) => {
            format!("ont://auth/callback?error={}", urlencode(error))
        }
        _ => "ont://auth/callback?error=invalid_response".to_string(),
    };

    (StatusCode::FOUND, [(axum::http::header::LOCATION, target)]).into_response()
}

/// Encodage minimal pour un composant d'URL — les codes d'autorisation sont
/// alphanumériques, mais un message d'erreur peut contenir n'importe quoi.
fn urlencode(value: &str) -> String {
    value
        .bytes()
        .map(|byte| match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                (byte as char).to_string()
            }
            _ => format!("%{byte:02X}"),
        })
        .collect()
}

// ─────────────────────────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct SignInBody {
    code: String,
    redirect_uri: String,
    /// Le vérificateur PKCE, pour Google et GitHub. Absent pour Apple, dont
    /// le flux natif n'en a pas besoin.
    #[serde(default)]
    code_verifier: Option<String>,
}

async fn sign_in(
    State(app): State<App>,
    Path(provider): Path<String>,
    Json(body): Json<SignInBody>,
) -> Result<Response, ApiError> {
    let provider = Provider::parse(&provider).ok_or(ApiError::UnknownProvider)?;
    let session = app
        .sign_in(
            provider,
            &body.code,
            &body.redirect_uri,
            body.code_verifier.as_deref(),
        )
        .await?;
    Ok(Json(session).into_response())
}

#[derive(Deserialize)]
struct RefreshBody {
    refresh_token: String,
}

async fn refresh(
    State(app): State<App>,
    Json(body): Json<RefreshBody>,
) -> Result<Response, ApiError> {
    Ok(Json(app.refresh(&body.refresh_token).await?).into_response())
}

// ─────────────────────────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct SinceQuery {
    since: Option<i64>,
}

async fn pull(
    State(app): State<App>,
    headers: HeaderMap,
    Query(query): Query<SinceQuery>,
) -> Result<Response, ApiError> {
    let user = authenticate(&app, &headers)?;
    Ok(Json(app.pull(&user, query.since).await?).into_response())
}

async fn push(
    State(app): State<App>,
    headers: HeaderMap,
    Json(body): Json<PushRequest>,
) -> Result<Response, ApiError> {
    let user = authenticate(&app, &headers)?;
    app.push(&user, body).await?;
    Ok(StatusCode::NO_CONTENT.into_response())
}

async fn erase(State(app): State<App>, headers: HeaderMap) -> Result<Response, ApiError> {
    let user = authenticate(&app, &headers)?;
    app.erase(&user).await?;
    Ok(StatusCode::NO_CONTENT.into_response())
}

/// Vérifie le jeton d'accès porté par l'en-tête `Authorization`.
///
/// La vérification se fait dans le processus plutôt que par un autorisateur
/// API Gateway : l'autorisateur JWT intégré ne sait valider que des jetons
/// asymétriques via un JWKS public, et un autorisateur Lambda ajouterait une
/// invocation facturée à chaque requête. Ici, c'est une vérification de
/// signature en mémoire — quelques microsecondes.
fn authenticate(app: &App, headers: &HeaderMap) -> Result<UserId, ApiError> {
    let token = headers
        .get("authorization")
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.strip_prefix("Bearer "))
        .ok_or(ApiError::Unauthorized)?;

    app.tokens.verify(token).map_err(|_| ApiError::Unauthorized)
}

// ─────────────────────────────────────────────────────────────────────────────

pub enum ApiError {
    Unauthorized,
    UnknownProvider,
    Domain(DomainError),
}

impl From<DomainError> for ApiError {
    fn from(error: DomainError) -> Self {
        Self::Domain(error)
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        // Les messages restent volontairement pauvres côté client : détailler
        // pourquoi une authentification échoue renseigne surtout celui qui
        // cherche à la contourner. Le détail part dans les traces.
        let (status, message) = match self {
            Self::Unauthorized => (StatusCode::UNAUTHORIZED, "authentification requise"),
            Self::UnknownProvider => (StatusCode::BAD_REQUEST, "fournisseur inconnu"),
            Self::Domain(DomainError::ProviderRejected) => {
                (StatusCode::UNAUTHORIZED, "connexion refusée")
            }
            Self::Domain(DomainError::SessionInvalid) => {
                (StatusCode::UNAUTHORIZED, "session expirée")
            }
            Self::Domain(DomainError::ProviderUnreachable) => {
                (StatusCode::BAD_GATEWAY, "fournisseur injoignable")
            }
            Self::Domain(error) => {
                tracing::error!(?error, "erreur interne");
                (StatusCode::INTERNAL_SERVER_ERROR, "erreur interne")
            }
        };

        (status, Json(serde_json::json!({ "error": message }))).into_response()
    }
}
