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

use crate::schema::{Block, Chapter, CibleDeLaReference, Inline, PorteeDeLaReference};

/// Où mène un renvoi résolu.
pub struct Cible {
    pub livre: String,
    pub unite: String,
    /// Le verset **interne** visé, quand on peut l'établir sans supposer.
    ///
    /// La numérotation ONT repart de 1 à chaque unité (§2.2) : le verset
    /// biblique 9:5 est le cinquième de l'unité qui couvre 9:1-17, mais le
    /// troisième de celle qui couvre 9:18-29 ne s'appelle pas 20.
    ///
    /// **Nul dès que le compte ne confirme pas le calcul.** Voir `interne`.
    pub verset: Option<u32>,
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
    /// Identifiant du livre → ses unités, avec leur plage et leur nombre de
    /// versets. Le compte sert à **vérifier** le calcul de l'indice interne.
    plages: HashMap<String, Vec<(String, Plage, u32)>>,
}

impl Index {
    /// Construit la table depuis le corpus déjà assemblé.
    pub fn nouveau(corpora: &[crate::schema::Corpus]) -> Self {
        let mut livres = HashMap::new();
        let mut plages: HashMap<String, Vec<(String, Plage, u32)>> = HashMap::new();

        for corpus in corpora {
            for mode in &corpus.modes {
                for livre in &mode.books {
                    livres.insert(livre.title.clone(), livre.id.clone());
                    // Le pont français aussi : une glose peut écrire
                    // « Genèse 1:4 » comme « Bereshit 1:4 ».
                    if !livre.french.is_empty() {
                        livres.insert(livre.french.clone(), livre.id.clone());
                    }
                    let unites: Vec<(String, Plage, u32)> = livre
                        .chapters
                        .iter()
                        .filter_map(|u| {
                            let r = u.subtitle.as_ref()?.reference.as_ref()?;
                            let versets = u
                                .blocks
                                .iter()
                                .map(|b| match b {
                                    Block::Verses { verses } => verses.len() as u32,
                                    _ => 0,
                                })
                                .sum();
                            Some((u.id.clone(), lire_plage(r)?, versets))
                        })
                        .collect();
                    plages.insert(livre.id.clone(), unites);
                }
            }
        }
        Self { livres, plages }
    }

    /// L'identifiant du livre que ce nom désigne — nom ONT ou nom français.
    fn livre(&self, nom: &str) -> Option<&String> {
        self.livres.get(nom)
    }

    /// Vrai quand le corpus porte cette unité.
    ///
    /// Sert au système **ONT**, où le numéro écrit *est* celui de l'unité :
    /// il n'y a rien à chercher dans les plages, seulement à vérifier que
    /// l'unité existe. Sans cette vérification, « *Yovelim* 11 » rendrait
    /// `yovelim-11` — un identifiant bien formé vers un livre que personne
    /// n'a traduit.
    fn porte_l_unite(&self, livre: &str, unite: &str) -> bool {
        self.plages
            .get(livre)
            .is_some_and(|u| u.iter().any(|(id, _, _)| id == unite))
    }

    /// L'unité qui contient ce renvoi, s'il en existe une.
    fn resoudre(&self, livre: &str, chapitre: u32, verset: Option<u32>) -> Option<Cible> {
        let id = self.livres.get(livre)?;
        let v = verset.unwrap_or(1);
        let point = (chapitre, v);
        let (unite, plage, compte) = self
            .plages
            .get(id)?
            .iter()
            .find(|(_, p, _)| point >= p.debut && point <= p.fin)?;
        Some(Cible {
            livre: id.clone(),
            unite: unite.clone(),
            verset: verset.and_then(|v| interne(plage, *compte, chapitre, v)),
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

/// **Donne sa destination à chaque `Reference` d'un arbre de blocs.**
///
/// ## Pourquoi une seconde passe, à côté de `lier`
///
/// `lier` découpe du **texte nu** et le remplace par un lien absolu. Il ne
/// voit plus rien à découper depuis que `parse_inline` reconnaît la référence
/// à la lecture : le nœud existe déjà quand `lier` passe, et un nœud n'est pas
/// du texte.
///
/// Mesuré le 11 septembre 2026, et c'est ce qui a motivé cette fonction : sur
/// la branche qui introduit `Reference`, le corpus portait **915 références et
/// 0 renvoi résolu**, là où `dev` en résolvait 221. La détection avait
/// quadruplé et la navigation était tombée à zéro — un instrument plus exact
/// qui répond à une autre question que celle qu'on pose.
///
/// ## Les deux systèmes ne se résolvent pas pareil
///
/// - **`recu`** — « Genèse 7:11 » nomme un chapitre et un verset du texte
///   reçu. Il faut la table des plages pour savoir quelle unité les couvre, et
///   traduire le verset dans la numérotation de cette unité. C'est exactement
///   ce que `resoudre` fait déjà pour les renvois de texte nu.
/// - **`ont`** — « *Bereshit* 17 » nomme **l'unité elle-même**. Il n'y a rien
///   à chercher : l'identifiant se compose, et la seule question est de savoir
///   si le corpus le porte. Le passer par `resoudre` serait une faute discrète
///   — le numéro y serait lu comme un chapitre reçu, ce qui tombe juste pour
///   Bereshit à partir de la troisième unité et faux partout ailleurs.
pub fn resoudre_l_unite(unite: &mut Chapter, index: &Index) {
    // **Les trois endroits où une unité porte des nœuds**, et non le seul
    // qu'on regarde spontanément.
    //
    // `blocks` est le corps, et c'est tout ce que `lier` visite. Or 47 des
    // références de Bereshit vivent dans les **notes de pied** et 19 dans les
    // **nœuds de titre** — deux conteneurs qu'aucune passe n'avait jamais
    // ouverts. Ils ne se voient pas parce qu'une référence non résolue
    // ressemble exactement à du texte.
    resoudre_inline(&mut unite.title_nodes, index);
    resoudre_les_references(&mut unite.blocks, index);
    if let Some(footer) = &mut unite.footer {
        resoudre_les_references(&mut footer.notes, index);
    }
}

pub fn resoudre_les_references(blocs: &mut [Block], index: &Index) {
    for bloc in blocs.iter_mut() {
        // **Exhaustif, sans `_`.** `lier` s'arrête aux quatre blocs de prose
        // et laisse les listes et les tableaux, et c'est resté invisible parce
        // qu'un renvoi non lié ressemble à du texte. Relevé le 11 septembre
        // 2026 : 129 des 342 références sans destination vivaient là, dont des
        // renvois vers Bereshit 1, qui existe depuis le premier jour.
        //
        // Le jour où un bloc s'ajoute, ce `match` cesse de compiler au lieu de
        // l'oublier en silence.
        match bloc {
            Block::Heading { nodes, .. } | Block::Para { nodes } | Block::Quote { nodes } => {
                resoudre_inline(nodes, index)
            }
            Block::Verses { verses } => {
                for v in verses {
                    resoudre_inline(&mut v.nodes, index);
                }
            }
            Block::List { items, .. } => {
                for item in items {
                    resoudre_inline(item, index);
                }
            }
            Block::Table { headers, rows } => {
                for cellule in headers {
                    resoudre_inline(cellule, index);
                }
                for ligne in rows {
                    for cellule in ligne {
                        resoudre_inline(cellule, index);
                    }
                }
            }
            Block::Rule => {}
        }
    }
}

fn resoudre_inline(noeuds: &mut [Inline], index: &Index) {
    for noeud in noeuds {
        // Exhaustif ici aussi, et pour la même raison : une variante à enfants
        // qui s'ajoute doit rougir, pas se taire.
        match noeud {
            Inline::Reference {
                livre,
                systeme,
                chapitre,
                portee,
                cible,
                ..
            } => {
                *cible = viser(index, livre, systeme, *chapitre, portee);
            }
            Inline::Gloss { children }
            | Inline::Em { children }
            | Inline::Accentuation { children }
            | Inline::Link { children, .. } => resoudre_inline(children, index),
            Inline::Text { .. }
            | Inline::Term { .. }
            | Inline::Shem { .. }
            | Inline::Renvoi { .. }
            | Inline::Translit { .. }
            | Inline::Heb { .. }
            | Inline::Break => {}
        }
    }
}

/// Ce que cette référence ouvre, ou rien.
fn viser(
    index: &Index,
    livre: &str,
    systeme: &str,
    chapitre: u32,
    portee: &PorteeDeLaReference,
) -> Option<CibleDeLaReference> {
    let id = index.livre(livre)?;

    // Le verset **écrit**, quelle que soit la portée. Une plage vise son
    // ouverture : « 11:26-32 » amène à 26, comme un renvoi ordinaire.
    let verset = match portee {
        PorteeDeLaReference::Chapitre => None,
        PorteeDeLaReference::Verset { n } => Some(*n),
        PorteeDeLaReference::Plage { premier, .. } => Some(*premier),
    };

    if systeme == "ont" {
        let unite = format!("{id}-{chapitre}");
        if !index.porte_l_unite(id, &unite) {
            return None;
        }
        // Le verset est **déjà** dans la numérotation de l'unité — le système
        // ONT ne connaît pas d'autre compte. Rien à traduire.
        return Some(CibleDeLaReference {
            livre: id.clone(),
            unite,
            verset,
        });
    }

    let vise = index.resoudre(livre, chapitre, verset)?;
    Some(CibleDeLaReference {
        livre: vise.livre,
        unite: vise.unite,
        verset: vise.verset,
    })
}

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
            // `?v=` désigne le verset et `#v` l'ancre : le premier le met en
            // évidence, le second y fait défiler. Les deux existaient déjà
            // sur le site ; il n'y avait que personne pour les viser.
            href: match cible.verset {
                Some(v) => format!("{SITE}/fr/lire/{}/{}?v={v}#v{v}", cible.livre, cible.unite),
                None => format!("{SITE}/fr/lire/{}/{}", cible.livre, cible.unite),
            },
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
    // Ici plutôt qu'en tête de module : ces trois-là ne servent qu'à monter un
    // `Chapter` d'essai. Importés à la racine, ils faisaient rougir
    // `clippy --all-targets -- -D warnings` — la CI compile la bibliothèque
    // **sans** `cfg(test)`, et n'y voyait que des imports morts.
    use crate::schema::{ChapterKind, Footer, Status};

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
            ("bereshit-8".to_string(), lire_plage("9:1-17").unwrap(), 17),
            ("bereshit-9".to_string(), lire_plage("9:18-29").unwrap(), 12),
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

    fn index_d_essai() -> Index {
        Index {
            livres: HashMap::from([
                ("Bereshit".into(), "bereshit".into()),
                ("Genèse".into(), "bereshit".into()),
            ]),
            plages: HashMap::from([(
                "bereshit".to_string(),
                vec![
                    (
                        "bereshit-1".to_string(),
                        lire_plage("1:1 — 2:3").unwrap(),
                        34,
                    ),
                    ("bereshit-2".to_string(), lire_plage("2:4-25").unwrap(), 22),
                ],
            )]),
        }
    }

    fn reference(livre: &str, systeme: &str, chapitre: u32, portee: PorteeDeLaReference) -> Inline {
        Inline::Reference {
            v: format!("{livre} {chapitre}"),
            livre: livre.to_string(),
            systeme: systeme.to_string(),
            chapitre,
            portee,
            cible: None,
        }
    }

    fn cible(noeud: &Inline) -> Option<CibleDeLaReference> {
        match noeud {
            Inline::Reference { cible, .. } => cible.clone(),
            _ => panic!("pas une référence"),
        }
    }

    /// **Le défaut du 11 septembre 2026, retourné en contrôle.**
    ///
    /// Les notes de pied et les nœuds de titre portaient 66 références que
    /// personne ne résolvait, parce que la passe ne visitait que `blocks`. Ce
    /// test rougit contre le code d'avant : il place la même référence dans
    /// les trois conteneurs et exige les trois.
    #[test]
    fn les_trois_conteneurs_d_une_unite_sont_visites() {
        let index = index_d_essai();
        let mut unite = Chapter {
            id: "bereshit-1".into(),
            book_id: "bereshit".into(),
            kind: ChapterKind::Chapter,
            n: 1,
            title: "Bereshit 1".into(),
            title_nodes: vec![reference(
                "Genèse",
                "recu",
                1,
                PorteeDeLaReference::Verset { n: 4 },
            )],
            subtitle: None,
            status: Status::Locked,
            blocks: vec![Block::Para {
                nodes: vec![reference(
                    "Genèse",
                    "recu",
                    1,
                    PorteeDeLaReference::Verset { n: 4 },
                )],
            }],
            footer: Some(Footer {
                version: None,
                locked: true,
                notes: vec![Block::List {
                    ordered: false,
                    items: vec![vec![reference(
                        "Genèse",
                        "recu",
                        1,
                        PorteeDeLaReference::Verset { n: 4 },
                    )]],
                }],
            }),
            verse_count: 34,
            lemmas: vec![],
            source: String::new(),
        };

        resoudre_l_unite(&mut unite, &index);

        let titre = cible(&unite.title_nodes[0]);
        assert_eq!(
            titre.as_ref().map(|c| c.unite.as_str()),
            Some("bereshit-1"),
            "le titre"
        );

        let Block::Para { nodes } = &unite.blocks[0] else {
            panic!("pas un para")
        };
        assert_eq!(
            cible(&nodes[0]).map(|c| c.unite),
            Some("bereshit-1".into()),
            "le corps"
        );

        let Some(Block::List { items, .. }) = unite.footer.as_ref().map(|f| &f.notes[0]) else {
            panic!("pas une liste")
        };
        assert_eq!(
            cible(&items[0][0]).map(|c| c.unite),
            Some("bereshit-1".into()),
            "la note"
        );
    }

    /// **Le système ONT ne se résout pas par les plages, et le confondre est
    /// une faute discrète.**
    ///
    /// « *Bereshit* 2 » en système ONT nomme l'unité 2. Passé par `resoudre`,
    /// le 2 serait lu comme un chapitre reçu et tomberait dans `bereshit-1`,
    /// qui couvre 1:1 — 2:3. Juste par accident pour les unités tardives,
    /// faux ici.
    #[test]
    fn une_reference_ont_nomme_l_unite_pas_le_chapitre_recu() {
        let index = index_d_essai();
        let ont = viser(&index, "Bereshit", "ont", 2, &PorteeDeLaReference::Chapitre);
        assert_eq!(ont.map(|c| c.unite), Some("bereshit-2".into()));

        let recu = viser(&index, "Genèse", "recu", 2, &PorteeDeLaReference::Chapitre);
        assert_eq!(recu.map(|c| c.unite), Some("bereshit-1".into()));
    }

    /// Un livre non traduit rend `None`, et non un identifiant bien formé.
    #[test]
    fn un_livre_absent_du_corpus_ne_vise_rien() {
        let index = index_d_essai();
        assert!(viser(&index, "Ésaïe", "recu", 40, &PorteeDeLaReference::Chapitre).is_none());
        // Bien formé, mais l'unité n'existe pas : « Bereshit 41 » sur un
        // corpus qui s'arrête à la deuxième unité.
        assert!(viser(
            &index,
            "Bereshit",
            "ont",
            41,
            &PorteeDeLaReference::Chapitre
        )
        .is_none());
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

/// L'indice interne d'un verset biblique dans son unité.
///
/// ## Pourquoi ce calcul refuse de conclure la moitié du temps
///
/// La numérotation ONT repart de 1 à chaque unité (§2.2). Convertir un renvoi
/// biblique en indice interne demande donc de compter depuis le début de la
/// plage — et ce compte n'est juste **que si l'unité contient exactement les
/// versets que sa plage annonce**.
///
/// Or ce n'est pas toujours le cas : l'unité 2 de *Bereshit* annonce `2:4-25`,
/// soit vingt-deux versets, et n'en porte que vingt et un — deux ont été
/// réunis, parce que le texte hébreu les tient ensemble. Le calcul y donnerait
/// un cran de décalage.
///
/// **La fonction vérifie donc son hypothèse avant de rendre un résultat**, et
/// rend `None` dès qu'elle ne tient pas. Un renvoi mène alors à l'unité, sans
/// viser de verset : mieux vaut arriver au bon endroit sans précision que
/// pointer une ligne à côté avec assurance.
fn interne(plage: &Plage, compte: u32, chapitre: u32, verset: u32) -> Option<u32> {
    // Une plage qui enjambe deux chapitres demanderait de connaître la
    // longueur du premier. On ne la devine pas.
    if plage.debut.0 != plage.fin.0 {
        return None;
    }
    if chapitre != plage.debut.0 {
        return None;
    }

    let debut = plage.debut.1;
    if verset < debut {
        return None;
    }

    // Un chapitre entier : la plage ne borne pas la fin, seul le compte le
    // fait. Sinon, la plage annonce un nombre de versets — et il doit tomber
    // juste, sans quoi l'unité a réuni ou séparé quelque chose.
    if plage.fin.1 != u32::MAX {
        let annonces = plage.fin.1.checked_sub(debut)? + 1;
        if annonces != compte {
            return None;
        }
    }

    let indice = verset - debut + 1;
    (indice <= compte).then_some(indice)
}

#[cfg(test)]
mod tests_du_verset {
    use super::*;

    fn plage(s: &str) -> Plage {
        lire_plage(s).expect("une plage lisible")
    }

    /// Le cas courant : la plage annonce ce que l'unité contient.
    #[test]
    fn un_verset_se_situe_quand_le_compte_tombe_juste() {
        assert_eq!(interne(&plage("9:1-17"), 17, 9, 5), Some(5));
        assert_eq!(interne(&plage("9:18-29"), 12, 9, 20), Some(3));
        assert_eq!(interne(&plage("3"), 24, 3, 7), Some(7));
    }

    /// **Le test qui compte.** L'unité 2 de *Bereshit* annonce `2:4-25` —
    /// vingt-deux versets — et n'en porte que vingt et un : deux ont été
    /// réunis. Le calcul donnerait un cran de décalage, donc il refuse.
    #[test]
    fn un_verset_ne_se_situe_pas_quand_l_unite_a_reuni() {
        assert_eq!(interne(&plage("2:4-25"), 21, 2, 10), None);
    }

    /// Une plage qui enjambe deux chapitres demanderait la longueur du
    /// premier. On ne la devine pas.
    #[test]
    fn un_verset_ne_se_situe_pas_a_cheval_sur_deux_chapitres() {
        assert_eq!(interne(&plage("1:1 — 2:3"), 34, 1, 4), None);
    }
}
