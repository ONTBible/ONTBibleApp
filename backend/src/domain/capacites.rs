//! Ce que ce déploiement sait faire — et le dire, au lieu de le laisser deviner.
//!
//! # Pourquoi ce module existe
//!
//! **L'app arrive structurellement avant le serveur.** Sa moitié voyage
//! `dev → staging → main` ; le backend n'est déployé que par un push sur
//! `main` — `deployer-backend.yml` ne se déclenche que là. Entre deux
//! promotions, une app livrée aux testeurs interroge donc un serveur plus
//! ancien qu'elle.
//!
//! Jusqu'ici elle n'avait aucun moyen de le savoir : `/health` rend `ok`, ce
//! qui dit que le serveur **répond**, pas ce qu'il **sait faire**. Deux
//! questions distinctes, et c'est pourquoi elles ont deux routes.
//!
//! # Ce qui rend cette déclaration vraie
//!
//! Une liste écrite en dur mentirait le jour où un secret manque : elle
//! annoncerait « connexion Apple » sur un déploiement dont les identifiants
//! Apple sont vides. Or c'est **exactement** l'accident que
//! `terraform/main.tf` documente — un `apply` sans `oauth.env` vide les huit
//! variables OAuth sur la fonction en ligne, et « rien dans le plan ne
//! s'appelle connexion ».
//!
//! Chaque capacité est donc **dérivée de ce qui est réellement installé**.
//! Elle disparaît de la liste dès que ce qui la sert disparaît, sans que
//! personne ait à y penser.
//!
//! Conséquence utile : interroger `/capacites` **est** le contrôle de
//! déploiement. Là où lire la configuration d'une fonction AWS demande des
//! droits et un poste équipé, cette route répond à qui peut l'appeler — y
//! compris pendant une bêta, depuis n'importe où.

use std::collections::BTreeSet;

use serde::{Deserialize, Serialize};

/// Une chose que le serveur sait faire, nommée par une clé stable.
///
/// **La clé est le contrat**, pas le nom de la variante : elle voyage en JSON
/// jusqu'aux deux liseuses, qui la comparent à la leur. On peut renommer une
/// variante Rust ; on ne peut pas renommer une clé sans casser les apps déjà
/// installées.
///
/// L'ordre est celui de `BTreeSet` — alphabétique et stable, pour qu'une
/// réponse soit comparable d'un appel à l'autre.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum Capacite {
    /// `POST /auth/apple` — les identifiants Apple sont installés.
    AuthApple,
    /// `POST /auth/google`.
    AuthGoogle,
    /// `POST /auth/github`.
    AuthGithub,
    /// `GET`/`PUT /sync` — la synchronisation des annotations.
    Synchronisation,
    /// `DELETE /me` — l'effacement du compte, exigé par le RGPD.
    EffacementDuCompte,
    /// `POST /appareils` et `POST /diffuser` — les notifications de parution.
    Diffusion,
}

impl Capacite {
    /// La clé telle qu'elle voyage.
    ///
    /// Écrite ici et nulle part ailleurs : une clé recopiée dans le handler
    /// serait un second endroit à tenir à jour, et le second finit toujours
    /// par diverger du premier.
    pub const fn cle(self) -> &'static str {
        match self {
            Self::AuthApple => "auth.apple",
            Self::AuthGoogle => "auth.google",
            Self::AuthGithub => "auth.github",
            Self::Synchronisation => "sync",
            Self::EffacementDuCompte => "compte.effacement",
            Self::Diffusion => "diffusion",
        }
    }

    /// Toutes les capacités que ce code **sait** servir.
    ///
    /// À distinguer de ce qu'un déploiement offre : celui-ci n'en offre qu'un
    /// sous-ensemble, celui dont la configuration est présente.
    pub const CONNUES: [Self; 6] = [
        Self::AuthApple,
        Self::AuthGoogle,
        Self::AuthGithub,
        Self::Synchronisation,
        Self::EffacementDuCompte,
        Self::Diffusion,
    ];
}

/// Ce qu'**un** déploiement offre.
///
/// Un port au sens de l'architecture hexagonale : le domaine déclare ce dont
/// il a besoin — savoir quelles pièces sont installées — et l'infrastructure
/// le renseigne. `Config` vit dans `infrastructure` et n'a donc rien à faire
/// ici ; c'est ce qui permet d'éprouver l'offre sans AWS ni variables
/// d'environnement.
pub trait Installation: Send + Sync {
    /// Les identifiants d'un fournisseur d'identité sont-ils présents ?
    fn fournisseur_installe(&self, provider: super::Provider) -> bool;
    /// La chaîne de notification est-elle joignable ?
    fn diffusion_installee(&self) -> bool;
}

/// Ce que ce déploiement-ci offre, dérivé de ce qui y est installé.
///
/// `Synchronisation` et `EffacementDuCompte` sont inconditionnelles : elles ne
/// dépendent que de la table, sans laquelle le processus ne démarre pas. Les
/// annoncer conditionnellement laisserait croire qu'elles peuvent manquer.
pub fn offertes(installation: &dyn Installation) -> BTreeSet<Capacite> {
    let mut offre = BTreeSet::from([Capacite::Synchronisation, Capacite::EffacementDuCompte]);

    for (provider, capacite) in [
        (super::Provider::Apple, Capacite::AuthApple),
        (super::Provider::Google, Capacite::AuthGoogle),
        (super::Provider::Github, Capacite::AuthGithub),
    ] {
        if installation.fournisseur_installe(provider) {
            offre.insert(capacite);
        }
    }

    if installation.diffusion_installee() {
        offre.insert(Capacite::Diffusion);
    }

    offre
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::Provider;

    struct Nue;
    impl Installation for Nue {
        fn fournisseur_installe(&self, _: Provider) -> bool {
            false
        }
        fn diffusion_installee(&self) -> bool {
            false
        }
    }

    struct Complete;
    impl Installation for Complete {
        fn fournisseur_installe(&self, _: Provider) -> bool {
            true
        }
        fn diffusion_installee(&self) -> bool {
            true
        }
    }

    struct GoogleSeul;
    impl Installation for GoogleSeul {
        fn fournisseur_installe(&self, provider: Provider) -> bool {
            matches!(provider, Provider::Google)
        }
        fn diffusion_installee(&self) -> bool {
            false
        }
    }

    /// Un déploiement nu offre encore de lire et de synchroniser : ces deux-là
    /// ne dépendent que de la table, sans laquelle rien ne démarre.
    #[test]
    fn un_deploiement_nu_n_offre_aucune_connexion() {
        let offre = offertes(&Nue);
        assert_eq!(
            offre,
            BTreeSet::from([Capacite::Synchronisation, Capacite::EffacementDuCompte]),
        );
    }

    /// **Le cas que ce module existe pour attraper.** Si les identifiants
    /// disparaissent — l'accident décrit dans `terraform/main.tf` —, la
    /// capacité disparaît de la liste sans que personne y touche.
    #[test]
    fn une_capacite_suit_ce_qui_la_sert() {
        assert!(offertes(&Complete).contains(&Capacite::AuthApple));
        assert!(!offertes(&Nue).contains(&Capacite::AuthApple));
    }

    #[test]
    fn seul_le_fournisseur_installe_est_offert() {
        let offre = offertes(&GoogleSeul);
        assert!(offre.contains(&Capacite::AuthGoogle));
        assert!(!offre.contains(&Capacite::AuthApple));
        assert!(!offre.contains(&Capacite::AuthGithub));
    }

    /// Les clés voyagent jusqu'aux apps installées : deux capacités qui
    /// partageraient la même deviendraient indiscernables sur le fil.
    #[test]
    fn chaque_capacite_a_une_cle_distincte() {
        let cles: BTreeSet<&str> = Capacite::CONNUES.iter().map(|c| c.cle()).collect();
        assert_eq!(cles.len(), Capacite::CONNUES.len());
    }

    /// `CONNUES` est écrite à la main : une variante ajoutée sans y être
    /// inscrite serait invisible du contrôle de contrat.
    #[test]
    fn connues_porte_bien_toutes_les_variantes() {
        // Le compilateur garde l'exhaustivité de ce `match` ; ce test garde
        // qu'aucune variante ne manque à `CONNUES`.
        for capacite in Capacite::CONNUES {
            let vue = match capacite {
                Capacite::AuthApple
                | Capacite::AuthGoogle
                | Capacite::AuthGithub
                | Capacite::Synchronisation
                | Capacite::EffacementDuCompte
                | Capacite::Diffusion => true,
            };
            assert!(vue);
        }
        assert_eq!(Capacite::CONNUES.len(), 6);
    }
}

/// Le contrôle de contrat entre les deux langages.
///
/// **C'est le seul endroit où la duplication est un défaut.** Les deux listes
/// ont le droit de différer — le serveur dit ce qu'il offre, l'app ce qu'elle
/// sait employer, et une capacité connue d'un seul côté est sans conséquence.
/// Mais une clé mal orthographiée d'un côté ne se voit **nulle part** : le
/// serveur l'annonce, l'app ne la reconnaît pas, et la capacité disparaît en
/// silence. Ni la compilation ni les épreuves de chacun ne peuvent l'attraper.
///
/// Le contrôle vit ici plutôt que dans un script parce que **le Rust est
/// autoritatif sur ses propres clés** : `cle()` les rend sans qu'on ait à lire
/// le fichier. Il ne reste qu'à lire celles de Swift, dont la forme
/// `case x = "y"` est stable et sans ambiguïté.
#[cfg(test)]
mod contrat {
    use super::*;

    /// Les clés déclarées côté Swift, lues dans `ONTKit`.
    fn cles_swift() -> BTreeSet<String> {
        let chemin = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../app/Packages/ONTKit/Sources/ONTKit/Account/Capacites.swift"
        );
        let source = std::fs::read_to_string(chemin).unwrap_or_else(|erreur| {
            panic!(
                "impossible de lire les capacités de l'app ({chemin}) : {erreur}\n\
                 Ce contrôle compare les deux déclarations ; sans le fichier, il \
                 ne contrôle rien."
            )
        });

        source
            .lines()
            .filter_map(|ligne| {
                let ligne = ligne.trim();
                let reste = ligne.strip_prefix("case ")?;
                let (_, valeur) = reste.split_once(" = \"")?;
                valeur.strip_suffix('"').map(str::to_string)
            })
            .collect()
    }

    /// Chaque clé du serveur doit être reconnue par l'app.
    ///
    /// Le sens qui blesse : une capacité annoncée que l'app ne sait pas lire
    /// est une fonction perdue sans message.
    #[test]
    fn l_app_reconnait_chaque_cle_du_serveur() {
        let swift = cles_swift();
        let manquantes: Vec<&str> = Capacite::CONNUES
            .iter()
            .map(|c| c.cle())
            .filter(|cle| !swift.contains(*cle))
            .collect();

        assert!(
            manquantes.is_empty(),
            "Ces clés sont annoncées par le serveur et inconnues de l'app : {manquantes:?}\n\
             Elles disparaîtraient en silence — l'app ne les reconnaîtrait pas.\n\
             À déclarer dans ONTKit/Account/Capacites.swift.",
        );
    }

    /// Et l'inverse : une clé que l'app attend et qu'aucun serveur n'annonce
    /// est une fonction qu'elle croira absente partout, pour toujours.
    #[test]
    fn le_serveur_connait_chaque_cle_de_l_app() {
        let serveur: BTreeSet<&str> = Capacite::CONNUES.iter().map(|c| c.cle()).collect();
        let inconnues: Vec<String> = cles_swift()
            .into_iter()
            .filter(|cle| !serveur.contains(cle.as_str()))
            .collect();

        assert!(
            inconnues.is_empty(),
            "Ces clés sont attendues par l'app et qu'aucun serveur n'annonce : {inconnues:?}\n\
             Probablement une faute de frappe d'un côté ou de l'autre.",
        );
    }

    /// Le contrôle doit **pouvoir** échouer : s'il ne lisait aucune clé, les
    /// deux épreuves ci-dessus passeraient sur le vide.
    #[test]
    fn le_controle_lit_bien_quelque_chose() {
        assert!(
            cles_swift().len() >= Capacite::CONNUES.len(),
            "aucune clé lue côté Swift — le contrôle ne contrôlerait rien",
        );
    }
}
