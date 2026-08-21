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
    /// De quoi signer les notifications. `None` désactive la diffusion sans
    /// empêcher le reste : lire ne dépend pas de savoir notifier.
    pub apns: Option<ApnsCredentials>,
    /// Le secret que le déploiement présente pour déclencher une diffusion.
    pub secret_diffusion: Option<String>,
}

/// La clé APNs.
///
/// **Distincte de celle de Sign in with Apple**, même si les trois premiers
/// champs se ressemblent. Une clé du portail développeur porte des capacités
/// précises : celle qui signe les connexions ne signe pas les notifications,
/// et Apple répond alors un `403` qui ne nomme pas la cause.
#[derive(Clone, Debug)]
pub struct ApnsCredentials {
    pub team_id: String,
    /// La clé de **production** — celle qui joint les lecteurs.
    pub key_id: String,
    pub private_key: String,
    /// La clé de **sandbox**, facultative.
    ///
    /// Une clé du portail ne couvre qu'un environnement : celle de production
    /// se fait refuser par le serveur de sandbox avec un
    /// `BadEnvironmentKeyInToken`, et réciproquement. Sans celle-ci, les builds
    /// de debug ne reçoivent rien — supportable en développement, mais qui
    /// mérite d'être su plutôt que découvert.
    pub sandbox_key_id: Option<String>,
    pub sandbox_private_key: Option<String>,
    /// Le « topic » — le bundle de l'app.
    pub topic: String,
}

impl Config {
    pub fn from_env() -> Result<Self, DomainError> {
        let var = |name: &str| std::env::var(name).ok().filter(|v| !v.is_empty());

        let jwt_secret = var("JWT_SECRET").ok_or_else(|| {
            tracing::error!("JWT_SECRET absent — impossible d'émettre des sessions");
            DomainError::Storage
        })?;

        // Les quatre ensemble, ou rien. Une clé sans son identifiant d'équipe
        // ne signe pas, et l'erreur ne se verrait qu'au premier envoi.
        let apns = match (
            var("APNS_TEAM_ID"),
            var("APNS_KEY_ID"),
            var("APNS_PRIVATE_KEY"),
            var("APNS_TOPIC"),
        ) {
            (Some(team_id), Some(key_id), Some(private_key), Some(topic)) => {
                Some(ApnsCredentials {
                    team_id,
                    key_id,
                    private_key,
                    sandbox_key_id: var("APNS_SANDBOX_KEY_ID"),
                    sandbox_private_key: var("APNS_SANDBOX_PRIVATE_KEY"),
                    topic,
                })
            }
            _ => {
                tracing::info!("APNs non configuré — la diffusion est désactivée");
                None
            }
        };

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
            apns,
            secret_diffusion: var("SECRET_DIFFUSION"),
        })
    }
}
