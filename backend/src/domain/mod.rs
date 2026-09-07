//! Le domaine — ce que le backend sait, indépendamment d'AWS et d'axum.

pub mod capacites;
pub mod diffusion;
pub mod ports;
pub mod sync;
pub mod token;

use serde::{Deserialize, Serialize};

/// D'où vient le code d'autorisation : de l'app ou d'un navigateur.
///
/// **Ce n'est pas une préférence, c'est une identité différente chez le
/// fournisseur.** Un code obtenu par `ASAuthorizationController` a été accordé
/// à l'**App ID** ; un code obtenu dans un navigateur l'a été au **Services
/// ID**. Présenter l'un pour l'autre à l'échange rend `invalid_grant` — Apple
/// le dit noir sur blanc, et l'inverse est vrai aussi.
///
/// GitHub pousse plus loin : son portail n'admet qu'une seule adresse de
/// retour par application, prise par l'app. Le site exige donc une **seconde
/// application**, donc un second identifiant *et* un second secret.
///
/// Google seul ignore la distinction : son client est de type « application
/// web » et sert les deux, une adresse de retour de plus suffisant. C'est
/// pourquoi il a été branché en premier.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Origine {
    /// L'app iOS ou Android, par l'interface système du fournisseur.
    ///
    /// **C'est le défaut, et ça n'est pas arbitraire** : les versions de l'app
    /// déjà installées n'envoient pas ce champ et ne le pourront jamais
    /// rétroactivement. Un défaut qui vaudrait `Web` les casserait toutes le
    /// jour du déploiement.
    #[default]
    App,
    /// `ontbible.com`, par redirection de navigateur.
    ///
    /// **Le mot est `webapp`, pas `web`**, et c'est le choix de l'auteur : le
    /// dépôt s'appelle `ONTBibleWebapp` et le Services ID d'Apple
    /// `com.labibleont.ont.webapp`. Un troisième mot pour la même chose aurait
    /// fait chercher lequel des trois fait foi.
    Webapp,
}

impl Origine {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::App => "app",
            Self::Webapp => "webapp",
        }
    }
}

/// Les fournisseurs d'identité acceptés.
///
/// « Sign in with Apple » figure en premier parce que la revue App Store
/// l'exige dès qu'un autre fournisseur tiers est proposé — ce n'est pas une
/// préférence, c'est une règle de publication.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Provider {
    Apple,
    Google,
    Github,
}

impl Provider {
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "apple" => Some(Self::Apple),
            "google" => Some(Self::Google),
            "github" => Some(Self::Github),
            _ => None,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Apple => "apple",
            Self::Google => "google",
            Self::Github => "github",
        }
    }
}

/// Ce qu'un fournisseur nous apprend d'une personne.
///
/// Volontairement maigre. On ne demande que ce dont on a besoin pour
/// reconnaître quelqu'un d'une session à l'autre — la minimisation n'est pas
/// qu'une exigence du RGPD, c'est aussi ce qui limite les dégâts d'une fuite.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExternalIdentity {
    pub provider: Provider,
    /// L'identifiant stable chez le fournisseur.
    pub subject: String,
    /// Facultatif — Apple ne le donne qu'à la toute première autorisation, et
    /// GitHub seulement si l'adresse est publique.
    pub email: Option<String>,
    /// Ce que le fournisseur dit de la personne, quand il le dit.
    ///
    /// ## Pourquoi tout est facultatif, et le restera
    ///
    /// Les trois fournisseurs ne donnent pas la même chose, et surtout pas au
    /// même endroit :
    ///
    /// - **Google** rend `given_name` et `family_name` dans son `userinfo`,
    ///   que le serveur interroge déjà ;
    /// - **GitHub** rend `name` — une seule chaîne — et `bio` dans son
    ///   `/user`, que le serveur interroge déjà aussi ;
    /// - **Apple** ne les rend **qu'au client**, et **qu'à la toute première
    ///   autorisation**. Jamais au serveur, jamais une seconde fois.
    ///
    /// Le serveur amorce donc le profil pour les deux premiers, et le client
    /// s'en charge pour Apple. Ce n'est pas une inélégance : l'information
    /// n'arrive pas au même endroit, et prétendre le contraire obligerait à
    /// faire transiter par le serveur une donnée qu'il n'a pas.
    ///
    /// Rien de tout ceci n'est exigé : un compte sans nom est un compte
    /// valide. Le lecteur le remplira s'il veut, ou jamais.
    pub prenom: Option<String>,
    pub nom: Option<String>,
    pub bio: Option<String>,
}

impl ExternalIdentity {
    /// La clé de recherche « ce fournisseur, cette personne ».
    pub fn key(&self) -> String {
        format!("IDP#{}#{}", self.provider.as_str(), self.subject)
    }
}

#[derive(Debug, thiserror::Error)]
pub enum DomainError {
    #[error("le fournisseur a refusé le code d'autorisation")]
    ProviderRejected,
    /// Le fournisseur n'a **pas** d'identifiants sur ce déploiement.
    ///
    /// Distinct de [`ProviderRejected`], et la distinction n'est pas cosmétique :
    /// un identifiant absent était rapporté comme un refus, c'est-à-dire comme
    /// le résultat d'un échange **qui n'a jamais eu lieu**. Celui qui exploite
    /// voyait alors exactement ce que voit un lecteur dont le code a expiré, et
    /// n'avait aucun moyen de distinguer « j'ai oublié le secret » de « ce code
    /// est périmé ».
    ///
    /// Il ne renseigne pas un attaquant : la liste des fournisseurs proposés est
    /// déjà publique — l'écran de connexion la montre. Savoir que l'un d'eux
    /// n'est pas installé sur ce déploiement ne donne aucune prise.
    #[error("le fournisseur n'est pas configuré sur ce déploiement")]
    ProviderNotConfigured,
    #[error("le fournisseur est injoignable")]
    ProviderUnreachable,
    #[error("session inconnue ou révoquée")]
    SessionInvalid,
    #[error("erreur de stockage")]
    Storage,
    /// Le portrait dépasse ce qu'un élément peut porter.
    ///
    /// Distincte de `Storage` : celle-ci dit au client que **son envoi** est en
    /// cause, et qu'il doit réduire l'image au lieu de réessayer. Une erreur de
    /// stockage l'inviterait à recommencer à l'identique, indéfiniment.
    #[error("le portrait dépasse la taille admise")]
    PortraitTropGrand,
    /// Une panne de la chaîne de notification — clé illisible, signature
    /// impossible, charge non sérialisable.
    ///
    /// Distincte de `Storage` : celle-ci ne dit rien au lecteur et ne doit
    /// jamais faire échouer autre chose. Une parution non annoncée est un
    /// agrément perdu ; le texte, lui, est arrivé.
    #[error("la notification n'a pas pu partir : {0}")]
    Notification(String),
}

#[cfg(test)]
mod origine {
    use super::Origine;

    /// **Le mot sur le fil est un contrat entre trois dépôts.**
    ///
    /// Le site envoie `"webapp"` ; le backend doit le reconnaître, et ne doit
    /// pas reconnaître autre chose à sa place. Renommer la variante Rust est
    /// sans danger — renommer ce que `serde` lit rompt la connexion de tous
    /// les lecteurs du site, et rien dans le compilateur ne le dirait.
    ///
    /// `web` a failli être ce mot. Il a été écarté parce que le dépôt
    /// s'appelle `ONTBibleWebapp` et le Services ID `com.labibleont.ont.webapp`.
    #[test]
    fn les_mots_du_fil_ne_bougent_pas() {
        let lu = |json: &str| serde_json::from_str::<Origine>(json).ok();

        assert_eq!(lu("\"app\""), Some(Origine::App));
        assert_eq!(lu("\"webapp\""), Some(Origine::Webapp));
        assert_eq!(Origine::App.as_str(), "app");
        assert_eq!(Origine::Webapp.as_str(), "webapp");

        // Ce qui n'est **pas** le mot ne passe pas — un `web` toléré en
        // silence laisserait les deux orthographes vivre côte à côte, et
        // personne ne saurait plus laquelle fait foi.
        assert_eq!(lu("\"web\""), None);
        assert_eq!(lu("\"ios\""), None);
    }

    /// L'absence vaut `app`, et c'est ce qui protège les versions installées.
    #[test]
    fn l_absence_vaut_l_app() {
        #[derive(serde::Deserialize)]
        struct Corps {
            #[serde(default)]
            origine: Origine,
        }
        let corps: Corps = serde_json::from_str("{}").unwrap();
        assert_eq!(corps.origine, Origine::App);
    }
}
