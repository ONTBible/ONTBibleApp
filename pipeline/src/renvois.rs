//! Les renvois d'un verset à un autre, rendus navigables.
//!
//! ## Le problème que ça résout, et il est propre à l'ONT
//!
//! Une glose écrit « déjà posé en *Bereshit* 1:4 ». Dans n'importe quelle
//! autre Bible, le lecteur ouvre le chapitre 1 et descend au verset 4. Ici il
//! ne le peut pas : les unités ONT ne coïncident pas avec les chapitres reçus,
//! et rien à l'écran ne dit laquelle contient 1:4.
//!
//! Le renvoi biblique est donc **la seule chose que le lecteur sait** et
//! **précisément ce qu'il ne peut pas suivre**. Le résoudre est le service que
//! seule la machine peut rendre : elle a la table des plages, lui non.
//!
//! ## Ce qu'on émet, et pourquoi ce n'est pas un nœud nouveau
//!
//! Un type de nœud inédit imposerait une montée du schéma du corpus : les
//! liseuses **lèvent** sur un tag inconnu, et toutes les versions installées
//! cesseraient de lire. On réemploie donc `Inline::Link`, que les trois
//! liseuses rendent déjà, avec une adresse **absolue** vers `ontbible.com`.
//!
//! La dégradation est alors douce dans les deux sens : une app ancienne ouvre
//! le site — ce qui marche —, une app à jour reconnaît son propre domaine et
//! navigue au-dedans.

use std::collections::HashMap;

use regex::Regex;
use std::sync::LazyLock;

use crate::schema::{Block, Inline};

/// Où mène un renvoi résolu.
pub struct Cible {
    pub livre: String,
    pub unite: String,
}

/// La plage biblique que recouvre une unité.
///
/// Les bornes sont des couples `(chapitre, verset)`. Un renvoi tombe dedans
/// quand il est entre les deux, au sens de l'ordre lexicographique — ce qui
/// est exactement la façon dont on lit une Bible.
#[derive(Debug, Clone, Copy)]
struct Plage {
    debut: (u32, u32),
    fin: (u32, u32),
}

/// Lit une plage telle que le vault l'écrit.
///
/// Quatre formes, toutes présentes dans le corpus :
///
/// ```text
///     1:1 — 2:3     d'un chapitre à un autre
///     2:4-25        des versets d'un seul chapitre
///     3             un chapitre entier
///     7-8           deux chapitres entiers
/// ```
///
/// Le tiret varie — cadratin, demi-cadratin, trait d'union — parce qu'un
/// texte composé n'emploie pas le même partout. On les accepte tous plutôt que
/// d'imposer une graphie au traducteur.
fn lire_plage(source: &str) -> Option<Plage> {
    let normalise = source.replace(['—', '–'], "-");
    let (gauche, droite) = match normalise.split_once('-') {
        Some((g, d)) => (g.trim(), d.trim()),
        None => (normalise.trim(), normalise.trim()),
    };

    // À gauche : « 1:1 » est un couple, « 3 » est un chapitre entier — il
    // commence donc à son premier verset.
    let debut = match couple(gauche) {
        Some(c) => c,
        None => (gauche.parse().ok()?, 1),
    };

    // À droite, trois cas. « 2:3 » est un couple. « 25 » après un couple est
    // un **verset** du même chapitre — c'est la forme « 2:4-25 ». « 8 » après
    // un chapitre nu est un **chapitre**, qui court jusqu'à sa fin.
    let fin = match couple(droite) {
        Some(c) => c,
        None => {
            let n: u32 = droite.parse().ok()?;
            if gauche.contains(':') {
                (debut.0, n)
            } else {
                (n, u32::MAX)
            }
        }
    };
    Some(Plage { debut, fin })
}

/// « 1:4 » → `(1, 4)`. Un nombre seul n'est pas un couple.
fn couple(s: &str) -> Option<(u32, u32)> {
    let (c, v) = s.split_once(':')?;
    Some((c.trim().parse().ok()?, v.trim().parse().ok()?))
}

/// La table qui résout un renvoi vers l'unité qui le contient.
pub struct Index {
    /// Nom de livre affiché → identifiant du livre.
    livres: HashMap<String, String>,
    /// Identifiant du livre → ses unités, avec leur plage.
    plages: HashMap<String, Vec<(String, Plage)>>,
}

impl Index {
    /// Construit la table depuis le corpus déjà assemblé.
    pub fn nouveau(corpora: &[crate::schema::Corpus]) -> Self {
        let mut livres = HashMap::new();
        let mut plages: HashMap<String, Vec<(String, Plage)>> = HashMap::new();

        for corpus in corpora {
            for mode in &corpus.modes {
                for livre in &mode.books {
                    livres.insert(livre.title.clone(), livre.id.clone());
                    // Le pont français aussi : une glose peut écrire
                    // « Genèse 1:4 » comme « Bereshit 1:4 ».
                    if !livre.french.is_empty() {
                        livres.insert(livre.french.clone(), livre.id.clone());
                    }
                    let unites: Vec<(String, Plage)> = livre
                        .chapters
                        .iter()
                        .filter_map(|u| {
                            let r = u.subtitle.as_ref()?.reference.as_ref()?;
                            Some((u.id.clone(), lire_plage(r)?))
                        })
                        .collect();
                    plages.insert(livre.id.clone(), unites);
                }
            }
        }
        Self { livres, plages }
    }

    /// L'unité qui contient ce renvoi, s'il en existe une.
    fn resoudre(&self, livre: &str, chapitre: u32, verset: Option<u32>) -> Option<Cible> {
        let id = self.livres.get(livre)?;
        let v = verset.unwrap_or(1);
        let point = (chapitre, v);
        let unite = self
            .plages
            .get(id)?
            .iter()
            .find(|(_, p)| point >= p.debut && point <= p.fin)
            .map(|(u, _)| u.clone())?;
        Some(Cible {
            livre: id.clone(),
            unite,
        })
    }
}

/// Un renvoi dans du texte courant — « Bereshit 1:4 », « Yeshayahu 11 ».
///
/// Le nom de livre doit commencer par une capitale et peut porter des
/// apostrophes ou des traits d'union — *Ya'aqov*, *Shir Hashirim*,
/// *Bereshit ha-Yohanan*. Le verset est facultatif : un renvoi à un chapitre
/// entier mène à l'unité qui l'ouvre.
static RENVOI: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"\b([A-ZÉÈ][\p{L}'’-]*(?:\s+[a-z]{2,3}-[\p{L}'’-]+|\s+[A-ZÉÈ][\p{L}'’-]*)?)\s+(\d{1,3})(?::(\d{1,3}))?\b")
        .expect("le motif des renvois")
});

/// Rend navigables les renvois d'un arbre de blocs.
pub fn lier(blocs: &mut Vec<Block>, index: &Index, origine: &str) {
    for bloc in blocs {
        match bloc {
            Block::Heading { nodes, .. } | Block::Para { nodes } | Block::Quote { nodes } => {
                *nodes = lier_inline(std::mem::take(nodes), index, origine);
            }
            Block::Verses { verses } => {
                for v in verses {
                    v.nodes = lier_inline(std::mem::take(&mut v.nodes), index, origine);
                }
            }
            _ => {}
        }
    }
}

/// Découpe les nœuds de texte autour des renvois reconnus.
///
/// **On ne touche qu'au texte nu.** Un renvoi déjà dans un lien resterait
/// imbriqué, et un intraduisible n'est pas un renvoi. La récursion descend
/// donc dans les enfants, mais ne transforme que `Text`.
fn lier_inline(noeuds: Vec<Inline>, index: &Index, origine: &str) -> Vec<Inline> {
    let mut sortie = Vec::new();
    for noeud in noeuds {
        match noeud {
            Inline::Text { v } => decouper(&v, index, origine, &mut sortie),
            Inline::Gloss { children } => sortie.push(Inline::Gloss {
                children: lier_inline(children, index, origine),
            }),
            Inline::Em { children } => sortie.push(Inline::Em {
                children: lier_inline(children, index, origine),
            }),
            Inline::Accentuation { children } => sortie.push(Inline::Accentuation {
                children: lier_inline(children, index, origine),
            }),
            autre => sortie.push(autre),
        }
    }
    sortie
}

/// Le domaine du site, en dur et absolu.
///
/// Absolu pour que les liseuses installées, qui ne savent pas intercepter,
/// ouvrent quand même quelque chose d'utile. Une app à jour reconnaît son
/// propre domaine et navigue au-dedans.
const SITE: &str = "https://ontbible.com";

fn decouper(texte: &str, index: &Index, origine: &str, sortie: &mut Vec<Inline>) {
    let mut curseur = 0usize;
    for m in RENVOI.captures_iter(texte) {
        let entier = m.get(0).expect("le groupe entier");
        let livre = m.get(1).expect("le livre").as_str().trim();
        let chapitre: u32 = match m.get(2).expect("le chapitre").as_str().parse() {
            Ok(n) => n,
            Err(_) => continue,
        };
        let verset = m.get(3).and_then(|g| g.as_str().parse().ok());

        let Some(cible) = index.resoudre(livre, chapitre, verset) else {
            continue;
        };
        // **Un renvoi vers l'unité qu'on lit déjà n'est pas un renvoi.**
        // Le rendre cliquable proposerait au lecteur d'aller là où il est.
        if cible.unite == origine {
            continue;
        }

        if entier.start() > curseur {
            sortie.push(Inline::Text {
                v: texte[curseur..entier.start()].to_string(),
            });
        }
        sortie.push(Inline::Link {
            children: vec![Inline::Text {
                v: entier.as_str().to_string(),
            }],
            href: format!("{SITE}/fr/lire/{}/{}", cible.livre, cible.unite),
        });
        curseur = entier.end();
    }
    if curseur < texte.len() {
        sortie.push(Inline::Text {
            v: texte[curseur..].to_string(),
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn une_plage_se_lit_sous_ses_quatre_formes() {
        assert_eq!(lire_plage("1:1 — 2:3").unwrap().debut, (1, 1));
        assert_eq!(lire_plage("1:1 — 2:3").unwrap().fin, (2, 3));
        assert_eq!(lire_plage("2:4-25").unwrap().debut, (2, 4));
        assert_eq!(lire_plage("2:4-25").unwrap().fin, (2, 25));
        assert_eq!(lire_plage("3").unwrap().debut, (3, 1));
        assert_eq!(lire_plage("3").unwrap().fin, (3, u32::MAX));
        assert_eq!(lire_plage("7-8").unwrap().debut, (7, 1));
        assert_eq!(lire_plage("7-8").unwrap().fin, (8, u32::MAX));
    }

    /// Le cas qui justifie tout le module : *Bereshit* 9:5 n'est pas dans
    /// l'unité 9 mais dans la 8, qui couvre 9:1-17. Aucun lecteur ne peut le
    /// deviner, et c'est pour ça que le renvoi doit être résolu par la machine.
    #[test]
    fn un_renvoi_tombe_dans_l_unite_qui_le_contient() {
        let plages = vec![
            ("bereshit-8".to_string(), lire_plage("9:1-17").unwrap()),
            ("bereshit-9".to_string(), lire_plage("9:18-29").unwrap()),
        ];
        let index = Index {
            livres: HashMap::from([("Bereshit".into(), "bereshit".into())]),
            plages: HashMap::from([("bereshit".to_string(), plages)]),
        };
        assert_eq!(
            index.resoudre("Bereshit", 9, Some(5)).unwrap().unite,
            "bereshit-8"
        );
        assert_eq!(
            index.resoudre("Bereshit", 9, Some(20)).unwrap().unite,
            "bereshit-9"
        );
    }
}

#[cfg(test)]
mod essai_de_reconnaissance {
    use super::*;

    #[test]
    fn le_motif_reconnait_un_renvoi_ordinaire() {
        let c = RENVOI
            .captures(" déjà posé en Bereshit 1:4 — ici")
            .expect("un renvoi");
        assert_eq!(c.get(1).unwrap().as_str(), "Bereshit");
        assert_eq!(c.get(2).unwrap().as_str(), "1");
        assert_eq!(c.get(3).unwrap().as_str(), "4");
    }
}
