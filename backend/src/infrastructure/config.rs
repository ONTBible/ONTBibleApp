//! La configuration, lue des variables d'environnement de la Lambda.
//!
//! Aucun secret n'est jamais écrit dans le dépôt ni dans le binaire iOS :
//! c'est toute la raison d'être de ce proxy. Un `.ipa` se désassemble en
//! quelques minutes ; une variable d'environnement Lambda, non.

use crate::domain::DomainError;

#[derive(Clone)]
pub struct OAuthCredentials {
    pub client_id: String,
    pub client_secret: String,
}

/// Apple n'a pas de secret statique : il faut le fabriquer à chaque échange,
/// signé avec la clé `.p8` téléchargée une seule fois depuis le portail
/// développeur.
#[derive(Clone)]
pub struct AppleCredentials {
    /// L'identifiant de l'**app** (`com.labibleont.ONT`) — surtout pas un
    /// Services ID : le flux natif accorde l'autorisation à l'app, et Apple
    /// refuse l'échange si les deux diffèrent.
    pub client_id: String,
    pub team_id: String,
    pub key_id: String,
    /// Le contenu PEM du fichier `.p8`.
    pub private_key: String,
}

#[derive(Clone)]
pub struct Config {
    pub table: String,
    /// La clé de signature de nos propres jetons.
    pub jwt_secret: String,
    /// Le DSN Sentry. Vide = observabilité désactivée, ce qui doit rester un
    /// mode de fonctionnement valide : un backend qui refuse de démarrer
    /// faute de télémétrie est un backend fragile.
    pub sentry_dsn: String,
    pub apple: Option<AppleCredentials>,
    pub google: Option<OAuthCredentials>,
    pub github: Option<OAuthCredentials>,
}

impl Config {
    pub fn from_env() -> Result<Self, DomainError> {
        let var = |name: &str| std::env::var(name).ok().filter(|v| !v.is_empty());

        let jwt_secret = var("JWT_SECRET").ok_or_else(|| {
            tracing::error!("JWT_SECRET absent — impossible d'émettre des sessions");
            DomainError::Storage
        })?;

        let pair = |id: &str, secret: &str| match (var(id), var(secret)) {
            (Some(client_id), Some(client_secret)) => Some(OAuthCredentials {
                client_id,
                client_secret,
            }),
            _ => None,
        };

        let apple = match (
            var("APPLE_CLIENT_ID"),
            var("APPLE_TEAM_ID"),
            var("APPLE_KEY_ID"),
            var("APPLE_PRIVATE_KEY"),
        ) {
            (Some(client_id), Some(team_id), Some(key_id), Some(private_key)) => {
                Some(AppleCredentials {
                    client_id,
                    team_id,
                    key_id,
                    // La clé passe par l'environnement avec des « \n »
                    // échappés — on les restitue.
                    private_key: private_key.replace("\\n", "\n"),
                })
            }
            _ => None,
        };

        Ok(Self {
            table: var("TABLE_NAME").unwrap_or_else(|| "ont".into()),
            sentry_dsn: var("SENTRY_DSN").unwrap_or_default(),
            jwt_secret,
            apple,
            google: pair("GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET"),
            github: pair("GITHUB_CLIENT_ID", "GITHUB_CLIENT_SECRET"),
        })
    }
}
