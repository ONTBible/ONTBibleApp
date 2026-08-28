//! Ce que le lecteur produit, et qui doit suivre d'un appareil à l'autre.
//!
//! **Attention — données de catégorie particulière.** Les surlignages et les
//! notes d'un lecteur de Bible, rattachés à une identité, révèlent des
//! convictions religieuses : article 9 du RGPD. Conséquences inscrites dans
//! la conception :
//!
//! - la synchronisation est **facultative** — l'app fonctionne entièrement
//!   sans compte, et c'est le comportement par défaut ;
//! - on stocke le strict nécessaire : pas de texte du verset, seulement sa
//!   *référence*. Le corpus est déjà dans l'app.
//! - tout est effaçable d'un coup (`DELETE /me`).

use serde::{Deserialize, Serialize};

/// Un surlignage, posé sur un verset.
///
/// La référence est `(unité, verset)` et jamais un décalage de caractères :
/// une révision du texte déplacerait les caractères et rendrait le
/// surlignage faux, alors qu'un numéro de verset reste juste.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Highlight {
    pub id: String,
    pub book_id: String,
    pub chapter_id: String,
    pub verse: u32,
    pub color: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
    /// Millisecondes epoch — sert d'arbitre en cas de conflit.
    pub updated_at: i64,
    /// Un objet supprimé est conservé comme pierre tombale jusqu'à son TTL :
    /// sans ça, un appareil resté hors ligne ressusciterait ce qu'un autre
    /// vient d'effacer.
    #[serde(default)]
    pub deleted: bool,
}

impl Highlight {
    pub fn sort_key(&self) -> String {
        format!("HL#{}#{:05}", self.chapter_id, self.verse)
    }
}

/// Où le lecteur en était.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Position {
    pub book_id: String,
    pub chapter_id: String,
    pub chapter_title: String,
    pub verse: u32,
    pub updated_at: i64,
}

/// Ce que le lecteur dit de lui, porté d'un appareil à l'autre.
///
/// ## Pourquoi ces champs-là montent, alors que le texte des versets ne monte
/// pas
///
/// Le refus de garder le texte d'un surlignage ne vient pas d'un principe
/// général de frugalité : il vient de ce que ce texte **révèle une conviction
/// religieuse**, et que l'article 9 du RGPD en fait une catégorie
/// particulière. Un prénom et une bio n'en sont pas — ce sont des données
/// personnelles ordinaires, que le lecteur écrit pour être vu.
///
/// Elles ne montent d'ailleurs que si la synchronisation est **allumée**,
/// comme le reste : le consentement couvre tout ce qui quitte l'appareil.
///
/// ## Le portrait
///
/// Il voyage en base64, dans le même élément. Ce n'est pas élégant, et c'est
/// délibéré : monter un stockage d'objets, ses accès signés et ses règles de
/// partage pour **une vignette par lecteur** coûterait plus à tenir que ce
/// qu'il rapporte.
///
/// La borne vient de DynamoDB, dont un élément ne dépasse pas 400 Kio. On
/// s'arrête bien avant — `PORTRAIT_MAX` —, parce qu'un élément qui frôle sa
/// limite se met à échouer le jour où l'on ajoute un champ à côté.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProfilLecteur {
    #[serde(default)]
    pub nom_dusage: String,
    #[serde(default)]
    pub prenom: String,
    #[serde(default)]
    pub nom: String,
    #[serde(default)]
    pub bio: String,
    /// Le portrait encodé en base64, ou `None`.
    #[serde(default)]
    pub portrait: Option<String>,
    pub updated_at: i64,
}

/// La taille maximale du portrait encodé, en octets.
///
/// 150 Kio quand DynamoDB en admet 400 pour l'élément entier. La marge n'est
/// pas de la prudence vague : elle laisse la place aux champs de texte, à la
/// clé, et surtout à ce que quelqu'un ajoutera dans six mois sans penser à
/// recompter.
pub const PORTRAIT_MAX: usize = 150 * 1024;

impl ProfilLecteur {
    /// Vrai quand le portrait tient dans la borne.
    ///
    /// **Refuser explicitement plutôt que laisser DynamoDB échouer.** Un
    /// élément trop gros rend une erreur de stockage, que le client lit comme
    /// une panne du serveur — et il réessaie, indéfiniment, avec la même image.
    pub fn portrait_tient(&self) -> bool {
        self.portrait
            .as_ref()
            .is_none_or(|p| p.len() <= PORTRAIT_MAX)
    }
}

/// Ce que le client envoie.
#[derive(Debug, Clone, Deserialize)]
pub struct PushRequest {
    #[serde(default)]
    pub highlights: Vec<Highlight>,
    #[serde(default)]
    pub position: Option<Position>,
    /// Le profil, quand le client en a un.
    ///
    /// Facultatif, comme tout le reste de cette requête : une version de l'app
    /// qui ne connaît pas encore le profil ne doit pas voir son envoi refusé.
    #[serde(default)]
    pub profil: Option<ProfilLecteur>,
}

/// Ce que le client reçoit.
#[derive(Debug, Clone, Serialize)]
pub struct PullResponse {
    pub highlights: Vec<Highlight>,
    pub position: Option<Position>,
    pub profil: Option<ProfilLecteur>,
    /// L'horodatage du serveur — le client le renvoie au prochain `since`.
    pub server_time: i64,
}

/// Arbitre un conflit entre deux versions du même objet.
///
/// **Dernier écrit gagné**, arbitré par `updated_at`. C'est le bon compromis
/// ici : un surlignage est un objet minuscule, sans structure interne, qu'une
/// seule personne modifie depuis ses propres appareils. Une fusion à trois
/// branches serait de la complexité sans bénéfice — personne ne modifie
/// simultanément la couleur d'un même verset sur deux téléphones.
///
/// À égalité d'horodatage, le serveur garde sa version : deux appareils dont
/// les horloges concordent à la milliseconde près sont plus probablement le
/// même écrit rejoué qu'un vrai conflit.
pub fn resolve(server: &Highlight, incoming: &Highlight) -> bool {
    incoming.updated_at > server.updated_at
}

#[cfg(test)]
mod tests {
    use super::*;

    fn highlight(updated_at: i64, color: &str) -> Highlight {
        Highlight {
            id: "1".into(),
            book_id: "bereshit".into(),
            chapter_id: "bereshit-18".into(),
            verse: 19,
            color: color.into(),
            note: None,
            updated_at,
            deleted: false,
        }
    }

    #[test]
    fn le_plus_recent_gagne() {
        let server = highlight(1_000, "gold");
        let incoming = highlight(2_000, "sky");
        assert!(resolve(&server, &incoming));
    }

    #[test]
    fn un_ecrit_plus_ancien_est_ignore() {
        let server = highlight(2_000, "gold");
        let incoming = highlight(1_000, "sky");
        assert!(!resolve(&server, &incoming));
    }

    #[test]
    fn a_egalite_le_serveur_garde_sa_version() {
        let server = highlight(1_000, "gold");
        let incoming = highlight(1_000, "sky");
        assert!(!resolve(&server, &incoming));
    }

    #[test]
    fn la_cle_de_tri_ordonne_les_versets_numeriquement() {
        // Sans le remplissage à cinq chiffres, le verset 10 se rangerait avant
        // le verset 9 — l'ordre lexicographique de DynamoDB n'est pas
        // l'ordre numérique.
        let mut keys = vec![
            highlight_at(9).sort_key(),
            highlight_at(10).sort_key(),
            highlight_at(2).sort_key(),
        ];
        keys.sort();

        assert_eq!(
            keys,
            vec![
                highlight_at(2).sort_key(),
                highlight_at(9).sort_key(),
                highlight_at(10).sort_key(),
            ]
        );
    }

    fn highlight_at(verse: u32) -> Highlight {
        Highlight {
            verse,
            ..highlight(0, "gold")
        }
    }
}

/// Le contrat de la borne, avec l'app.
///
/// **Deux nombres écrits dans deux langages, dans deux dossiers, qui doivent
/// s'accorder.** L'app borne le JPEG *avant* encodage ; le serveur borne le
/// base64 *après*. Le base64 enfle d'un tiers, et c'est ce facteur — invisible
/// dans les deux fichiers — qui les relie.
///
/// C'est exactement le motif qu'on collectionne : un type écrit à la main qui
/// doit suivre un contrat qu'il ne surveille pas. Ici il le surveille : baisser
/// `PORTRAIT_MAX` ou monter la borne de l'app fait tomber ce test, au lieu de
/// faire rejeter les portraits d'un lecteur sur trois.
#[cfg(test)]
mod contrat {
    use super::PORTRAIT_MAX;

    const SOURCE: &str = include_str!(
        "../../../app/Packages/ONTFeatures/Sources/YouFeature/Presentation/ProfilDuLecteur.swift"
    );

    /// La borne que l'app s'impose, lue dans son propre code.
    fn borne_de_l_app() -> usize {
        let ligne = SOURCE
            .lines()
            .find(|l| l.contains("static let borne"))
            .expect("`ONTPortrait.borne` a disparu du code de l'app");

        let expression = ligne.split('=').nth(1).expect("borne sans valeur");
        expression
            .split('*')
            .map(|morceau| {
                morceau
                    .trim()
                    .parse::<usize>()
                    .expect("la borne n'est plus un produit d'entiers")
            })
            .product()
    }

    /// Le gonflement du base64 : quatre octets écrits pour trois lus.
    fn en_base64(octets: usize) -> usize {
        octets.div_ceil(3) * 4
    }

    #[test]
    fn ce_que_l_app_envoie_tient_dans_ce_que_le_serveur_admet() {
        let envoye = en_base64(borne_de_l_app());
        assert!(
            envoye <= PORTRAIT_MAX,
            "l'app peut envoyer {envoye} octets de base64, le serveur en admet {PORTRAIT_MAX}",
        );
    }

    /// **Et la marge doit rester franche.**
    ///
    /// Une borne qui frôle la limite tient aujourd'hui et tombe au premier
    /// champ ajouté à côté. Dix pour cent, c'est assez pour qu'un ajout normal
    /// ne la fasse pas basculer, et assez peu pour qu'on ne gaspille pas la
    /// place.
    #[test]
    fn la_marge_reste_franche() {
        let envoye = en_base64(borne_de_l_app());
        let marge = PORTRAIT_MAX - envoye;
        assert!(
            marge >= PORTRAIT_MAX / 10,
            "il ne reste que {marge} octets de marge sur {PORTRAIT_MAX}",
        );
    }
}
