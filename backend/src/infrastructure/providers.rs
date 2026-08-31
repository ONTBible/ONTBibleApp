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
    /// Google sépare les deux, ce qui nous épargne de deviner où couper.
    given_name: Option<String>,
    family_name: Option<String>,
}

#[derive(Deserialize)]
struct GithubUser {
    id: u64,
    email: Option<String>,
    /// GitHub ne rend qu'une chaîne, et n'a aucune idée de ce qui est le
    /// prénom — voir `couper_le_nom`.
    name: Option<String>,
    bio: Option<String>,
}

/// Les revendications d'un `id_token` Apple.
#[derive(Deserialize)]
struct AppleClaims {
    sub: String,
    email: Option<String>,
}

/// Une chaîne vide vaut « rien dit ».
///
/// GitHub rend `""` pour une biographie jamais remplie, là où Google omet le
/// champ. Sans cette réduction, un compte GitHub arriverait avec une biographie
/// vide *présente*, qui écraserait celle que le lecteur aurait écrite ailleurs
/// — la fusion de profils arbitre sur la date, pas sur le contenu.
fn vide_en_none(valeur: Option<String>) -> Option<String> {
    valeur.filter(|texte| !texte.trim().is_empty())
}

/// Coupe le nom entier de GitHub en prénom et nom.
///
/// **La coupe est une convention, pas une vérité.** GitHub ne rend qu'une
/// chaîne libre — « Gloire Bikouta », « bikouta », « G. Bikouta », ou un pseudo
/// sans rapport. On coupe à la **première** espace : le premier mot au prénom,
/// tout le reste au nom, ce qui traite correctement « Marie-Claire de la
/// Fontaine » là où couper à la dernière espace l'aurait défiguré.
///
/// Un seul mot part en prénom et laisse le nom vide. C'est le bon défaut : un
/// écran qui affiche « prénom nom » rendra ce mot-là, et le lecteur
/// corrigera s'il le souhaite. Le mettre au nom rendrait un affichage qui
/// commence par une espace.
fn couper_le_nom(entier: Option<&str>) -> (Option<String>, Option<String>) {
    let Some(entier) = entier.map(str::trim).filter(|texte| !texte.is_empty()) else {
        return (None, None);
    };
    match entier.split_once(char::is_whitespace) {
        Some((premier, reste)) => {
            let reste = reste.trim();
            (
                Some(premier.to_string()),
                if reste.is_empty() {
                    None
                } else {
                    Some(reste.to_string())
                },
            )
        }
        None => (Some(entier.to_string()), None),
    }
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

    /// Quels identifiants GitHub servent, selon d'où vient le code.
    ///
    /// Une fonction à part pour qu'on puisse l'éprouver **sans réseau** : le
    /// choix est ce qui a été faux, et l'échange lui-même n'apprend rien de
    /// plus. Une épreuve qui appelle GitHub pour vérifier quel identifiant on
    /// lui présente mesure la connexion au moins autant que le code.
    fn identifiants_github(
        &self,
        origine: Origine,
    ) -> Option<&crate::infrastructure::config::OAuthCredentials> {
        match origine {
            Origine::App => self.config.github.as_ref(),
            Origine::Webapp => self
                .config
                .github_web
                .as_ref()
                .or(self.config.github.as_ref()),
        }
    }

    async fn github(
        &self,
        origine: Origine,
        code: &str,
        redirect_uri: &str,
        verifier: Option<&str>,
    ) -> Result<ExternalIdentity, DomainError> {
        // **Une seconde application GitHub est possible, elle n'est pas
        // nécessaire.**
        //
        // Ce code exigeait `github_web`, sur une prémisse écrite ici même : « le
        // portail de GitHub n'admet qu'une adresse de retour par application ».
        // C'est faux. Le champ s'appelle « Authorization callback URLs », au
        // pluriel, et porte un bouton « Add more ». La session du site l'a
        // relevé sur le portail ; la rectification n'était jamais arrivée
        // jusqu'ici, où la contrainte avait déjà servi de fondation.
        //
        // Le site tombait donc sur un 503 « fournisseur non configuré » pour un
        // secret que personne n'avait de raison de créer — et le lecteur, lui,
        // partait chez GitHub, autorisait, revenait, et se trouvait devant une
        // erreur où il ne pouvait rien faire.
        //
        // On garde le champ et l'on perd l'obligation : `github_web` sert s'il
        // est posé — quotas séparés, marque séparée le jour venu —, et l'on
        // retombe sur l'application unique sinon. Ce qui reste vrai des deux
        // côtés, c'est que l'adresse de retour du site doit figurer dans la
        // liste de l'application employée : GitHub compare, et refuse ce qu'il
        // ne connaît pas.
        let credentials = self
            .identifiants_github(origine)
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

        let (prenom, nom) = couper_le_nom(user.name.as_deref());
        Ok(ExternalIdentity {
            provider: Provider::Github,
            subject: user.id.to_string(),
            email: user.email,
            prenom,
            nom,
            bio: vide_en_none(user.bio),
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
            prenom: vide_en_none(user.given_name),
            nom: vide_en_none(user.family_name),
            // Google n'a pas de biographie à donner : son `userinfo` n'en
            // porte pas. Ne rien rendre plutôt que d'inventer un équivalent.
            bio: None,
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
            Origine::Webapp => credentials
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
        if origine == Origine::Webapp {
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

        // **Apple ne donne le nom qu'au client, et qu'une fois.**
        //
        // Il accompagne l'autorisation, pas l'`id_token` : le serveur ne le
        // voit jamais, et une seconde connexion ne le redonne à personne. C'est
        // donc au client de le retenir et de le poser lui-même dans le profil.
        //
        // Rendre `None` ici n'est pas un manque à combler plus tard : c'est
        // l'état exact de ce que le serveur sait.
        Ok(ExternalIdentity {
            provider: Provider::Apple,
            subject: claims.sub,
            email: claims.email,
            prenom: None,
            nom: None,
            bio: None,
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
            for origine in [Origine::App, Origine::Webapp] {
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

    /// **Apple : configuré pour l'app ne veut pas dire configuré pour le site.**
    ///
    /// Sans ce partage, le site présenterait l'App ID d'Apple et recevrait un
    /// `invalid_grant` — une erreur de fournisseur pour une clé qu'on n'a
    /// simplement pas encore créée. Il chercherait la faute chez lui, et elle
    /// serait chez nous.
    ///
    /// Le réseau n'est pas atteint : la vérification précède l'appel.
    #[tokio::test]
    async fn apple_se_dit_non_configure_tant_que_le_services_id_manque() {
        let providers = HttpIdentityProvider::new(seulement_l_app());

        let erreur = providers
            .exchange(
                Provider::Apple,
                Origine::Webapp,
                "un-code",
                "https://ontbible.com/fr/compte/retour",
                None,
            )
            .await
            .expect_err("le site n'a pas encore d'identité chez Apple");

        assert!(
            matches!(erreur, DomainError::ProviderNotConfigured),
            "Apple devrait dire au site qu'il n'est pas configuré : {erreur:?}",
        );
    }

    /// **GitHub, lui, n'a pas besoin d'une seconde identité.**
    ///
    /// Le contraire était écrit ici et reposait sur une inexactitude : le
    /// portail admet plusieurs adresses de retour par application. Le site
    /// tombait donc sur un 503 pour un secret que personne n'avait de raison de
    /// créer.
    #[test]
    fn le_site_emploie_l_application_de_l_app_a_defaut_de_la_sienne() {
        let providers = HttpIdentityProvider::new(seulement_l_app());

        let choisis = providers
            .identifiants_github(Origine::Webapp)
            .expect("le site retombe sur l'application de l'app");
        assert_eq!(choisis.client_id, "app");
    }

    /// Et quand la seconde application existe, c'est elle qui sert : le repli
    /// ne doit pas devenir un plafond.
    #[test]
    fn une_seconde_application_github_reste_prioritaire_pour_le_site() {
        let config = Config {
            github_web: Some(crate::infrastructure::config::OAuthCredentials {
                client_id: "site".into(),
                client_secret: "secret-du-site".into(),
            }),
            ..seulement_l_app()
        };
        let providers = HttpIdentityProvider::new(config);

        assert_eq!(
            providers
                .identifiants_github(Origine::Webapp)
                .unwrap()
                .client_id,
            "site"
        );
        assert_eq!(
            providers
                .identifiants_github(Origine::App)
                .unwrap()
                .client_id,
            "app"
        );
    }

    /// Un déploiement sans aucun identifiant GitHub le dit encore.
    #[test]
    fn sans_application_github_le_site_n_a_rien_a_presenter() {
        let providers = HttpIdentityProvider::new(sans_identifiants());
        assert!(providers.identifiants_github(Origine::Webapp).is_none());
        assert!(providers.identifiants_github(Origine::App).is_none());
    }

    /// **La coupe du nom de GitHub est une convention, et elle a des bords.**
    ///
    /// GitHub ne rend qu'une chaîne libre. On coupe à la **première** espace,
    /// ce qui traite correctement les noms composés — couper à la dernière
    /// aurait mis « Marie-Claire de la » au prénom.
    #[test]
    fn le_nom_entier_se_coupe_a_la_premiere_espace() {
        assert_eq!(
            couper_le_nom(Some("Gloire Bikouta")),
            (Some("Gloire".into()), Some("Bikouta".into()))
        );
        assert_eq!(
            couper_le_nom(Some("Marie-Claire de la Fontaine")),
            (Some("Marie-Claire".into()), Some("de la Fontaine".into()))
        );
    }

    /// Un seul mot part au **prénom**, pas au nom.
    ///
    /// Un écran qui compose « prénom nom » rendra ce mot-là. Le mettre au nom
    /// produirait un affichage qui commence par une espace.
    #[test]
    fn un_seul_mot_est_un_prenom() {
        assert_eq!(
            couper_le_nom(Some("bikouta")),
            (Some("bikouta".into()), None)
        );
    }

    /// Rien dit reste rien dit — y compris quand GitHub dit `""`.
    #[test]
    fn le_vide_ne_devient_pas_un_nom() {
        assert_eq!(couper_le_nom(None), (None, None));
        assert_eq!(couper_le_nom(Some("")), (None, None));
        assert_eq!(couper_le_nom(Some("   ")), (None, None));
    }

    /// **Une chaîne vide n'est pas une valeur.**
    ///
    /// GitHub rend `""` pour une biographie jamais remplie, là où Google omet
    /// le champ. Sans cette réduction, un compte GitHub arriverait avec une
    /// biographie vide *présente*, qui écraserait celle écrite ailleurs — la
    /// fusion arbitre sur la date, pas sur le contenu.
    #[test]
    fn une_chaine_vide_vaut_rien_dit() {
        assert_eq!(vide_en_none(Some(String::new())), None);
        assert_eq!(vide_en_none(Some("  \n ".into())), None);
        assert_eq!(vide_en_none(Some("lecteur".into())), Some("lecteur".into()));
    }
}
