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
use crate::domain::{DomainError, ExternalIdentity, Origine, Provider};

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
        origine: Origine,
        code: &str,
        redirect_uri: &str,
        verifier: Option<&str>,
    ) -> Result<ExternalIdentity, DomainError> {
        match provider {
            Provider::Github => self.github(origine, code, redirect_uri, verifier).await,
            // Google ne distingue pas : son client est de type « application
            // web » et sert les deux origines. Une adresse de retour de plus
            // dans sa console suffit — rien à choisir ici.
            Provider::Google => self.google(code, redirect_uri, verifier).await,
            Provider::Apple => self.apple(origine, code, redirect_uri).await,
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
        origine: Origine,
        code: &str,
        redirect_uri: &str,
        verifier: Option<&str>,
    ) -> Result<ExternalIdentity, DomainError> {
        // Deux **applications** distinctes, pas deux identifiants de la même :
        // le portail de GitHub n'admet qu'une adresse de retour par
        // application, et celle de l'app la prend.
        let credentials = match origine {
            Origine::App => self.config.github.as_ref(),
            Origine::Web => self.config.github_web.as_ref(),
        }
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

    async fn apple(
        &self,
        origine: Origine,
        code: &str,
        redirect_uri: &str,
    ) -> Result<ExternalIdentity, DomainError> {
        let credentials = self
            .config
            .apple
            .as_ref()
            .ok_or(DomainError::ProviderNotConfigured)?;

        // **L'identité présentée doit être celle à qui l'autorisation a été
        // accordée.** L'App ID pour un code venu de l'interface système, le
        // Services ID pour un code venu d'un navigateur. Les échanger rend
        // `invalid_grant` dans les deux sens.
        //
        // Un Services ID absent se **dit** : sans ça, le site recevrait un
        // refus d'Apple pour une clé qu'on n'a simplement pas encore créée, et
        // chercherait la faute chez lui.
        let identite = match origine {
            Origine::App => credentials.client_id.as_str(),
            Origine::Web => credentials
                .services_id
                .as_deref()
                .ok_or(DomainError::ProviderNotConfigured)?,
        };
        let secret = apple_client_secret(credentials, identite, OffsetDateTime::now_utc())?;

        let mut form: Vec<(&str, &str)> = vec![
            ("client_id", identite),
            ("client_secret", secret.as_str()),
            ("code", code),
            ("grant_type", "authorization_code"),
        ];
        // Et `redirect_uri` suit le même partage : le flux natif n'a jamais
        // redirigé, donc l'envoyer serait mentir ; le flux navigateur l'exige,
        // et Apple le compare à ce qui est déclaré sous le Services ID.
        if origine == Origine::Web {
            form.push(("redirect_uri", redirect_uri));
        }

        let id_token = self
            .post_token("https://appleid.apple.com/auth/token", &form)
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
/// Le `sub` porte **la même identité que le `client_id` de l'échange** — App
/// ID ou Services ID selon l'origine du code —, sans quoi Apple rejette. D'où
/// le paramètre : la clé `.p8` sert aux deux flux, l'identité non.
fn apple_client_secret(
    credentials: &super::config::AppleCredentials,
    identite: &str,
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
            sub: identite,
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
            github_web: None,
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
            for origine in [Origine::App, Origine::Web] {
                let erreur = providers
                    .exchange(
                        fournisseur,
                        origine,
                        "un-code",
                        "https://ontbible.com/cb",
                        None,
                    )
                    .await
                    .expect_err("sans identifiants, l'échange ne peut pas aboutir");

                assert!(
                    matches!(erreur, DomainError::ProviderNotConfigured),
                    "{fournisseur:?} en {} devrait se dire non configuré, et non refuser : {erreur:?}",
                    origine.as_str(),
                );
            }
        }
    }

    /// Un déploiement où l'app est branchée et le site pas encore.
    ///
    /// C'est l'état réel du 27 août 2026, et c'est celui qui pouvait le plus
    /// tromper : les identifiants **existent**, ils sont simplement ceux d'une
    /// autre identité.
    fn seulement_l_app() -> Config {
        Config {
            apple: Some(crate::infrastructure::config::AppleCredentials {
                client_id: "com.labibleont.ONT".into(),
                services_id: None,
                team_id: "EQUIPE".into(),
                key_id: "CLE".into(),
                private_key: String::new(),
            }),
            github: Some(crate::infrastructure::config::OAuthCredentials {
                client_id: "app".into(),
                client_secret: "secret".into(),
            }),
            ..sans_identifiants()
        }
    }

    /// **Configuré pour l'app ne veut pas dire configuré pour le site.**
    ///
    /// Sans ce partage, le site présenterait l'App ID d'Apple ou l'application
    /// GitHub de l'app, et recevrait un `invalid_grant` — une erreur de
    /// fournisseur pour une clé qu'on n'a simplement pas encore créée. Il
    /// chercherait la faute chez lui, et elle serait chez nous.
    ///
    /// Le réseau n'est pas atteint : la vérification précède l'appel.
    #[tokio::test]
    async fn le_site_se_dit_non_configure_tant_que_ses_identites_manquent() {
        let providers = HttpIdentityProvider::new(seulement_l_app());

        for fournisseur in [Provider::Apple, Provider::Github] {
            let erreur = providers
                .exchange(
                    fournisseur,
                    Origine::Web,
                    "un-code",
                    "https://ontbible.com/fr/compte/retour",
                    None,
                )
                .await
                .expect_err("le site n'a pas encore d'identité chez ce fournisseur");

            assert!(
                matches!(erreur, DomainError::ProviderNotConfigured),
                "{fournisseur:?} devrait dire au site qu'il n'est pas configuré : {erreur:?}",
            );
        }
    }
}
