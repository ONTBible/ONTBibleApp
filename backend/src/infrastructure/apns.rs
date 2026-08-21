//! L'envoi des notifications, chez Apple.
//!
//! ## L'authentification par jeton, pas par certificat
//!
//! Apple accepte deux voies. Le certificat `.p12` expire au bout d'un an et
//! doit être renouvelé à la main — une panne annuelle, silencieuse, qui tombe
//! le jour où personne ne s'y attend. La clé `.p8` ne périme pas : on signe
//! soi-même un jeton court, et c'est celui-là qu'Apple vérifie.
//!
//! ## Le jeton est réutilisé, et c'est une exigence d'Apple
//!
//! Apple **rejette** un émetteur qui régénère son jeton à chaque envoi — la
//! documentation parle d'un `TooManyProviderTokenUpdates`. Il faut le garder
//! entre cinquante minutes et une heure. On le renouvelle donc à cinquante
//! minutes : au-delà d'une heure il est refusé, en deçà de cinquante on
//! s'expose au reproche inverse.
//!
//! ## HTTP/2, et pourquoi ce n'est pas un détail
//!
//! APNs ne parle que HTTP/2. `reqwest` le négocie, à condition que la
//! fonctionnalité soit compilée — sans elle, la connexion aboutit et chaque
//! envoi rend un `403` qui ne dit pas pourquoi.

use std::sync::Mutex;

use async_trait::async_trait;
use serde::Serialize;
use time::OffsetDateTime;

use crate::domain::diffusion::{Annonce, Appareil};
use crate::domain::ports::Notificateur;
use crate::domain::DomainError;

/// Ce qu'Apple demande pour signer.
pub struct Apns {
    /// L'identifiant de l'équipe — dix caractères, dans le portail développeur.
    equipe: String,
    /// L'identifiant de la clé `.p8`.
    cle_id: String,
    /// La clé privée elle-même, au format PEM.
    cle: Vec<u8>,
    /// Le bundle de l'app — le « topic » au sens d'Apple.
    topic: String,
    http: reqwest::Client,
    /// Le jeton courant et sa date d'émission.
    jeton: Mutex<Option<(String, OffsetDateTime)>>,
}

/// Une heure moins dix : Apple refuse au-delà d'une heure, et reproche les
/// renouvellements trop fréquents en deçà de cinquante minutes.
const DUREE_JETON: time::Duration = time::Duration::minutes(50);

#[derive(Serialize)]
struct Charge<'a> {
    aps: Aps<'a>,
    #[serde(skip_serializing_if = "Option::is_none")]
    livre: Option<&'a str>,
}

#[derive(Serialize)]
struct Aps<'a> {
    alert: Alerte<'a>,
    sound: &'a str,
    /// Le fil de discussion. Deux parutions du même livre s'empilent au lieu
    /// de se remplacer, et l'écran verrouillé les regroupe.
    #[serde(rename = "thread-id")]
    thread_id: &'a str,
}

#[derive(Serialize)]
struct Alerte<'a> {
    title: &'a str,
    body: &'a str,
}

impl Apns {
    pub fn new(equipe: String, cle_id: String, cle: Vec<u8>, topic: String) -> Self {
        Self {
            equipe,
            cle_id,
            cle,
            topic,
            http: reqwest::Client::new(),
            jeton: Mutex::new(None),
        }
    }

    /// Le jeton de fournisseur, signé en ES256.
    fn jeton(&self) -> Result<String, DomainError> {
        let maintenant = OffsetDateTime::now_utc();
        {
            let garde = self.jeton.lock().expect("verrou du jeton APNs");
            if let Some((jeton, emis)) = garde.as_ref() {
                if maintenant - *emis < DUREE_JETON {
                    return Ok(jeton.clone());
                }
            }
        }

        #[derive(Serialize)]
        struct Revendications<'a> {
            iss: &'a str,
            iat: i64,
        }

        let entete = {
            let mut e = jsonwebtoken::Header::new(jsonwebtoken::Algorithm::ES256);
            e.kid = Some(self.cle_id.clone());
            e
        };
        let cle = jsonwebtoken::EncodingKey::from_ec_pem(&self.cle)
            .map_err(|e| DomainError::Notification(format!("clé APNs illisible : {e}")))?;
        let jeton = jsonwebtoken::encode(
            &entete,
            &Revendications {
                iss: &self.equipe,
                iat: maintenant.unix_timestamp(),
            },
            &cle,
        )
        .map_err(|e| DomainError::Notification(format!("signature APNs : {e}")))?;

        *self.jeton.lock().expect("verrou du jeton APNs") = Some((jeton.clone(), maintenant));
        Ok(jeton)
    }
}

#[async_trait]
impl Notificateur for Apns {
    async fn diffuser(
        &self,
        appareils: &[Appareil],
        annonce: &Annonce,
    ) -> Result<Vec<String>, DomainError> {
        let jeton = self.jeton()?;
        let charge = Charge {
            aps: Aps {
                alert: Alerte {
                    title: &annonce.titre,
                    body: &annonce.corps,
                },
                sound: "default",
                thread_id: annonce.livre.as_deref().unwrap_or("lexique"),
            },
            livre: annonce.livre.as_deref(),
        };
        let corps = serde_json::to_vec(&charge)
            .map_err(|e| DomainError::Notification(format!("charge APNs : {e}")))?;

        let mut morts = Vec::new();
        for appareil in appareils {
            let url = format!(
                "https://{}/3/device/{}",
                appareil.environnement.hote(),
                appareil.jeton
            );
            let reponse = self
                .http
                .post(&url)
                .bearer_auth(&jeton)
                .header("apns-topic", &self.topic)
                .header("apns-push-type", "alert")
                // `5` et non `10` : une parution n'est pas urgente au point de
                // réveiller un écran. Apple peut la grouper avec d'autres et
                // ménager la batterie.
                .header("apns-priority", "5")
                // Une parution garde son sens une journée. Passé ce délai,
                // l'app aura de toute façon synchronisé toute seule.
                .header(
                    "apns-expiration",
                    (OffsetDateTime::now_utc().unix_timestamp() + 86_400).to_string(),
                )
                .body(corps.clone())
                .send()
                .await;

            match reponse {
                // **410 : le jeton est mort.** L'app a été désinstallée, et
                // c'est le seul signal qu'on en aura jamais — un lecteur parti
                // ne peut plus rien retirer lui-même.
                Ok(r) if r.status() == reqwest::StatusCode::GONE => {
                    morts.push(appareil.empreinte());
                }
                Ok(r) if r.status().is_success() => {}
                // Une panne sur un appareil n'arrête pas la diffusion : les
                // autres lecteurs n'y sont pour rien.
                Ok(r) => {
                    let code = r.status();
                    let detail = r.text().await.unwrap_or_default();
                    tracing::warn!(%code, %detail, "APNs a refusé un envoi");
                }
                Err(e) => tracing::warn!(erreur = %e, "APNs injoignable pour un appareil"),
            }
        }
        Ok(morts)
    }
}
