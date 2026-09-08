//! Rendre touchable la translittération du niveau 3, quand elle se résout.
//!
//! ## Le défaut, tel que le lecteur le rencontre
//!
//! Le niveau 3 écrit `(*chesed* / חֶסֶד)` à côté du mot traduit. Le lecteur est
//! dessus, il vient de lire le mot hébreu, c'est **exactement** le moment où il
//! voudrait sa fiche — et rien ne répond. La fiche existe pourtant : le même
//! mot, balisé `**chesed**` dans le corps trente lignes plus haut, l'ouvre.
//!
//! L'appareil qui relie un mot à sa fiche s'arrêtait au corps du texte. Le
//! niveau 3 est précisément l'endroit où le lecteur *demande* l'appareil.
//!
//! ## Ce que ce module fait, et surtout ce qu'il ne fait pas
//!
//! Trois résolutions, toutes **exactes**, aucune devinée :
//!
//! 1. la translittération slugifiée **est** un lemme du glossaire ;
//! 2. elle est une **forme déclarée** au §2.5 d'une entrée — c'est la même
//!    règle de déduction que pour le corps ;
//! 3. elle est un **Shem publié**.
//!
//! Tout le reste reste inerte. Sur 1748 translittérations, 631 se résolvent —
//! 257 par lemme exact, 77 par forme déclarée, 297 par Shem — et 1117 non.
//!
//! **Aucune résolution morphologique**, et c'est le cœur de la décision. Ni
//! spirantisation — `lehavdil` vient de `badal`, le bet devenant vet —, ni
//! verbes lamed-he — `vayiven` vient de `banah`, dont le he disparaît. Ces
//! règles existent et se codent. Le problème n'est pas leur difficulté, c'est
//! leur **mode d'échec** : une règle qui se trompe ne rend pas le mot inerte,
//! elle le rend touchable **vers la mauvaise fiche**. Le lecteur arrive
//! ailleurs sans que rien ne le dise. L'abstention se voit, la substitution
//! silencieuse non.
//!
//! Le chemin de sortie n'est donc pas une meilleure heuristique, c'est le
//! §2.5 : une forme déclarée devient touchable pour toujours, et le rapport
//! classe les non résolues par fréquence pour que la déclaration commence par
//! ce qui sert le plus.
//!
//! ## Pourquoi contre le *publié* et non contre les fiches lues
//!
//! Une fiche de Shem qu'aucun `[[…]]` n'emploie **n'entre pas** dans
//! `shemot.json` — le corpus livré ne la porte pas. Résoudre contre les fiches
//! du disque minterait un lien vers une fiche absente du JSON : un mot doré,
//! touchable, qui n'ouvre rien. Exactement le défaut qu'on répare, avec un pas
//! de plus. L'index se monte donc sur les entrées **livrées**.

use std::collections::{BTreeMap, HashMap, HashSet};

use crate::schema::{Block, CibleDuNiveauTrois, Inline};

/// Ce qui est publié, et donc ouvrable.
pub struct Index {
    /// Les lemmes du glossaire livré.
    lemmes: HashSet<String>,
    /// Les formes déclarées au §2.5, slugifiées → leur lemme.
    formes: HashMap<String, String>,
    /// Les Shemot livrés.
    shemot: HashSet<String>,
}

impl Index {
    pub fn nouveau(
        lemmes: impl IntoIterator<Item = String>,
        formes: impl IntoIterator<Item = (String, String)>,
        shemot: impl IntoIterator<Item = String>,
    ) -> Self {
        Self {
            lemmes: lemmes.into_iter().collect(),
            formes: formes.into_iter().collect(),
            shemot: shemot.into_iter().collect(),
        }
    }

    /// La fiche qu'ouvre cette translittération, s'il y en a une.
    ///
    /// **L'ordre des trois épreuves porte une décision.** Le lemme exact passe
    /// avant la forme déclarée : un mot qui *est* une entrée ouvre la sienne,
    /// jamais celle dont il se trouverait aussi être une forme. Et le glossaire
    /// passe avant les Shemot : si un slug existe des deux côtés, c'est
    /// l'intraduisible qui gagne — il a une définition, le Shem a un porteur.
    pub fn cible(&self, translit: &str) -> Option<CibleDuNiveauTrois> {
        let slug = crate::inline::slugify(translit);
        if slug.is_empty() {
            return None;
        }
        if self.lemmes.contains(&slug) {
            return Some(CibleDuNiveauTrois::Term { lemma: slug });
        }
        if let Some(lemme) = self.formes.get(&slug) {
            // La forme n'ouvre pas sa propre fiche — elle n'en a pas —, elle
            // ouvre celle de son lemme. C'est la règle du §2.5, la même que
            // pour le corps du texte.
            return Some(CibleDuNiveauTrois::Term {
                lemma: lemme.clone(),
            });
        }
        if self.shemot.contains(&slug) {
            return Some(CibleDuNiveauTrois::Shem { lemma: slug });
        }
        None
    }
}

/// Ce que la passe n'a pas su résoudre, par forme et par nombre.
///
/// C'est la matière du rapport : la liste de travail du vault, classée par ce
/// qui sert le plus de lecteurs.
#[derive(Debug, Default)]
pub struct Restes(pub BTreeMap<String, u32>);

impl Restes {
    /// Les formes non résolues, la plus fréquente d'abord.
    ///
    /// À nombre égal, l'ordre alphabétique — pour qu'un rapport à l'autre le
    /// même corpus rende le même fichier, et qu'un `diff` ne montre que ce qui
    /// a bougé.
    pub fn par_frequence(&self) -> Vec<(&str, u32)> {
        let mut v: Vec<(&str, u32)> = self.0.iter().map(|(f, n)| (f.as_str(), *n)).collect();
        v.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(b.0)));
        v
    }

    pub fn total(&self) -> u32 {
        self.0.values().sum()
    }
}

/// Résout les translittérations d'une suite de blocs, en place.
pub fn resoudre(blocs: &mut [Block], index: &Index, restes: &mut Restes) {
    for bloc in blocs {
        match bloc {
            Block::Heading { nodes, .. } | Block::Para { nodes } | Block::Quote { nodes } => {
                inline(nodes, index, restes);
            }
            Block::Verses { verses } => {
                for v in verses {
                    inline(&mut v.nodes, index, restes);
                }
            }
            _ => {}
        }
    }
}

/// **La récursion descend**, parce que le niveau 3 vit dans le niveau 2.
///
/// `(*chesed* / חֶסֶד)` s'écrit le plus souvent *dans* une glose. Une passe qui
/// ne regarderait que la surface manquerait la majorité des cas — et ne le
/// dirait pas : elle rendrait simplement moins de mots touchables.
fn inline(noeuds: &mut [Inline], index: &Index, restes: &mut Restes) {
    for noeud in noeuds {
        match noeud {
            Inline::Translit {
                translit, cible, ..
            } => match index.cible(translit) {
                Some(trouvee) => *cible = Some(trouvee),
                None => *restes.0.entry(translit.clone()).or_insert(0) += 1,
            },
            Inline::Gloss { children }
            | Inline::Em { children }
            | Inline::Accentuation { children }
            | Inline::Link { children, .. } => inline(children, index, restes),
            _ => {}
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::schema::Verse;

    fn index() -> Index {
        Index::nouveau(
            ["chesed".to_string(), "avraham".to_string()],
            [("chasdo".to_string(), "chesed".to_string())],
            ["noach".to_string(), "avraham".to_string()],
        )
    }

    fn translit(t: &str) -> Inline {
        Inline::Translit {
            translit: t.into(),
            hebrew: "חֶסֶד".into(),
            cible: None,
        }
    }

    #[test]
    fn le_lemme_exact_ouvre_sa_fiche() {
        assert_eq!(
            index().cible("chesed"),
            Some(CibleDuNiveauTrois::Term {
                lemma: "chesed".into()
            })
        );
    }

    #[test]
    fn une_forme_declaree_ouvre_celle_de_son_lemme() {
        assert_eq!(
            index().cible("chasdo"),
            Some(CibleDuNiveauTrois::Term {
                lemma: "chesed".into()
            })
        );
    }

    #[test]
    fn un_shem_publie_ouvre_sa_fiche() {
        assert_eq!(
            index().cible("Noach"),
            Some(CibleDuNiveauTrois::Shem {
                lemma: "noach".into()
            })
        );
    }

    #[test]
    fn le_glossaire_passe_avant_les_shemot() {
        // `avraham` est des deux côtés dans cette fixture. L'ordre des épreuves
        // doit trancher, et toujours dans le même sens — sans quoi la même
        // entrée ouvrirait une fiche ou l'autre selon l'ordre de parcours d'un
        // `HashSet`, qui n'est pas stable.
        assert_eq!(
            index().cible("Avraham"),
            Some(CibleDuNiveauTrois::Term {
                lemma: "avraham".into()
            })
        );
    }

    #[test]
    fn ce_qui_ne_se_resout_pas_reste_inerte_et_se_compte() {
        let mut blocs = vec![Block::Verses {
            verses: vec![Verse {
                n: 1,
                nodes: vec![translit("vayiven"), translit("vayiven"), translit("chesed")],
            }],
        }];
        let mut restes = Restes::default();
        resoudre(&mut blocs, &index(), &mut restes);

        let Block::Verses { verses } = &blocs[0] else {
            panic!("le bloc de versets");
        };
        let cibles: Vec<Option<&CibleDuNiveauTrois>> = verses[0]
            .nodes
            .iter()
            .map(|n| match n {
                Inline::Translit { cible, .. } => cible.as_ref(),
                _ => None,
            })
            .collect();
        // Les deux `vayiven` restent nuls : aucune règle ne les rattache à
        // `banah`, et en inventer une les enverrait ailleurs en silence.
        assert_eq!(cibles[0], None);
        assert_eq!(cibles[1], None);
        assert!(cibles[2].is_some());
        assert_eq!(restes.par_frequence(), vec![("vayiven", 2)]);
    }

    #[test]
    fn le_niveau_trois_se_resout_jusque_dans_une_glose() {
        // C'est le cas majoritaire, pas un cas limite : le niveau 3 s'écrit le
        // plus souvent au-dedans d'une glose de niveau 2.
        let mut blocs = vec![Block::Para {
            nodes: vec![Inline::Gloss {
                children: vec![translit("chesed")],
            }],
        }];
        let mut restes = Restes::default();
        resoudre(&mut blocs, &index(), &mut restes);

        let Block::Para { nodes } = &blocs[0] else {
            panic!("le paragraphe");
        };
        let Inline::Gloss { children } = &nodes[0] else {
            panic!("la glose");
        };
        let Inline::Translit { cible, .. } = &children[0] else {
            panic!("le niveau 3");
        };
        assert!(cible.is_some(), "une glose cache le niveau 3 à la passe");
    }
}
