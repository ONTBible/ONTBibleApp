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
//! USER#<id>         PROFILE                   le compte
//! USER#<id>         HL#<unité>#<verset>       un surlignage
//! USER#<id>         POS                       la position de lecture
//! USER#<id>         RT#<empreinte>            un jeton de rafraîchissement
//! IDP#<fourn>#<sub> LINK                      identité externe → compte
//! ```
//!
//! Les jetons de rafraîchissement portent un TTL DynamoDB : ils disparaissent
//! d'eux-mêmes à expiration, sans tâche de ménage à écrire ni à surveiller.

use std::collections::HashMap;

use async_trait::async_trait;
use aws_sdk_dynamodb::types::AttributeValue;
use aws_sdk_dynamodb::Client;

use crate::domain::ports::{SyncRepository, UserRepository};
use crate::domain::sync::{Highlight, Position};
use crate::domain::token::UserId;
use crate::domain::{DomainError, ExternalIdentity};

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
}

fn string(item: &HashMap<String, AttributeValue>, name: &str) -> Option<String> {
    item.get(name)?.as_s().ok().cloned()
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

        // `attribute_not_exists(pk)` rend l'écriture idempotente : deux
        // connexions simultanées depuis deux appareils ne créeront pas deux
        // comptes pour la même identité.
        self.client
            .put_item()
            .table_name(&self.table)
            .set_item(Some(link))
            .condition_expression("attribute_not_exists(pk)")
            .send()
            .await
            .map_err(|error| {
                tracing::warn!(?error, "création de l'identité");
                DomainError::Storage
            })?;

        let mut profile = Self::key(&Self::user_key(&user), "PROFILE");
        profile.insert(
            "provider".into(),
            AttributeValue::S(identity.provider.as_str().to_string()),
        );
        if let Some(email) = &identity.email {
            profile.insert("email".into(), AttributeValue::S(email.clone()));
        }

        self.client
            .put_item()
            .table_name(&self.table)
            .set_item(Some(profile))
            .send()
            .await
            .map_err(|_| DomainError::Storage)?;

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

        self.client
            .delete_item()
            .table_name(&self.table)
            .set_key(Some(Self::key(&format!("USER#{user}"), &sort)))
            .send()
            .await
            .map_err(|_| DomainError::Storage)?;

        Ok(UserId(user))
    }

    async fn erase(&self, user: &UserId) -> Result<(), DomainError> {
        let partition = Self::user_key(user);

        let items = self
            .client
            .query()
            .table_name(&self.table)
            .key_condition_expression("pk = :pk")
            .expression_attribute_values(":pk", AttributeValue::S(partition.clone()))
            .send()
            .await
            .map_err(|_| DomainError::Storage)?;

        for item in items.items() {
            let Some(sort) = string(item, "sk") else { continue };
            self.client
                .delete_item()
                .table_name(&self.table)
                .set_key(Some(Self::key(&partition, &sort)))
                .send()
                .await
                .map_err(|_| DomainError::Storage)?;
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
        let response = self
            .client
            .query()
            .table_name(&self.table)
            .key_condition_expression("pk = :pk AND begins_with(sk, :prefix)")
            .expression_attribute_values(":pk", AttributeValue::S(Self::user_key(user)))
            .expression_attribute_values(":prefix", AttributeValue::S("HL#".into()))
            .send()
            .await
            .map_err(|_| DomainError::Storage)?;

        let mut highlights = Vec::new();
        for item in response.items() {
            let Some(body) = string(item, "body") else { continue };
            let Ok(highlight) = serde_json::from_str::<Highlight>(&body) else {
                continue;
            };
            if since.is_none_or(|cutoff| highlight.updated_at > cutoff) {
                highlights.push(highlight);
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
