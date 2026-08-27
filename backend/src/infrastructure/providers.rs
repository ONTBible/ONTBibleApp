//! L'échange OAuth2 auprès d'Apple, Google et GitHub.
//!
//! C'est le cœur du « jeton maison » : on reçoit du client le **code
//! d'autorisation** que le fournisseur lui a remis, on le troque contre
//! l'identité, et on s'arrête là. Le secret client ne quitte jamais cette
//! fonction — c'est la raison d'être du proxy : un binaire iOS se désassemble,
//! une variable d'environnement Lambda non.
//!
//! Les trois fournisseurs ne se ressemblent pas :
//!
//! - **GitHub** rend un jeton d'accès, puis `GET /user` donne l'identité.
//! - **Google** rend un jeton d'accès, puis `userinfo` donne l'identité.
//! - **Apple** rend un `id_token` (un JWT) qui *contient* l'identité, et
//!   exige que le secret client soit lui-même un JWT signé ES256 avec la clé
//!   `.p8` du compte développeur. C'est le seul des trois qui demande de la
//!   cryptographie de notre côté.
//!
//! **Le cas particulier d'Apple en flux natif.** Quand le code d'autorisation
//! vient de `ASAuthorizationController` — l'interface système, pas un
//! navigateur — le `client_id` doit être l'**identifiant de l'app**
//! (`com.labibleont.ONT`), et surtout **pas** un Services ID : Apple refuse
//! l'échange avec un `invalid_grant` si les deux diffèrent, puisque
//! l'autorisation a été accordée à l'app. Le `sub` du secret client doit
//! porter la même valeur, et `redirect_uri` doit être **omis** — il n'y a
//! jamais eu de redirection. Conséquence pratique : pas de Services ID à
//! créer, seulement la clé `.p8`.

use async_trait::async_trait;
use serde::Deserialize;
use time::{Duration, OffsetDateTime};

use crate::domain::ports::IdentityProvider;
use crate::domain::{DomainError, ExternalIdentity, Provider};

use super::config::Config;

pub struct HttpIdentityProvider {
    client: reqwest::Client,
    config: Config,
}

impl HttpIdentityProvider {
    pub fn new(config: Config) -> Self {
        Self {
            client: reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(10))
                // GitHub refuse les requêtes sans agent utilisateur.
                .user_agent("la-bible-ont/0.1")
                .build()
                .expect("client HTTP"),
            config,
        }
    }
}

#[derive(Deserialize)]
struct TokenResponse {
    #[serde(default)]
    access_token: Option<String>,
    #[serde(default)]
    id_token: Option<String>,
}

#[derive(Deserialize)]
struct GoogleUser {
    sub: String,
    email: Option<String>,
}

#[derive(Deserialize)]
struct GithubUser {
    id: u64,
    email: Option<String>,
}

/// Les revendications d'un `id_token` Apple.
#[derive(Deserialize)]
struct AppleClaims {
    sub: String,
    email: Option<String>,
}

#[async_trait]
impl IdentityProvider for HttpIdentityProvider {
    async fn exchange(
        &self,
        provider: Provider,
        code: &str,
        redirect_uri: &str,
        verifier: Option<&str>,
    ) -> Result<ExternalIdentity, DomainError> {
        match provider {
            Provider::Github => self.github(code, redirect_uri, verifier).await,
            Provider::Google => self.google(code, redirect_uri, verifier).await,
            // Apple n'a ni redirection ni PKCE en flux natif.
            Provider::Apple => self.apple(code).await,
        }
    }
}

impl HttpIdentityProvider {
    async fn post_token(
        &self,
        url: &str,
        form: &[(&str, &str)],
    ) -> Result<TokenResponse, DomainError> {
        let response = self
            .client
            .post(url)
            .header("Accept", "application/json")
            .form(form)
            .send()
            .await
            .map_err(|_| DomainError::ProviderUnreachable)?;

        if !response.status().is_success() {
            return Err(DomainError::ProviderRejected);
        }
        response
            .json::<TokenResponse>()
            .await
            .map_err(|_| DomainError::ProviderRejected)
    }

    async fn github(
        &self,
        code: &str,
        redirect_uri: &str,
        verifier: Option<&str>,
    ) -> Result<ExternalIdentity, DomainError> {
        let credentials = self
            .config
            .github
            .as_ref()
            .ok_or(DomainError::ProviderNotConfigured)?;

        let mut form: Vec<(&str, &str)> = vec![
            ("client_id", credentials.client_id.as_str()),
            ("client_secret", credentials.client_secret.as_str()),
            ("code", code),
            ("redirect_uri", redirect_uri),
        ];
        if let Some(verifier) = verifier {
            form.push(("code_verifier", verifier));
        }

        let token = self
            .post_token("https://github.com/login/oauth/access_token", &form)
            .await?
            .access_token
            .ok_or(DomainError::ProviderRejected)?;

        let user: GithubUser = self
            .client
            .get("https://api.github.com/user")
            .bearer_auth(&token)
            .send()
            .await
            .map_err(|_| DomainError::ProviderUnreachable)?
            .json()
            .await
            .map_err(|_| DomainError::ProviderRejected)?;

        Ok(ExternalIdentity {
            provider: Provider::Github,
            subject: user.id.to_string(),
            email: user.email,
        })
    }

    async fn google(
        &self,
        code: &str,
        redirect_uri: &str,
        verifier: Option<&str>,
    ) -> Result<ExternalIdentity, DomainError> {
        let credentials = self
            .config
            .google
            .as_ref()
            .ok_or(DomainError::ProviderNotConfigured)?;

        let mut form: Vec<(&str, &str)> = vec![
            ("client_id", credentials.client_id.as_str()),
            ("client_secret", credentials.client_secret.as_str()),
            ("code", code),
            ("redirect_uri", redirect_uri),
            ("grant_type", "authorization_code"),
        ];
        if let Some(verifier) = verifier {
            form.push(("code_verifier", verifier));
        }

        let token = self
            .post_token("https://oauth2.googleapis.com/token", &form)
            .await?
            .access_token
            .ok_or(DomainError::ProviderRejected)?;

        let user: GoogleUser = self
            .client
            .get("https://openidconnect.googleapis.com/v1/userinfo")
            .bearer_auth(&token)
            .send()
            .await
            .map_err(|_| DomainError::ProviderUnreachable)?
            .json()
            .await
            .map_err(|_| DomainError::ProviderRejected)?;

        Ok(ExternalIdentity {
            provider: Provider::Google,
            subject: user.sub,
            email: user.email,
        })
    }

    async fn apple(&self, code: &str) -> Result<ExternalIdentity, DomainError> {
        let credentials = self
            .config
            .apple
            .as_ref()
            .ok_or(DomainError::ProviderNotConfigured)?;
        let secret = apple_client_secret(credentials, OffsetDateTime::now_utc())?;

        let id_token = self
            .post_token(
                "https://appleid.apple.com/auth/token",
                &[
                    ("client_id", credentials.client_id.as_str()),
                    ("client_secret", secret.as_str()),
                    ("code", code),
                    ("grant_type", "authorization_code"),
                ],
            )
            .await?
            .id_token
            .ok_or(DomainError::ProviderRejected)?;

        // L'`id_token` vient de nous être remis par Apple sur un canal TLS
        // authentifié, en réponse à notre propre requête signée : sa
        // provenance est déjà établie. On en lit donc les revendications sans
        // revalider la signature contre le JWKS, qui n'apporterait rien ici.
        // (Ce raccourci serait faux si le jeton nous arrivait du client.)
        let claims = decode_jwt_claims::<AppleClaims>(&id_token)?;

        Ok(ExternalIdentity {
            provider: Provider::Apple,
            subject: claims.sub,
            email: claims.email,
        })
    }
}

/// Le secret client d'Apple — un JWT ES256 signé avec la clé `.p8`.
///
/// Apple est le seul fournisseur à ne pas délivrer de secret statique : il
/// faut le fabriquer, et il expire. Six mois est le maximum autorisé ; on
/// prend une heure, puisqu'on le régénère à chaque échange de toute façon.
///
/// Le `sub` porte l'identifiant de l'app — la même valeur que `client_id`,
/// sans quoi Apple rejette l'échange.
fn apple_client_secret(
    credentials: &super::config::AppleCredentials,
    now: OffsetDateTime,
) -> Result<String, DomainError> {
    #[derive(serde::Serialize)]
    struct AppleSecretClaims<'a> {
        iss: &'a str,
        iat: i64,
        exp: i64,
        aud: &'a str,
        sub: &'a str,
    }

    let mut header = jsonwebtoken::Header::new(jsonwebtoken::Algorithm::ES256);
    header.kid = Some(credentials.key_id.clone());

    let key = jsonwebtoken::EncodingKey::from_ec_pem(credentials.private_key.as_bytes())
        .map_err(|_| DomainError::ProviderRejected)?;

    jsonwebtoken::encode(
        &header,
        &AppleSecretClaims {
            iss: &credentials.team_id,
            iat: now.unix_timestamp(),
            exp: (now + Duration::hours(1)).unix_timestamp(),
            aud: "https://appleid.apple.com",
            sub: &credentials.client_id,
        },
        &key,
    )
    .map_err(|_| DomainError::ProviderRejected)
}

/// Lit la charge utile d'un JWT sans vérifier sa signature.
///
/// Réservé aux jetons dont la provenance est déjà établie par le canal — voir
/// l'explication dans `apple()`. Ne jamais employer sur un jeton reçu d'un
/// client.
fn decode_jwt_claims<T: serde::de::DeserializeOwned>(token: &str) -> Result<T, DomainError> {
    use base64::Engine;

    let payload = token
        .split('.')
        .nth(1)
        .ok_or(DomainError::ProviderRejected)?;
    let bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(payload)
        .map_err(|_| DomainError::ProviderRejected)?;

    serde_json::from_slice(&bytes).map_err(|_| DomainError::ProviderRejected)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn les_revendications_d_un_jwt_se_lisent() {
        // {"sub":"001234.abcdef","email":"lecteur@example.com"}
        let token = "eyJhbGciOiJFUzI1NiJ9.\
                     eyJzdWIiOiIwMDEyMzQuYWJjZGVmIiwiZW1haWwiOiJsZWN0ZXVyQGV4YW1wbGUuY29tIn0.\
                     signature-ignoree";

        let claims: AppleClaims = decode_jwt_claims(token).unwrap();
        assert_eq!(claims.sub, "001234.abcdef");
        assert_eq!(claims.email.as_deref(), Some("lecteur@example.com"));
    }

    #[test]
    fn un_jeton_malforme_est_rejete() {
        assert!(decode_jwt_claims::<AppleClaims>("pas-un-jwt").is_err());
    }

    /// Un déploiement nu : ni Apple, ni Google, ni GitHub.
    fn sans_identifiants() -> Config {
        Config {
            table: "ont".into(),
            jwt_secret: "secret-d-epreuve".into(),
            sentry_dsn: String::new(),
            apple: None,
            google: None,
            github: None,
            apns: None,
            secret_diffusion: None,
        }
    }

    /// **Un identifiant absent n'est pas un refus.**
    ///
    /// Il était rapporté comme `ProviderRejected`, c'est-à-dire comme le
    /// résultat d'un échange qui n'a jamais eu lieu — et le client recevait 401
    /// « connexion refusée ». Celui qui exploite ne pouvait donc pas distinguer
    /// « j'ai oublié le secret » de « ce code a expiré », et le lecteur lisait
    /// qu'on l'avait refusé alors qu'on n'avait interrogé personne.
    ///
    /// Le réseau n'est jamais atteint : la vérification précède l'appel, donc ce
    /// test ne sort pas de la machine.
    #[tokio::test]
    async fn un_fournisseur_sans_identifiants_se_dit_non_configure() {
        let providers = HttpIdentityProvider::new(sans_identifiants());

        for fournisseur in [Provider::Github, Provider::Google, Provider::Apple] {
            let erreur = providers
                .exchange(fournisseur, "un-code", "https://ontbible.com/cb", None)
                .await
                .expect_err("sans identifiants, l'échange ne peut pas aboutir");

            assert!(
                matches!(erreur, DomainError::ProviderNotConfigured),
                "{fournisseur:?} devrait se dire non configuré, et non refuser : {erreur:?}",
            );
        }
    }
}
