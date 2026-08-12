//! Les jetons de session — c'est ici que se joue le « jeton maison ».
//!
//! Le raisonnement, pour qu'il reste lisible dans six mois :
//!
//! **Pourquoi pas Cognito.** Cognito facture *par personne active et par
//! mois* (0,015 $ au-delà de 10 000). Lambda, API Gateway et DynamoDB
//! facturent *par requête*, en fractions de centime par million. À 50 000
//! lecteurs, Cognito représenterait 96 % de la facture — 600 $ contre 30 $
//! pour tout le reste. Émettre nos propres jetons supprime ce poste.
//!
//! **Pourquoi ce n'est pas de la sécurité bricolée.** Le point dangereux en
//! authentification, c'est de détenir des mots de passe. Ici on n'en voit
//! jamais un seul : Apple, Google et GitHub authentifient la personne, et
//! nous ne faisons que constater leur verdict puis émettre un ticket
//! d'entrée. Signer un JWT est un appel de bibliothèque.
//!
//! **Pourquoi HS256 et pas ES256.** Un seul service émet et vérifie ces
//! jetons, dans le même processus : une clé symétrique suffit, et elle évite
//! une paire de clés à gérer. Le jour où un second service devra vérifier
//! sans pouvoir émettre, il faudra passer à ES256 — la migration est prévue,
//! c'est pourquoi `alg` est déjà inscrit dans l'en-tête et vérifié.
//!
//! **Pourquoi un jeton d'accès court et un de rafraîchissement long.** Un JWT
//! ne se révoque pas : une fois signé, il vaut jusqu'à son expiration. On le
//! garde donc court (1 heure). Le jeton de rafraîchissement, lui, vit en base
//! — donc il se révoque, et déconnecter un appareil devient possible.

use serde::{Deserialize, Serialize};
use time::{Duration, OffsetDateTime};

/// Durée de vie du jeton d'accès. Court, parce qu'il est irrévocable.
pub const ACCESS_TTL: Duration = Duration::hours(1);

/// Durée de vie du jeton de rafraîchissement. Long, parce qu'il est révocable.
pub const REFRESH_TTL: Duration = Duration::days(60);

/// L'identifiant interne d'un lecteur.
///
/// Délibérément distinct de l'identifiant du fournisseur : quelqu'un peut
/// rattacher Google *et* Apple au même compte, et l'identifiant Apple change
/// si la personne révoque puis réautorise.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct UserId(pub String);

impl UserId {
    pub fn new() -> Self {
        Self(uuid::Uuid::new_v4().to_string())
    }
}

impl Default for UserId {
    fn default() -> Self {
        Self::new()
    }
}

impl std::fmt::Display for UserId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

/// Le contenu du jeton d'accès.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Claims {
    /// Le sujet — notre identifiant interne.
    pub sub: String,
    /// Émis à (secondes epoch).
    pub iat: i64,
    /// Expire à (secondes epoch).
    pub exp: i64,
}

#[derive(Debug, thiserror::Error)]
pub enum TokenError {
    #[error("jeton invalide ou expiré")]
    Invalid,
    #[error("impossible de signer le jeton")]
    Signing,
}

/// Émet et vérifie les jetons d'accès.
#[derive(Clone)]
pub struct TokenIssuer {
    encoding: jsonwebtoken::EncodingKey,
    decoding: jsonwebtoken::DecodingKey,
}

impl TokenIssuer {
    pub fn new(secret: &str) -> Self {
        Self {
            encoding: jsonwebtoken::EncodingKey::from_secret(secret.as_bytes()),
            decoding: jsonwebtoken::DecodingKey::from_secret(secret.as_bytes()),
        }
    }

    pub fn issue(&self, user: &UserId, now: OffsetDateTime) -> Result<String, TokenError> {
        let claims = Claims {
            sub: user.0.clone(),
            iat: now.unix_timestamp(),
            exp: (now + ACCESS_TTL).unix_timestamp(),
        };
        jsonwebtoken::encode(
            &jsonwebtoken::Header::new(jsonwebtoken::Algorithm::HS256),
            &claims,
            &self.encoding,
        )
        .map_err(|_| TokenError::Signing)
    }

    /// Vérifie la signature **et** l'algorithme.
    ///
    /// Contrôler `alg` explicitement n'est pas une précaution de style : sans
    /// ça, un attaquant peut présenter un jeton annonçant `alg: none` ou un
    /// algorithme asymétrique, et certaines bibliothèques le vérifieraient
    /// avec la clé publique — c'est la faille classique des implémentations
    /// JWT. `jsonwebtoken` impose la liste, on la restreint à HS256.
    pub fn verify(&self, token: &str) -> Result<UserId, TokenError> {
        let mut validation = jsonwebtoken::Validation::new(jsonwebtoken::Algorithm::HS256);
        validation.validate_exp = true;

        jsonwebtoken::decode::<Claims>(token, &self.decoding, &validation)
            .map(|data| UserId(data.claims.sub))
            .map_err(|_| TokenError::Invalid)
    }
}

/// Un jeton de rafraîchissement — opaque côté client, haché côté serveur.
///
/// On ne stocke jamais la valeur en clair : une fuite de la table ne doit pas
/// livrer des sessions utilisables. Même logique qu'un mot de passe, sauf
/// qu'ici la valeur est aléatoire, donc un hachage rapide suffit — pas besoin
/// d'un dérivateur lent, il n'y a rien à deviner.
#[derive(Debug, Clone)]
pub struct RefreshToken(pub String);

impl RefreshToken {
    pub fn generate() -> Self {
        use base64::Engine;
        let raw: [u8; 32] = std::array::from_fn(|_| rand_byte());
        Self(base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(raw))
    }

    pub fn digest(&self) -> String {
        use sha2::{Digest, Sha256};
        let mut hasher = Sha256::new();
        hasher.update(self.0.as_bytes());
        hex(&hasher.finalize())
    }
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

/// Un octet aléatoire cryptographique, tiré du générateur du système.
fn rand_byte() -> u8 {
    use std::cell::RefCell;
    use std::io::Read;

    thread_local! {
        static SOURCE: RefCell<std::fs::File> = RefCell::new(
            std::fs::File::open("/dev/urandom").expect("/dev/urandom indisponible")
        );
    }

    SOURCE.with(|file| {
        let mut byte = [0u8; 1];
        file.borrow_mut()
            .read_exact(&mut byte)
            .expect("lecture de /dev/urandom");
        byte[0]
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn un_jeton_emis_se_verifie() {
        let issuer = TokenIssuer::new("secret-de-test");
        let user = UserId("abc".into());

        let token = issuer.issue(&user, OffsetDateTime::now_utc()).unwrap();
        assert_eq!(issuer.verify(&token).unwrap(), user);
    }

    #[test]
    fn un_jeton_signe_avec_une_autre_cle_est_rejete() {
        let mine = TokenIssuer::new("ma-cle");
        let theirs = TokenIssuer::new("leur-cle");

        let token = theirs
            .issue(&UserId("abc".into()), OffsetDateTime::now_utc())
            .unwrap();
        assert!(mine.verify(&token).is_err());
    }

    #[test]
    fn un_jeton_expire_est_rejete() {
        let issuer = TokenIssuer::new("secret-de-test");
        let past = OffsetDateTime::now_utc() - Duration::hours(3);

        let token = issuer.issue(&UserId("abc".into()), past).unwrap();
        assert!(issuer.verify(&token).is_err());
    }

    #[test]
    fn un_jeton_bricole_est_rejete() {
        let issuer = TokenIssuer::new("secret-de-test");
        let token = issuer
            .issue(&UserId("abc".into()), OffsetDateTime::now_utc())
            .unwrap();

        // On altère la charge utile sans retoucher la signature.
        let mut parts: Vec<&str> = token.split('.').collect();
        let forged = "eyJzdWIiOiJhdHRhcXVhbnQiLCJpYXQiOjAsImV4cCI6OTk5OTk5OTk5OX0";
        parts[1] = forged;
        assert!(issuer.verify(&parts.join(".")).is_err());
    }

    #[test]
    fn les_jetons_de_rafraichissement_sont_uniques_et_haches() {
        let first = RefreshToken::generate();
        let second = RefreshToken::generate();

        assert_ne!(first.0, second.0);
        assert_ne!(first.digest(), second.digest());
        // L'empreinte ne doit jamais laisser deviner la valeur.
        assert!(!first.digest().contains(&first.0));
        assert_eq!(first.digest().len(), 64);
    }
}
