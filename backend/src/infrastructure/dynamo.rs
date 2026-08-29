//! Le stockage — DynamoDB, en table unique.
//!
//! Une seule table plutôt qu'une par entité : toutes nos lectures partent
//! d'un lecteur connu (« ses surlignages », « sa position »), donc une clé de
//! partition `USER#<id>` et un tri par préfixe suffisent. C'est le schéma que
//! DynamoDB récompense, et il évite autant de tables à provisionner.
//!
//! ```text
//! PK                SK                        contenu
//! ─────────────────────────────────────────────────────────────────
//! USER#<id>         PROFILE                   le compte, + `idp` → la clé du lien
//! USER#<id>         HL#<unité>#<verset>       un surlignage
//! USER#<id>         POS                       la position de lecture
//! USER#<id>         LECTEUR                   ce que le lecteur dit de lui
//! USER#<id>         RT#<empreinte>            un jeton de rafraîchissement
//! IDP#<fourn>#<sub> LINK                      identité externe → compte
//! ```
//!
//! **`PROFILE` et `LECTEUR` ne sont pas la même chose.** Le premier est le
//! compte — sa création, son lien d'identité ; le second est ce que le lecteur
//! écrit de lui-même. Les confondre ferait porter au compte une donnée qu'il
//! doit pouvoir perdre sans cesser d'exister, et le nom anglais du premier
//! vient de ce qu'il est antérieur.
//!
//! Le profil porte `idp`, la clé du lien d'identité. Sans elle, l'effacement
//! ne peut pas atteindre l'autre partition — voir `erase`.
//!
//! Les jetons de rafraîchissement portent un TTL DynamoDB, qui les efface
//! d'eux-mêmes. **Ce n'est pas une garantie d'expiration** : AWS écrit qu'un
//! élément expiré peut rester lisible plusieurs jours. `consume_refresh`
//! vérifie donc l'échéance lui-même.

use std::collections::HashMap;

use async_trait::async_trait;
use aws_sdk_dynamodb::types::{AttributeValue, Put, TransactWriteItem};
use aws_sdk_dynamodb::Client;

use crate::domain::diffusion::{Appareil, Environnement};
use crate::domain::ports::{AppareilRepository, SyncRepository, UserRepository};
use crate::domain::sync::{Highlight, Position, ProfilLecteur};
use crate::domain::token::UserId;
use crate::domain::{DomainError, ExternalIdentity};
use time::OffsetDateTime;

#[derive(Clone)]
pub struct Dynamo {
    client: Client,
    table: String,
}

impl Dynamo {
    pub fn new(client: Client, table: String) -> Self {
        Self { client, table }
    }

    fn key(partition: &str, sort: &str) -> HashMap<String, AttributeValue> {
        HashMap::from([
            ("pk".to_string(), AttributeValue::S(partition.to_string())),
            ("sk".to_string(), AttributeValue::S(sort.to_string())),
        ])
    }

    fn user_key(user: &UserId) -> String {
        format!("USER#{user}")
    }

    /// La partition des appareils.
    ///
    /// **Une seule**, et c'est délibéré : une diffusion les veut tous d'un
    /// coup, sans ciblage. Répartir sur plusieurs partitions demanderait de
    /// les parcourir toutes, pour une lecture qui n'a lieu qu'à chaque
    /// parution — quelques fois par mois.
    ///
    /// La limite est connue : une partition DynamoDB tient 10 Go et 3 000
    /// unités de lecture par seconde. Un jeton pèse deux cents octets, ce qui
    /// laisse de la marge pour des millions de lecteurs — et le jour où ce
    /// n'est plus vrai, ce sera un beau problème à avoir.
    const APPAREILS: &'static str = "PUSH";
}

#[async_trait]
impl AppareilRepository for Dynamo {
    async fn enregistrer(&self, appareil: &Appareil) -> Result<(), DomainError> {
        // L'empreinte comme clé de tri : deux enregistrements du même appareil
        // se recouvrent. Sans ça, un lecteur qui rouvre l'app chaque jour
        // multiplierait ses jetons et recevrait la même parution autant de
        // fois qu'il en aurait accumulé.
        let mut item = Self::key(
            Self::APPAREILS,
            &format!("APPAREIL#{}", appareil.empreinte()),
        );
        item.insert("jeton".into(), AttributeValue::S(appareil.jeton.clone()));
        item.insert(
            "environnement".into(),
            AttributeValue::S(
                match appareil.environnement {
                    Environnement::Production => "production",
                    Environnement::Sandbox => "sandbox",
                }
                .into(),
            ),
        );
        // **Une échéance, et elle n'est pas un détail.**
        //
        // Un lecteur qui désinstalle l'app ne peut plus rien retirer : sans
        // date de péremption, son jeton resterait indéfiniment. Apple finit
        // par répondre `410`, mais seulement si on lui écrit — et on n'écrit
        // qu'à chaque parution. Un an après le dernier signe de vie, l'entrée
        // s'efface toute seule.
        //
        // Chaque ouverture de l'app la repousse : un appareil vivant ne
        // disparaît jamais.
        let an = OffsetDateTime::now_utc() + time::Duration::days(365);
        item.insert(
            "expire".into(),
            AttributeValue::N(an.unix_timestamp().to_string()),
        );

        self.client
            .put_item()
            .table_name(&self.table)
            .set_item(Some(item))
            .send()
            .await
            .map_err(|e| {
                tracing::error!(erreur = ?e, "enregistrement d'appareil");
                DomainError::Storage
            })?;
        Ok(())
    }

    async fn oublier(&self, empreinte: &str) -> Result<(), DomainError> {
        self.client
            .delete_item()
            .table_name(&self.table)
            .set_key(Some(Self::key(
                Self::APPAREILS,
                &format!("APPAREIL#{empreinte}"),
            )))
            .send()
            .await
            .map_err(|e| {
                tracing::error!(erreur = ?e, "retrait d'appareil");
                DomainError::Storage
            })?;
        Ok(())
    }

    async fn tous(&self) -> Result<Vec<Appareil>, DomainError> {
        // Paginé, et pas seulement par prudence : DynamoDB rend au plus un
        // mégaoctet par page, quel que soit ce qu'on demande. Sans la boucle,
        // la diffusion s'arrêterait silencieusement aux premiers milliers
        // d'appareils — et personne ne le verrait, puisque les autres
        // recevraient simplement rien.
        let mut appareils = Vec::new();
        let mut depuis = None;

        loop {
            let page = self
                .client
                .query()
                .table_name(&self.table)
                .key_condition_expression("pk = :p")
                .expression_attribute_values(":p", AttributeValue::S(Self::APPAREILS.into()))
                .set_exclusive_start_key(depuis.clone())
                .send()
                .await
                .map_err(|e| {
                    tracing::error!(erreur = ?e, "lecture des appareils");
                    DomainError::Storage
                })?;

            for item in page.items() {
                let Some(jeton) = string(item, "jeton") else {
                    continue;
                };
                let environnement = match string(item, "environnement").as_deref() {
                    Some("sandbox") => Environnement::Sandbox,
                    _ => Environnement::Production,
                };
                appareils.push(Appareil {
                    jeton,
                    environnement,
                });
            }

            depuis = page.last_evaluated_key().cloned();
            if depuis.is_none() {
                break;
            }
        }
        Ok(appareils)
    }
}

fn string(item: &HashMap<String, AttributeValue>, name: &str) -> Option<String> {
    item.get(name)?.as_s().ok().cloned()
}

/// L'horloge du système, en secondes epoch.
///
/// L'infrastructure a le droit de la lire — c'est le domaine qui ne l'a pas,
/// pour rester éprouvable sans horloge. Ici on compare une échéance écrite par
/// nous à l'instant présent : il n'y a rien à injecter.
fn maintenant() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|ecoule| ecoule.as_secs() as i64)
        .unwrap_or(0)
}

fn number(item: &HashMap<String, AttributeValue>, name: &str) -> Option<i64> {
    item.get(name)?.as_n().ok()?.parse().ok()
}

#[async_trait]
impl UserRepository for Dynamo {
    async fn find_by_identity(
        &self,
        identity: &ExternalIdentity,
    ) -> Result<Option<UserId>, DomainError> {
        let response = self
            .client
            .get_item()
            .table_name(&self.table)
            .set_key(Some(Self::key(&identity.key(), "LINK")))
            .send()
            .await
            .map_err(|error| {
                tracing::error!(?error, "lecture de l'identité");
                DomainError::Storage
            })?;

        Ok(response
            .item()
            .and_then(|item| string(item, "user"))
            .map(UserId))
    }

    async fn create(&self, identity: &ExternalIdentity) -> Result<UserId, DomainError> {
        let user = UserId::new();

        let mut link = Self::key(&identity.key(), "LINK");
        link.insert("user".into(), AttributeValue::S(user.0.clone()));

        let mut profile = Self::key(&Self::user_key(&user), "PROFILE");
        profile.insert(
            "provider".into(),
            AttributeValue::S(identity.provider.as_str().to_string()),
        );
        // La clé du lien, recopiée sur le profil.
        //
        // C'est ce qui rend l'effacement complet possible : le lien vit dans
        // **une autre partition** (`IDP#…`), et rien dans `USER#<id>` n'y menait.
        // `erase` ne pouvait donc pas le trouver, et l'identité externe
        // survivait au compte — une reconnexion retrouvait un compte censé
        // effacé.
        profile.insert("idp".into(), AttributeValue::S(identity.key()));
        if let Some(email) = &identity.email {
            profile.insert("email".into(), AttributeValue::S(email.clone()));
        }

        // Les deux écritures dans **une transaction**.
        //
        // Elles étaient séparées : une panne entre les deux laissait un lien
        // sans profil, et l'identité pointait alors un compte qui n'existait
        // pas. La transaction est tout ou rien.
        //
        // `attribute_not_exists(pk)` sur le lien garde l'idempotence : deux
        // connexions simultanées depuis deux appareils ne créent pas deux
        // comptes pour la même identité. La seconde échoue, et c'est traité
        // ci-dessous plutôt que rendu au visiteur.
        let resultat = self
            .client
            .transact_write_items()
            .transact_items(
                TransactWriteItem::builder()
                    .put(
                        Put::builder()
                            .table_name(&self.table)
                            .set_item(Some(link))
                            .condition_expression("attribute_not_exists(pk)")
                            .build()
                            .map_err(|_| DomainError::Storage)?,
                    )
                    .build(),
            )
            .transact_items(
                TransactWriteItem::builder()
                    .put(
                        Put::builder()
                            .table_name(&self.table)
                            .set_item(Some(profile))
                            .build()
                            .map_err(|_| DomainError::Storage)?,
                    )
                    .build(),
            )
            .send()
            .await;

        if let Err(error) = resultat {
            // La course perdue n'est pas une erreur : l'autre connexion vient
            // de créer le compte, et c'est celui-là qu'il faut rendre. Renvoyer
            // un 500 à la seconde ferait échouer une connexion parfaitement
            // valide, sur un appareil que rien ne distingue du premier.
            tracing::warn!(?error, "création concurrente, on relit le lien");
            if let Some(existant) = self.find_by_identity(identity).await? {
                return Ok(existant);
            }
            return Err(DomainError::Storage);
        }

        Ok(user)
    }

    async fn store_refresh(
        &self,
        user: &UserId,
        digest: &str,
        expires_at: i64,
    ) -> Result<(), DomainError> {
        let mut item = Self::key(&Self::user_key(user), &format!("RT#{digest}"));
        item.insert("user".into(), AttributeValue::S(user.0.clone()));
        item.insert("digest".into(), AttributeValue::S(digest.to_string()));
        // Attribut de TTL : DynamoDB efface la ligne tout seul à échéance.
        item.insert("ttl".into(), AttributeValue::N(expires_at.to_string()));

        self.client
            .put_item()
            .table_name(&self.table)
            .set_item(Some(item))
            .send()
            .await
            .map_err(|_| DomainError::Storage)?;
        Ok(())
    }

    async fn consume_refresh(&self, digest: &str) -> Result<UserId, DomainError> {
        // On cherche la ligne par son index secondaire sur l'empreinte, puis
        // on la supprime : un jeton de rafraîchissement ne sert qu'une fois.
        let found = self
            .client
            .query()
            .table_name(&self.table)
            .index_name("by-digest")
            .key_condition_expression("digest = :digest")
            .expression_attribute_values(":digest", AttributeValue::S(digest.to_string()))
            .limit(1)
            .send()
            .await
            .map_err(|_| DomainError::Storage)?;

        let item = found
            .items()
            .first()
            .cloned()
            .ok_or(DomainError::SessionInvalid)?;

        let user = string(&item, "user").ok_or(DomainError::SessionInvalid)?;
        let sort = string(&item, "sk").ok_or(DomainError::SessionInvalid)?;

        // L'expiration est vérifiée **ici**, et pas seulement par le TTL.
        //
        // AWS écrit noir sur blanc qu'un élément expiré peut rester lisible
        // plusieurs jours avant d'être effacé : le TTL est un ménage, pas une
        // garantie. Sans ce contrôle, un jeton de soixante jours restait
        // utilisable au-delà — et c'est précisément la durée qui décide de
        // combien de temps une session volée survit.
        if let Some(echeance) = number(&item, "ttl") {
            if echeance <= maintenant() {
                // On retire quand même la ligne au passage : elle n'a plus
                // aucune valeur, et la laisser ferait réessayer indéfiniment.
                let _ = self
                    .client
                    .delete_item()
                    .table_name(&self.table)
                    .set_key(Some(Self::key(&format!("USER#{user}"), &sort)))
                    .send()
                    .await;
                return Err(DomainError::SessionInvalid);
            }
        }

        // La suppression est **conditionnelle**, et c'est ce qui rend la
        // consommation atomique.
        //
        // Sans condition, deux requêtes concurrentes lisaient la même ligne,
        // la supprimaient toutes les deux sans erreur, et repartaient chacune
        // avec une session neuve : un jeton à usage unique en délivrait deux.
        // Ici, une seule des deux voit la ligne exister au moment d'écrire ;
        // l'autre reçoit un échec de condition, qui vaut « déjà consommé ».
        self.client
            .delete_item()
            .table_name(&self.table)
            .set_key(Some(Self::key(&format!("USER#{user}"), &sort)))
            .condition_expression("attribute_exists(pk)")
            .send()
            .await
            .map_err(|error| {
                tracing::warn!(?error, "jeton déjà consommé, ou stockage indisponible");
                DomainError::SessionInvalid
            })?;

        Ok(UserId(user))
    }

    /// Efface **tout** ce qui rattache des données à ce lecteur.
    ///
    /// ## Deux défauts corrigés, et le second était le grave
    ///
    /// La requête ne **paginait pas**. DynamoDB rend au plus un mégaoctet par
    /// appel et signale la suite par une clé de reprise ; sans la suivre, un
    /// compte chargé gardait silencieusement tout ce qui dépassait. Un
    /// effacement partiel qui se déclare réussi est pire qu'un échec.
    ///
    /// Et le **lien d'identité** vit dans une autre partition, `IDP#<fourn>#…`.
    /// Une requête sur `pk = USER#<id>` ne pouvait pas l'atteindre : il
    /// survivait au compte, et une reconnexion par le même fournisseur
    /// retrouvait un identifiant censé effacé. Ce n'était donc pas un
    /// effacement au sens de l'article 17 du RGPD.
    ///
    /// ## L'ordre compte
    ///
    /// Le lien part **en premier**. Si l'effacement s'interrompt ensuite, il
    /// reste des miettes sans identité — désagréable mais anonyme. L'ordre
    /// inverse laisserait une identité vivante pointant un compte vidé, ce qui
    /// est exactement ce qu'on veut éviter.
    async fn erase(&self, user: &UserId) -> Result<(), DomainError> {
        let partition = Self::user_key(user);

        // Le profil porte la clé du lien depuis `create`.
        let profil = self
            .client
            .get_item()
            .table_name(&self.table)
            .set_key(Some(Self::key(&partition, "PROFILE")))
            .send()
            .await
            .map_err(|_| DomainError::Storage)?;

        if let Some(idp) = profil.item().and_then(|item| string(item, "idp")) {
            self.client
                .delete_item()
                .table_name(&self.table)
                .set_key(Some(Self::key(&idp, "LINK")))
                .send()
                .await
                .map_err(|error| {
                    tracing::error!(?error, "effacement du lien d'identité");
                    DomainError::Storage
                })?;
        } else {
            // Un profil sans `idp` vient d'avant ce correctif. On le dit fort :
            // le compte sera vidé, mais son identité externe restera, et
            // personne ne le verra autrement que dans ce journal.
            tracing::error!(
                user = %user.0,
                "profil sans clé d'identité — le lien IDP survivra à l'effacement"
            );
        }

        // Puis la partition du lecteur, page par page.
        let mut depuis = None;
        loop {
            let page = self
                .client
                .query()
                .table_name(&self.table)
                .key_condition_expression("pk = :pk")
                .expression_attribute_values(":pk", AttributeValue::S(partition.clone()))
                .set_exclusive_start_key(depuis)
                .send()
                .await
                .map_err(|_| DomainError::Storage)?;

            for item in page.items() {
                let Some(sort) = string(item, "sk") else {
                    continue;
                };
                self.client
                    .delete_item()
                    .table_name(&self.table)
                    .set_key(Some(Self::key(&partition, &sort)))
                    .send()
                    .await
                    .map_err(|_| DomainError::Storage)?;
            }

            depuis = page.last_evaluated_key().cloned();
            if depuis.is_none() {
                break;
            }
        }

        Ok(())
    }
}

#[async_trait]
impl SyncRepository for Dynamo {
    async fn highlights(
        &self,
        user: &UserId,
        since: Option<i64>,
    ) -> Result<Vec<Highlight>, DomainError> {
        // Paginé, comme l'effacement et pour la même raison : au-delà d'un
        // mégaoctet, DynamoDB s'arrête et le dit par une clé de reprise. Sans
        // la suivre, un lecteur assidu cesserait de recevoir ses plus anciens
        // surlignages sans qu'aucune erreur ne le signale — ses appareils
        // divergeraient en silence.
        let mut highlights = Vec::new();
        let mut depuis = None;

        loop {
            let page = self
                .client
                .query()
                .table_name(&self.table)
                .key_condition_expression("pk = :pk AND begins_with(sk, :prefix)")
                .expression_attribute_values(":pk", AttributeValue::S(Self::user_key(user)))
                .expression_attribute_values(":prefix", AttributeValue::S("HL#".into()))
                .set_exclusive_start_key(depuis)
                .send()
                .await
                .map_err(|_| DomainError::Storage)?;

            for item in page.items() {
                let Some(body) = string(item, "body") else {
                    continue;
                };
                let Ok(highlight) = serde_json::from_str::<Highlight>(&body) else {
                    continue;
                };
                if since.is_none_or(|cutoff| highlight.updated_at > cutoff) {
                    highlights.push(highlight);
                }
            }

            depuis = page.last_evaluated_key().cloned();
            if depuis.is_none() {
                break;
            }
        }

        Ok(highlights)
    }

    async fn position(&self, user: &UserId) -> Result<Option<Position>, DomainError> {
        let response = self
            .client
            .get_item()
            .table_name(&self.table)
            .set_key(Some(Self::key(&Self::user_key(user), "POS")))
            .send()
            .await
            .map_err(|_| DomainError::Storage)?;

        Ok(response
            .item()
            .and_then(|item| string(item, "body"))
            .and_then(|body| serde_json::from_str(&body).ok()))
    }

    async fn upsert_highlight(
        &self,
        user: &UserId,
        highlight: &Highlight,
    ) -> Result<(), DomainError> {
        let body = serde_json::to_string(highlight).map_err(|_| DomainError::Storage)?;

        let mut item = Self::key(&Self::user_key(user), &highlight.sort_key());
        item.insert("body".into(), AttributeValue::S(body));
        item.insert(
            "updated_at".into(),
            AttributeValue::N(highlight.updated_at.to_string()),
        );

        self.client
            .put_item()
            .table_name(&self.table)
            .set_item(Some(item))
            .send()
            .await
            .map_err(|_| DomainError::Storage)?;
        Ok(())
    }

    async fn profil(&self, user: &UserId) -> Result<Option<ProfilLecteur>, DomainError> {
        let response = self
            .client
            .get_item()
            .table_name(&self.table)
            .set_key(Some(Self::key(&Self::user_key(user), "LECTEUR")))
            .send()
            .await
            .map_err(|_| DomainError::Storage)?;

        Ok(response
            .item()
            .and_then(|item| string(item, "body"))
            .and_then(|body| serde_json::from_str(&body).ok()))
    }

    async fn set_profil(&self, user: &UserId, profil: &ProfilLecteur) -> Result<(), DomainError> {
        let body = serde_json::to_string(profil).map_err(|_| DomainError::Storage)?;

        let mut item = Self::key(&Self::user_key(user), "LECTEUR");
        item.insert("body".into(), AttributeValue::S(body));
        item.insert(
            "updated_at".into(),
            AttributeValue::N(profil.updated_at.to_string()),
        );

        self.client
            .put_item()
            .table_name(&self.table)
            .set_item(Some(item))
            .send()
            .await
            .map_err(|_| DomainError::Storage)?;
        Ok(())
    }

    async fn set_position(&self, user: &UserId, position: &Position) -> Result<(), DomainError> {
        let body = serde_json::to_string(position).map_err(|_| DomainError::Storage)?;

        let mut item = Self::key(&Self::user_key(user), "POS");
        item.insert("body".into(), AttributeValue::S(body));

        self.client
            .put_item()
            .table_name(&self.table)
            .set_item(Some(item))
            .send()
            .await
            .map_err(|_| DomainError::Storage)?;
        Ok(())
    }
}

/// Utilisé seulement par les tests d'infrastructure — laissé pour éviter un
/// avertissement sur `number`, qui servira au prochain index temporel.
#[allow(dead_code)]
fn unused(item: &HashMap<String, AttributeValue>) -> Option<i64> {
    number(item, "updated_at")
}
