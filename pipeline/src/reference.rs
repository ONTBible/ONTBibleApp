//! Le document de référence — `CLAUDE.md` — devient le lexique de la liseuse.
//!
//! C'est ici que se joue l'équivalent ONT de ce que Bible Strong fait avec les
//! numéros Strong : le glossaire des intraduisibles **est** le lexique, et il
//! est déjà écrit. Deux sources s'y combinent :
//!
//! - **§2.5** — la liste des formes *à baliser*. Elle dit ce qui est un
//!   intraduisible, donc ce qui devient une cible de toucher, et quelles
//!   formes dérivées retombent sur le même lemme.
//! - **§3** — les tables de terminologie fixée. Elles donnent l'hébreu, la
//!   traduction ONT arrêtée, et le champ sémantique complet.
//!
//! Le §2.6 fournit en plus les répertoires de noms de livres, d'où l'on tire le
//! titre hébreu de chaque slot.
//!
//! ## Pourquoi on lit le document plutôt que de le recopier
//!
//! Une décision terminologique prise dans le vault doit se retrouver dans la
//! liseuse au prochain build, sans qu'on ait à toucher au pipeline. Recopier le
//! glossaire ici en ferait une seconde source de vérité, et la seconde source
//! est toujours celle qu'on oublie de mettre à jour.
//!
//! Le prix est que ce module analyse un document **écrit pour être lu par un
//! humain**. Il est donc volontairement tolérant : une ligne qu'il ne
//! reconnaît pas est ignorée, jamais fatale.

use std::collections::{BTreeMap, HashMap, HashSet};
use std::path::Path;

use once_cell::sync::Lazy;
use regex::Regex;

use crate::inline::{
    extract_hebrew, has_hebrew, parse_inline, plain_text, slugify, tidy, PlainOptions,
};
use crate::schema::{Block, GlossaryEntry};

/// Une forme balisée citée entre accents graves : `` `**chesed**` ``.
static TAGGED_FORM: Lazy<Regex> = Lazy::new(|| Regex::new(r"`\*\*([^`*]+)\*\*`").unwrap());

/// « Premier emploi en *Bereshit* 8:20 » → `Bereshit 8:20`.
static FIRST_USE: Lazy<Regex> =
    Lazy::new(|| Regex::new(r"(?i)premier emploi[^*]*\*([^*]+)\*\s*(\d+(?::[\d\-–]+)?)?").unwrap());

static HEADING: Lazy<Regex> = Lazy::new(|| Regex::new(r"^(#{1,6})\s+(.*)$").unwrap());
static TABLE_ROW: Lazy<Regex> = Lazy::new(|| Regex::new(r"^\s*\|(.*)\|\s*$").unwrap());
static TABLE_SEPARATOR: Lazy<Regex> = Lazy::new(|| Regex::new(r"^\s*\|[\s:|-]+\|\s*$").unwrap());
static NUMERO_SECTION: Lazy<Regex> = Lazy::new(|| Regex::new(r"^(\d+(?:\.\d+)*)\.?\s").unwrap());
static ITEM: Lazy<Regex> = Lazy::new(|| Regex::new(r"^\s*[-+]\s+").unwrap());
static TETE_DE_NOTE: Lazy<Regex> = Lazy::new(|| Regex::new(r"^[\s/,;:—–-]+").unwrap());
static SECTION_3: Lazy<Regex> = Lazy::new(|| Regex::new(r"^3\.[123]$").unwrap());

struct Section {
    /// Le numéro tel qu'écrit — `2.5`, `3.2`.
    number: Option<String>,
    lines: Vec<String>,
}

/// Découpe le document en sections, repérées par leur numéro de titre.
fn split_sections(lines: &[String]) -> Vec<Section> {
    let mut sections = Vec::new();
    let mut current = Section {
        number: None,
        lines: Vec::new(),
    };

    for line in lines {
        if let Some(h) = HEADING.captures(line) {
            sections.push(current);
            let titre = h.get(2).unwrap().as_str().trim();
            current = Section {
                number: NUMERO_SECTION
                    .captures(titre)
                    .map(|m| m.get(1).unwrap().as_str().to_string()),
                lines: Vec::new(),
            };
            continue;
        }
        current.lines.push(line.clone());
    }
    sections.push(current);
    sections
}

/// Extrait les lignes de tableau d'une section, en cellules brutes.
fn table_rows(lines: &[String]) -> Vec<Vec<String>> {
    lines
        .iter()
        .filter(|l| TABLE_ROW.is_match(l) && !TABLE_SEPARATOR.is_match(l))
        .map(|l| {
            TABLE_ROW
                .captures(l)
                .unwrap()
                .get(1)
                .unwrap()
                .as_str()
                .split('|')
                .map(|c| c.trim().to_string())
                .collect()
        })
        .collect()
}

/// Le texte nu d'une cellule, hébreu compris.
fn cell_text(cell: &str) -> String {
    tidy(&plain_text(
        &parse_inline(cell),
        PlainOptions {
            level3: true,
            ..Default::default()
        },
    ))
}

fn as_blocks(text: &str) -> Option<Vec<Block>> {
    let t = text.trim();
    if t.is_empty() {
        None
    } else {
        Some(vec![Block::Para {
            nodes: parse_inline(t),
        }])
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// §2.5 — les formes à baliser
// ─────────────────────────────────────────────────────────────────────────────

struct TaggedTerm {
    lemma: String,
    title: String,
    forms: Vec<String>,
    note: String,
    first_use: Option<String>,
    /// L'hébreu que la note énonce au passage, quand le §3 n'en donne pas.
    hebrew: Option<String>,
}

/// Lit la liste des intraduisibles.
///
/// On n'extrait **que** les formes citées entre accents graves. Le reste de la
/// ligne est de la prose, qui peut elle-même contenir du gras d'emphase — le
/// confondre avec une forme balisée créerait de faux lemmes, et ces faux lemmes
/// deviendraient des mots dorés ouvrant des fiches vides.
fn read_tagged_terms(section: &Section) -> Vec<TaggedTerm> {
    let mut terms = Vec::new();

    for line in &section.lines {
        if !ITEM.is_match(line) {
            continue;
        }

        let forms: Vec<String> = TAGGED_FORM
            .captures_iter(line)
            .map(|m| m.get(1).unwrap().as_str().trim().to_string())
            .collect();
        if forms.is_empty() {
            continue;
        }

        // La prose restante, une fois les formes citées retirées.
        let sans_puce = ITEM.replace(line, "");
        let sans_formes = TAGGED_FORM.replace_all(&sans_puce, "");
        let note = TETE_DE_NOTE.replace(&sans_formes, "").trim().to_string();

        let first_use = FIRST_USE.captures(line).map(|m| {
            let livre = m.get(1).unwrap().as_str().trim();
            match m.get(2) {
                Some(renvoi) => format!("{livre} {}", renvoi.as_str()),
                None => livre.to_string(),
            }
        });

        // Le lemme vient de la **première** forme citée ; les formes dérivées
        // annoncées sur la même ligne y retombent (§2.5, règle de déduction).
        let title = forms[0].clone();
        terms.push(TaggedTerm {
            lemma: slugify(&title),
            title,
            hebrew: extract_hebrew(&note),
            forms,
            note,
            first_use,
        });
    }

    terms
}

// ─────────────────────────────────────────────────────────────────────────────
// §3 — les tables de terminologie fixée
// ─────────────────────────────────────────────────────────────────────────────

struct FixedTerm {
    lemma: String,
    title: String,
    hebrew: Option<String>,
    rendering: Option<String>,
    definition: String,
    section: String,
}

/// Lit les tables `| Terme hébreu | Translittération | Traduction ONT | … |`.
///
/// Une ligne peut porter plusieurs termes séparés par une barre oblique —
/// `*ishah* / *ish*`, `*goy* / *goyim*`. On les dédouble, en appariant les
/// hébreux correspondants **quand leur nombre concorde** ; sinon la cellule
/// entière vaut pour chacun, ce qui reste vrai.
fn read_fixed_terms(section: &Section) -> Vec<FixedTerm> {
    let mut terms = Vec::new();

    for cells in table_rows(&section.lines) {
        let (Some(hebrew_cell), Some(translit_cell)) = (cells.first(), cells.get(1)) else {
            continue;
        };
        // La ligne d'en-tête n'a pas d'hébreu dans sa première cellule : c'est
        // ce qui la distingue, sans avoir à compter les lignes.
        if !has_hebrew(hebrew_cell) {
            continue;
        }

        let split = |cell: &str| -> Vec<String> {
            cell.split('/')
                .map(cell_text)
                .filter(|s| !s.is_empty())
                .collect()
        };

        let translits = split(translit_cell);
        let hebrews = split(hebrew_cell);
        let renderings = cells.get(2).map(|c| split(c)).unwrap_or_default();
        let definition = cells
            .get(3)
            .map(|c| c.trim().to_string())
            .unwrap_or_default();

        let pick = |parts: &[String], index: usize| -> Option<String> {
            if parts.len() == translits.len() {
                parts.get(index).cloned()
            } else {
                parts.first().cloned()
            }
        };

        for (index, translit) in translits.iter().enumerate() {
            terms.push(FixedTerm {
                lemma: slugify(translit),
                title: translit.clone(),
                hebrew: pick(&hebrews, index),
                rendering: pick(&renderings, index),
                definition: definition.clone(),
                section: section.number.clone().unwrap_or_else(|| "3".into()),
            });
        }
    }

    terms
}

// ─────────────────────────────────────────────────────────────────────────────
// §2.6 — les répertoires de noms de livres
// ─────────────────────────────────────────────────────────────────────────────

/// Le nom d'un livre tel que le §2.6 le fixe.
#[derive(Debug, Clone)]
pub struct BookName {
    /// Le nom hébreu translittéré — le vrai titre du livre.
    pub translit: String,
    /// Le titre en écriture hébraïque.
    pub hebrew: String,
}

/// Associe à chaque identifiant de livre son nom canonique.
///
/// Les répertoires n'ont pas tous la même forme — trois ou quatre colonnes,
/// l'ordre varie. Plutôt que de coder chaque table, on repère dans chaque ligne
/// la cellule qui porte de l'hébreu et celle dont la translittération
/// correspond à un slot connu. La structure du vault fait donc foi, pas une
/// table écrite ici qui vieillirait.
fn read_book_names(section: &Section, known_ids: &HashSet<String>) -> HashMap<String, BookName> {
    let mut names = HashMap::new();

    for cells in table_rows(&section.lines) {
        let Some(hebrew_cell) = cells.iter().find(|c| has_hebrew(c)) else {
            continue;
        };

        for cell in &cells {
            if cell == hebrew_cell {
                continue;
            }
            let translit = cell_text(cell);
            let id = slugify(&translit);
            if !id.is_empty() && known_ids.contains(&id) && !names.contains_key(&id) {
                names.insert(
                    id,
                    BookName {
                        translit,
                        hebrew: cell_text(hebrew_cell),
                    },
                );
                break;
            }
        }
    }

    names
}

// ─────────────────────────────────────────────────────────────────────────────

pub struct Reference {
    /// Le glossaire, sans les décomptes — le build les remplit.
    pub glossary: Vec<GlossaryEntry>,
    /// Forme dérivée → lemme canonique.
    ///
    /// C'est la règle de déduction du §2.5 rendue exécutable : « toute forme
    /// dérivée d'un terme intraduisible est elle-même intraduisible ». Un
    /// `**anashim**` rencontré dans le texte doit ouvrir la fiche d'**ish**, un
    /// `**mishpatim**` celle de **mishpat**.
    ///
    /// Une forme qui possède sa propre entrée — **tov me'od** en a une,
    /// distincte de **tov** — n'y figure pas : elle reste son propre lemme.
    pub form_index: HashMap<String, String>,
    /// Identifiant de livre → nom canonique (§2.6).
    pub book_names: HashMap<String, BookName>,
}

/// Les fiches denses du vault — `lexique/<lemme>.md`, une par terme.
///
/// ## Ce que le fichier contient, et pourquoi seulement des paragraphes
///
/// Le titre `# Elohim` sert de repère à l'auteur dans Obsidian ; le pipeline
/// l'ignore. Tout le reste est de la prose, découpée en paragraphes sur les
/// lignes vides.
///
/// **Rien d'autre que des paragraphes.** `TermSheet.swift` ne rend que
/// `Block::Para` et laisse tomber le reste **sans rien dire** : un titre ou une
/// liste dans une fiche disparaîtrait chez le lecteur, en silence. C'est la
/// contrainte qui décide de la forme — et elle a une contrepartie : une fiche
/// faite de paragraphes traverse la mise à jour réseau du corpus, donc atteint
/// les apps **déjà installées**, sans compilation ni revue.
///
/// ## Ce qui n'est pas trouvé est dit
///
/// Une fiche dont le nom ne retombe sur aucune entrée serait écrite, committée,
/// publiée — et jamais lue par personne. Le pipeline la signale au lieu de la
/// laisser tomber.
pub fn read_fiches(racine: &Path) -> HashMap<String, Vec<Block>> {
    let mut fiches = HashMap::new();
    let dossier = racine.join(crate::config::LEXIQUE);
    let Ok(entrées) = std::fs::read_dir(&dossier) else {
        return fiches;
    };

    let mut noms: Vec<_> = entrées
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.extension().is_some_and(|x| x == "md"))
        .collect();
    noms.sort();

    for chemin in noms {
        let Ok(texte) = std::fs::read_to_string(&chemin) else {
            continue;
        };
        let lemme = chemin
            .file_stem()
            .map(|s| slugify(&s.to_string_lossy()))
            .unwrap_or_default();
        let blocs: Vec<Block> = texte
            .split("\n\n")
            .map(str::trim)
            .filter(|p| !p.is_empty() && !p.starts_with('#'))
            .map(|p| Block::Para {
                nodes: parse_inline(&p.replace('\n', " ")),
            })
            .collect();
        if !blocs.is_empty() {
            fiches.insert(lemme, blocs);
        }
    }
    fiches
}

/// Lit `CLAUDE.md` et en tire le glossaire et les noms de livres.
pub fn read_reference(texte: &str, known_book_ids: &HashSet<String>) -> Reference {
    let lignes: Vec<String> = texte
        .split('\n')
        .map(|l| l.trim_end_matches('\r').to_string())
        .collect();
    let sections = split_sections(&lignes);

    let tagged: Vec<TaggedTerm> = sections
        .iter()
        .filter(|s| s.number.as_deref() == Some("2.5"))
        .flat_map(read_tagged_terms)
        .collect();

    let fixed: Vec<FixedTerm> = sections
        .iter()
        .filter(|s| s.number.as_deref().is_some_and(|n| SECTION_3.is_match(n)))
        .flat_map(read_fixed_terms)
        .collect();

    let mut book_names = HashMap::new();
    for section in sections
        .iter()
        .filter(|s| s.number.as_deref() == Some("2.6"))
    {
        for (id, name) in read_book_names(section, known_book_ids) {
            book_names.entry(id).or_insert(name);
        }
    }

    // Les intraduisibles d'abord — ils sont la colonne vertébrale du lexique —
    // puis le vocabulaire fixé vient les enrichir ou s'ajouter.
    //
    // `BTreeMap` plutôt qu'une table de hachage suivie d'un tri : le glossaire
    // sort trié par lemme, et les lemmes sont en ASCII pur — l'ordre des
    // octets y coïncide avec l'ordre alphabétique.
    let mut entries: BTreeMap<String, GlossaryEntry> = BTreeMap::new();

    for term in &tagged {
        let mut formes = Vec::new();
        for f in &term.forms {
            if !formes.contains(f) {
                formes.push(f.clone());
            }
        }
        entries.insert(
            term.lemma.clone(),
            GlossaryEntry {
                lemma: term.lemma.clone(),
                title: term.title.clone(),
                tagged: true,
                forms: formes,
                hebrew: term.hebrew.clone(),
                rendering: None,
                definition: None,
                tagging_note: as_blocks(&term.note),
                first_use: term.first_use.clone(),
                source_section: Some("2.5".into()),
                count: 0,
                body_count: 0,
                gloss_count: 0,
            },
        );
    }

    for term in &fixed {
        if let Some(existante) = entries.get_mut(&term.lemma) {
            // `get_or_insert` : le §2.5 a la préséance, le §3 comble les trous.
            if existante.hebrew.is_none() {
                existante.hebrew = term.hebrew.clone();
            }
            if existante.rendering.is_none() {
                existante.rendering = term.rendering.clone();
            }
            if existante.definition.is_none() {
                existante.definition = as_blocks(&term.definition);
            }
            existante.source_section = Some(format!("2.5 + {}", term.section));
            continue;
        }
        entries.insert(
            term.lemma.clone(),
            GlossaryEntry {
                lemma: term.lemma.clone(),
                title: term.title.clone(),
                tagged: false,
                forms: vec![term.title.clone()],
                hebrew: term.hebrew.clone(),
                rendering: term.rendering.clone(),
                definition: as_blocks(&term.definition),
                tagging_note: None,
                first_use: None,
                source_section: Some(term.section.clone()),
                count: 0,
                body_count: 0,
                gloss_count: 0,
            },
        );
    }

    // Une forme citée au §2.5 est un intraduisible, **même si sa fiche vient
    // d'une table du §3** — c'est le cas de `tov me'od`, listé comme forme de
    // `tov` mais doté de sa propre définition.
    for term in &tagged {
        for form in &term.forms {
            if let Some(entree) = entries.get_mut(&slugify(form)) {
                entree.tagged = true;
            }
        }
    }

    // Les formes dérivées qui n'ont pas de fiche propre pointent vers leur
    // lemme.
    let mut form_index = HashMap::new();
    for term in &tagged {
        for form in &term.forms {
            let slug = slugify(form);
            if slug != term.lemma && !entries.contains_key(&slug) {
                form_index.insert(slug, term.lemma.clone());
            }
        }
    }

    Reference {
        glossary: entries.into_values().collect(),
        form_index,
        book_names,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn reference(texte: &str) -> Reference {
        read_reference(texte, &HashSet::new())
    }

    #[test]
    fn une_forme_citee_devient_un_intraduisible() {
        let r = reference("## 2.5 Les intraduisibles\n\n- `**chesed**` — la loyauté d'alliance\n");
        assert_eq!(r.glossary.len(), 1);
        assert_eq!(r.glossary[0].lemma, "chesed");
        assert!(r.glossary[0].tagged);
        assert!(r.glossary[0].tagging_note.is_some());
    }

    #[test]
    fn du_gras_de_prose_ne_cree_pas_de_lemme() {
        // Le piège : `**…**` sert aussi à insister dans le document de
        // référence. Sans les accents graves, ce ne sont pas des formes.
        let r =
            reference("## 2.5 Les intraduisibles\n\n- ceci est **important** mais pas un terme\n");
        assert!(r.glossary.is_empty());
    }

    #[test]
    fn les_formes_derivees_pointent_vers_leur_lemme() {
        // La règle de déduction du §2.5 rendue exécutable.
        let r = reference("## 2.5 Les intraduisibles\n\n- `**ish**` / `**anashim**` — l'Être\n");
        assert_eq!(r.form_index.get("anashim"), Some(&"ish".to_string()));
        assert!(
            !r.form_index.contains_key("ish"),
            "un lemme ne pointe pas vers lui-même"
        );
    }

    #[test]
    fn le_premier_emploi_se_lit() {
        let r = reference(
            "## 2.5 Les intraduisibles\n\n- `**emunah**` — premier emploi en *Bereshit* 15:6\n",
        );
        assert_eq!(r.glossary[0].first_use.as_deref(), Some("Bereshit 15:6"));
    }

    #[test]
    fn une_table_du_paragraphe_3_donne_hebreu_et_rendu() {
        let r = reference(
            "## 3.1 Terminologie\n\n\
             | Terme | Translittération | Traduction ONT | Champ |\n\
             |---|---|---|---|\n\
             | בָּרָא | *bara* | orchestrer | mettre en ordre |\n",
        );
        let e = &r.glossary[0];
        assert_eq!(e.lemma, "bara");
        assert_eq!(e.rendering.as_deref(), Some("orchestrer"));
        assert!(
            !e.tagged,
            "le vocabulaire fixé n'est pas balisé dans le texte"
        );
        assert!(e.definition.is_some());
    }

    #[test]
    fn l_en_tete_d_une_table_n_est_pas_un_terme() {
        // Elle se reconnaît à l'absence d'hébreu dans sa première cellule —
        // pas à sa position, qui varie.
        let r = reference(
            "## 3.1 Terminologie\n\n| Terme | Translittération |\n|---|---|\n| בָּרָא | *bara* |\n",
        );
        assert_eq!(r.glossary.len(), 1);
    }

    #[test]
    fn le_paragraphe_2_5_a_la_preseance_sur_le_3() {
        // Un terme balisé **et** défini garde son statut d'intraduisible, et
        // gagne la définition du §3.
        let r = reference(
            "## 2.5 Les intraduisibles\n\n- `**chesed**` — la loyauté\n\n\
             ## 3.1 Terminologie\n\n| T | Tr | ONT | Champ |\n|---|---|---|---|\n\
             | חֶסֶד | *chesed* | fidélité | la loyauté d'alliance |\n",
        );
        assert_eq!(r.glossary.len(), 1, "une seule fiche, pas deux");
        let e = &r.glossary[0];
        assert!(e.tagged);
        assert_eq!(e.rendering.as_deref(), Some("fidélité"));
        assert_eq!(e.source_section.as_deref(), Some("2.5 + 3.1"));
    }

    #[test]
    fn une_ligne_a_plusieurs_termes_se_dedouble() {
        let r = reference(
            "## 3.2 Terminologie\n\n| T | Tr | ONT | Champ |\n|---|---|---|---|\n\
             | עָרְלָה / עָרֵל | *orlah* / *arel* | a / b | c |\n",
        );
        let lemmes: Vec<_> = r.glossary.iter().map(|e| e.lemma.as_str()).collect();
        assert_eq!(lemmes, ["arel", "orlah"], "triés par lemme");
    }

    #[test]
    fn le_glossaire_sort_trie() {
        let r = reference("## 2.5 Les intraduisibles\n\n- `**zayin**` — z\n- `**aleph**` — a\n");
        let lemmes: Vec<_> = r.glossary.iter().map(|e| e.lemma.as_str()).collect();
        assert_eq!(lemmes, ["aleph", "zayin"]);
    }
}
