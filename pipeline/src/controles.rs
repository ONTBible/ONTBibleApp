//! Deux contrôles qui mesurent **ce qui est livré**, non ce que le vault dit.
//!
//! ## Pourquoi ils existent tous les deux
//!
//! Le rapport de build savait déjà relever quatre choses — les marqueurs
//! déséquilibrés, les formes en gras hors glossaire, les mots d'or sans fiche,
//! les Shemot sans fiche. Il rendait `0` partout, et **221 liens du corpus
//! livré n'ouvraient rien**.
//!
//! La raison tient en une phrase, et c'est elle qu'il faut retenir : **le
//! rapport normalisait autrement que le consommateur.** Pour décider si
//! `**gibborim**` a bien une fiche, il traversait `forms` et retombait sur
//! `gibbor` ; le nœud livré, lui, porte `lemma: "gibborim"`, et la liseuse
//! indexe par lemme exact. Les deux avaient raison chacun de son côté, et le
//! lecteur voyait « Terme non documenté » sur un mot parfaitement documenté.
//!
//! D'où la règle que ces deux contrôles appliquent, et qui les distingue de
//! tous les précédents :
//!
//! > **On ne mesure pas la source, on mesure `dist/`.** La question n'est pas
//! > « ce terme a-t-il une fiche ? » mais « ce lemme, tel qu'il est écrit dans
//! > le fichier livré, retombe-t-il sur une entrée du **même** fichier ? »
//!
//! ## Le second contrôle, et pourquoi il est ici plutôt que dans une note
//!
//! Le §4.1 du `CLAUDE.md` impose de compter les gloses avant de clore une
//! **parashah** — *« compter avant de clore coûte une commande, et c'est le
//! seul contrôle qui ne dépende pas de ce que le traducteur a fini par trouver
//! évident »*. Une commande qu'il faut penser à lancer est une commande qu'on
//! oublie : elle l'a été le jour même où la règle a été écrite.
//!
//! Elle tourne donc à chaque build, comme les autres.

use std::collections::{BTreeMap, HashSet};

use crate::schema::{Block, Chapter, GlossaryEntry, Inline, ShemEntry};

// ─────────────────────────────────────────────────────────────────────────────
// Parcourir tout ce qui est livré, sans exception
// ─────────────────────────────────────────────────────────────────────────────

/// Applique `f` à chaque nœud d'un bloc, quel que soit le bloc.
///
/// **Le `match` est exhaustif, et c'est délibéré.** Les parcours existants du
/// pipeline ne regardent que `Heading`, `Para` et `Verses` : une liste, une
/// citation ou un tableau n'y est jamais visité. C'est la forme exacte du
/// défaut que le journal a nommé `unites(livre)` — un chemin de traversée qui
/// ne voit pas une source —, et un contrôle bâti dessus hériterait du trou
/// qu'il est censé mesurer.
///
/// Écrire `_ => {}` rendrait de plus le compilateur muet le jour où un
/// variant s'ajoute. Ici, il refusera de compiler.
pub fn pour_chaque_inline(bloc: &Block, f: &mut impl FnMut(&Inline)) {
    match bloc {
        Block::Heading { nodes, .. } | Block::Para { nodes } | Block::Quote { nodes } => {
            descendre(nodes, f)
        }
        Block::Verses { verses } => {
            for v in verses {
                descendre(&v.nodes, f)
            }
        }
        Block::List { items, .. } => {
            for item in items {
                descendre(item, f)
            }
        }
        Block::Table { headers, rows } => {
            for cellule in headers {
                descendre(cellule, f)
            }
            for ligne in rows {
                for cellule in ligne {
                    descendre(cellule, f)
                }
            }
        }
        Block::Rule => {}
    }
}

/// Descend dans un arbre d'inline. Même exigence d'exhaustivité que ci-dessus.
fn descendre(nodes: &[Inline], f: &mut impl FnMut(&Inline)) {
    for n in nodes {
        f(n);
        match n {
            Inline::Em { children }
            | Inline::Accentuation { children }
            | Inline::Gloss { children }
            | Inline::Link { children, .. } => descendre(children, f),
            Inline::Text { .. }
            | Inline::Term { .. }
            | Inline::Shem { .. }
            | Inline::Translit { .. }
            | Inline::Heb { .. }
            | Inline::Break => {}
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Contrôle 1 — chaque lemme émis retombe-t-il sur une entrée du même dist/ ?
// ─────────────────────────────────────────────────────────────────────────────

/// Un lien livré qui n'ouvre rien.
pub struct LienMort {
    /// `term` ou `shem` — les deux couches touchables.
    pub couche: &'static str,
    /// Ce que le lecteur voit, casse comprise : `mal'akhim`.
    pub forme: String,
    /// Ce que le nœud porte, et que la liseuse cherchera : `malakhim`.
    pub lemme: String,
    pub occurrences: usize,
    /// Où on l'a rencontré la première fois — `bereshit-16`, `lexique/gibbor`.
    pub ou: String,
    /// L'entrée qui *déclare* cette forme, quand il y en a une.
    ///
    /// C'est ce champ qui sépare les deux populations et qui rend la section
    /// actionnable : avec une piste, l'entrée existe et la liseuse ment au
    /// lecteur ; sans piste, la fiche est réellement à écrire.
    pub entree_reelle: Option<String>,
}

/// Relève tous les liens livrés qui ne retombent sur aucune entrée livrée.
///
/// `unites` et `fiches` sont parcourus tous les deux : une fiche de lexique est
/// livrée au même titre qu'un chapitre, ses `[[…]]` et ses `**…**` sont rendus
/// touchables, et ses liens morts atteignent donc le lecteur exactement comme
/// ceux d'un verset.
pub fn liens_morts(
    unites: &[&Chapter],
    glossaire: &[GlossaryEntry],
    shemot: &[ShemEntry],
) -> Vec<LienMort> {
    let lemmes_gl: HashSet<&str> = glossaire.iter().map(|e| e.lemma.as_str()).collect();
    let lemmes_sh: HashSet<&str> = shemot.iter().map(|e| e.lemma.as_str()).collect();

    // La table qui donne la piste : forme déclarée, slugifiée comme le nœud
    // l'est, vers le lemme qui la déclare. C'est **exactement** la
    // normalisation que le rapport faisait en silence et que le fichier livré
    // ne fait pas ; l'écrire ici la rend visible au lieu de la rendre implicite.
    let mut declarants: BTreeMap<String, &str> = BTreeMap::new();
    for e in glossaire {
        for f in &e.forms {
            declarants.insert(crate::inline::slugify(f), e.lemma.as_str());
        }
    }

    // Clé : la couche et le lemme émis. Deux formes qui slugifient pareil sont
    // le même lien mort du point de vue de la liseuse, qui ne voit que le lemme.
    let mut vus: BTreeMap<(&'static str, String), LienMort> = BTreeMap::new();
    let mut relever = |couche: &'static str, v: &str, lemme: &str, ou: &str| {
        let vivant = match couche {
            "shem" => lemmes_sh.contains(lemme),
            _ => lemmes_gl.contains(lemme),
        };
        if vivant {
            return;
        }
        vus.entry((couche, lemme.to_string()))
            .and_modify(|l| l.occurrences += 1)
            .or_insert_with(|| LienMort {
                couche,
                forme: v.to_string(),
                lemme: lemme.to_string(),
                occurrences: 1,
                ou: ou.to_string(),
                entree_reelle: declarants.get(lemme).map(|s| s.to_string()),
            });
    };

    for unite in unites {
        for bloc in &unite.blocks {
            pour_chaque_inline(bloc, &mut |n| match n {
                Inline::Term { v, lemma } => relever("term", v, lemma, &unite.id),
                Inline::Shem { v, lemma } => relever("shem", v, lemma, &unite.id),
                _ => {}
            });
        }
    }
    for e in glossaire {
        let ou = format!("lexique/{}", e.lemma);
        for blocs in [e.definition.as_ref(), e.tagging_note.as_ref()]
            .into_iter()
            .flatten()
        {
            for bloc in blocs {
                pour_chaque_inline(bloc, &mut |n| match n {
                    Inline::Term { v, lemma } => relever("term", v, lemma, &ou),
                    Inline::Shem { v, lemma } => relever("shem", v, lemma, &ou),
                    _ => {}
                });
            }
        }
    }
    for e in shemot {
        let ou = format!("lexique/{}", e.lemma);
        for bloc in &e.definition {
            pour_chaque_inline(bloc, &mut |n| match n {
                Inline::Term { v, lemma } => relever("term", v, lemma, &ou),
                Inline::Shem { v, lemma } => relever("shem", v, lemma, &ou),
                _ => {}
            });
        }
    }

    let mut morts: Vec<LienMort> = vus.into_values().collect();
    // Les plus fréquents d'abord : c'est l'ordre dans lequel on les corrige.
    morts.sort_by(|a, b| {
        b.occurrences
            .cmp(&a.occurrences)
            .then_with(|| a.lemme.cmp(&b.lemme))
    });
    morts
}

// ─────────────────────────────────────────────────────────────────────────────
// Contrôle 2 — la densité de glose, §4.1
// ─────────────────────────────────────────────────────────────────────────────

/// L'unité que le §4.1 nomme comme référence.
pub const REFERENCE: &str = "bereshit-4";

/// Ce qu'une unité porte comme apparat, mesuré sur ce qui est livré.
pub struct Densite {
    pub unite: String,
    pub versets: u32,
    pub gloses: usize,
    /// Les mots du corps seul — gloses, translittérations et hébreu retirés.
    pub mots_corps: usize,
    /// Les mots qui sont *dans* une glose.
    pub mots_gloses: usize,
    /// La plus longue glose de l'unité, en mots.
    pub plus_longue: usize,
}

impl Densite {
    /// Gloses pour mille mots de corps.
    ///
    /// **C'est cette mesure-là qui compare, et non les gloses par verset.** Un
    /// verset ONT n'a pas de longueur fixe : le *Chazon Avraham* découpe une
    /// phrase de témoin en plusieurs versets courts là où *Bereshit* suit le
    /// verset biblique. Rapporter à un dénominateur variable fait dire au ratio
    /// ce qu'on a décidé du découpage, pas ce qu'on a écrit d'apparat.
    pub fn pour_mille(&self) -> f64 {
        if self.mots_corps == 0 {
            return 0.0;
        }
        1000.0 * self.gloses as f64 / self.mots_corps as f64
    }

    /// Mots d'explication par mot de corps — le **volume**, non la fréquence.
    ///
    /// Les deux se séparent, et il faut les deux : une unité peut porter tout
    /// le volume attendu en quelques blocs énormes. Le volume dit si l'implicite
    /// a été explicité ; la fréquence dit s'il l'a été *là où il se trouve*.
    pub fn volume(&self) -> f64 {
        if self.mots_corps == 0 {
            return 0.0;
        }
        self.mots_gloses as f64 / self.mots_corps as f64
    }
}

/// Compte les mots d'une chaîne — tout ce qui n'est ni espace ni ponctuation.
fn mots(s: &str) -> usize {
    s.split(|c: char| !(c.is_alphanumeric() || c == '\'' || c == '\u{2019}' || c == '-'))
        .filter(|m| !m.is_empty())
        .count()
}

/// Les mots portés par un arbre d'inline, gloses **exclues**.
fn mots_hors_glose(nodes: &[Inline], total: &mut usize) {
    for n in nodes {
        match n {
            Inline::Text { v } | Inline::Term { v, .. } | Inline::Shem { v, .. } => {
                *total += mots(v)
            }
            Inline::Em { children }
            | Inline::Accentuation { children }
            | Inline::Link { children, .. } => mots_hors_glose(children, total),
            // La glose est ce qu'on mesure *contre* le corps : elle n'en fait
            // pas partie.
            Inline::Gloss { .. } => {}
            // Le niveau 3 et l'hébreu ne sont pas de la prose française et
            // fausseraient le dénominateur — un verset dense en niveau 3
            // paraîtrait moins glosé qu'il ne l'est.
            Inline::Translit { .. } | Inline::Heb { .. } | Inline::Break => {}
        }
    }
}

/// Les mots portés par un arbre d'inline, sans distinction — pour l'intérieur
/// d'une glose.
fn mots_tout(nodes: &[Inline], total: &mut usize) {
    for n in nodes {
        match n {
            Inline::Text { v } | Inline::Term { v, .. } | Inline::Shem { v, .. } => {
                *total += mots(v)
            }
            Inline::Em { children }
            | Inline::Accentuation { children }
            | Inline::Gloss { children }
            | Inline::Link { children, .. } => mots_tout(children, total),
            Inline::Translit { .. } | Inline::Heb { .. } | Inline::Break => {}
        }
    }
}

/// Mesure une unité.
///
/// **Le corps seul, pas les notes de bas de section.** L'apparat détaillé vit
/// dans le pied (§2.7), et il est légitime qu'il soit dense ; le §4.1 parle de
/// ce que le lecteur rencontre *en lisant le verset*. Compter le pied ferait
/// passer pour glosée une unité dont le corps est muet.
pub fn densite(unite: &Chapter) -> Densite {
    let mut mots_corps = 0usize;
    let mut mots_gloses = 0usize;
    let mut gloses = 0usize;
    let mut plus_longue = 0usize;

    for bloc in &unite.blocks {
        pour_chaque_inline(bloc, &mut |n| {
            if let Inline::Gloss { children } = n {
                gloses += 1;
                let mut m = 0usize;
                mots_tout(children, &mut m);
                mots_gloses += m;
                plus_longue = plus_longue.max(m);
            }
        });
        // Le corps se compte bloc par bloc, sans descendre dans les gloses.
        match bloc {
            Block::Heading { nodes, .. } | Block::Para { nodes } | Block::Quote { nodes } => {
                mots_hors_glose(nodes, &mut mots_corps)
            }
            Block::Verses { verses } => {
                for v in verses {
                    mots_hors_glose(&v.nodes, &mut mots_corps)
                }
            }
            Block::List { items, .. } => {
                for item in items {
                    mots_hors_glose(item, &mut mots_corps)
                }
            }
            Block::Table { headers, rows } => {
                for c in headers {
                    mots_hors_glose(c, &mut mots_corps)
                }
                for l in rows {
                    for c in l {
                        mots_hors_glose(c, &mut mots_corps)
                    }
                }
            }
            Block::Rule => {}
        }
    }

    Densite {
        unite: unite.id.clone(),
        versets: unite.verse_count,
        gloses,
        mots_corps,
        mots_gloses,
        plus_longue,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::schema::{ChapterKind, Status, Verse};

    fn entree(lemma: &str, title: &str, forms: &[&str]) -> GlossaryEntry {
        GlossaryEntry {
            lemma: lemma.into(),
            title: title.into(),
            tagged: true,
            forms: forms.iter().map(|f| (*f).into()).collect(),
            hebrew: None,
            rendering: None,
            definition: None,
            tagging_note: None,
            first_use: None,
            source_section: None,
            count: 0,
            body_count: 0,
            gloss_count: 0,
        }
    }

    fn texte(s: &str) -> Inline {
        Inline::Text { v: s.into() }
    }

    fn unite(blocks: Vec<Block>) -> Chapter {
        Chapter {
            id: "essai-1".into(),
            book_id: "essai".into(),
            kind: ChapterKind::Chapter,
            n: 1,
            title: "Essai 1".into(),
            title_nodes: vec![],
            subtitle: None,
            status: Status::Brouillon,
            blocks,
            footer: None,
            verse_count: 1,
            lemmas: vec![],
            source: "essai.md".into(),
        }
    }

    /// **Le contrôle doit voir une liste, une citation et un tableau.**
    ///
    /// C'est sa raison d'être : les parcours existants n'inspectent que
    /// `Heading`, `Para` et `Verses`. Une fiche de lexique écrite en liste — et
    /// le §2.5 ter les autorise depuis le 30 août — y serait invisible, et le
    /// contrôle rendrait `0` sur un corpus plein de liens morts.
    #[test]
    fn les_blocs_que_les_autres_parcours_oublient_sont_visites() {
        let mort = |l: &str| Inline::Term {
            v: l.into(),
            lemma: l.into(),
        };
        let u = unite(vec![
            Block::List {
                ordered: false,
                items: vec![vec![mort("dans-une-liste")]],
            },
            Block::Quote {
                nodes: vec![mort("dans-une-citation")],
            },
            Block::Table {
                headers: vec![vec![mort("dans-un-en-tete")]],
                rows: vec![vec![vec![mort("dans-une-cellule")]]],
            },
        ]);
        let morts = liens_morts(&[&u], &[], &[]);
        let lemmes: Vec<&str> = morts.iter().map(|m| m.lemme.as_str()).collect();
        assert_eq!(
            lemmes,
            [
                "dans-un-en-tete",
                "dans-une-cellule",
                "dans-une-citation",
                "dans-une-liste"
            ]
        );
    }

    /// **Éprouvé sur un cas dont on connaît la réponse.** Un lemme vivant ne
    /// doit rien produire — sans quoi le contrôle crierait toujours, et une
    /// garde qui crie toujours ne garde plus rien.
    #[test]
    fn un_lemme_vivant_ne_produit_aucun_signalement() {
        let u = unite(vec![Block::Verses {
            verses: vec![Verse {
                n: 1,
                nodes: vec![Inline::Term {
                    v: "chesed".into(),
                    lemma: "chesed".into(),
                }],
            }],
        }]);
        let entree = entree("chesed", "chesed", &["chesed"]);
        assert!(liens_morts(&[&u], &[entree], &[]).is_empty());
    }

    /// Le cœur du défaut : la forme fléchie est **déclarée**, donc l'entrée
    /// existe, et le lien meurt quand même parce que le lemme émis est la
    /// forme et non le lemme canonique. La piste doit le dire.
    #[test]
    fn une_forme_declaree_qui_meurt_porte_son_entree_reelle() {
        let u = unite(vec![Block::Para {
            nodes: vec![Inline::Term {
                v: "gibborim".into(),
                lemma: "gibborim".into(),
            }],
        }]);
        let entree = entree("gibbor", "gibbor", &["gibbor", "gibborim", "gibor"]);
        let morts = liens_morts(&[&u], &[entree], &[]);
        assert_eq!(morts.len(), 1);
        assert_eq!(morts[0].entree_reelle.as_deref(), Some("gibbor"));
    }

    /// L'apostrophe est le cas qu'aucune traversée de `forms` ne rattraperait :
    /// `forms` garde `mal'akhim`, le nœud porte `malakhim`. La piste doit le
    /// retrouver quand même, parce qu'on slugifie **les deux côtés**.
    #[test]
    fn la_piste_slugifie_aussi_la_forme_declaree() {
        let u = unite(vec![Block::Para {
            nodes: vec![Inline::Term {
                v: "mal'akhim".into(),
                lemma: "malakhim".into(),
            }],
        }]);
        let entree = entree("malakh", "mal'akh", &["mal'akh", "mal'akhim"]);
        let morts = liens_morts(&[&u], &[entree], &[]);
        assert_eq!(morts[0].entree_reelle.as_deref(), Some("malakh"));
    }

    /// Une glose ne compte pas dans le corps, et le corps ne compte pas dans la
    /// glose : c'est tout le sens d'un rapport entre les deux.
    #[test]
    fn la_glose_ne_se_compte_pas_dans_le_corps() {
        let u = unite(vec![Block::Verses {
            verses: vec![Verse {
                n: 1,
                nodes: vec![
                    texte("un deux trois"),
                    Inline::Gloss {
                        children: vec![texte("quatre cinq")],
                    },
                ],
            }],
        }]);
        let d = densite(&u);
        assert_eq!(d.mots_corps, 3);
        assert_eq!(d.mots_gloses, 2);
        assert_eq!(d.gloses, 1);
        assert_eq!(d.plus_longue, 2);
    }

    /// Le niveau 3 est hors du dénominateur : sinon une unité dense en
    /// translittérations paraîtrait moins glosée qu'elle ne l'est.
    #[test]
    fn le_niveau_trois_ne_gonfle_pas_le_denominateur() {
        let u = unite(vec![Block::Para {
            nodes: vec![
                texte("un deux"),
                Inline::Translit {
                    translit: "chesed".into(),
                    hebrew: "חֶסֶד".into(),
                },
            ],
        }]);
        assert_eq!(densite(&u).mots_corps, 2);
    }
}
