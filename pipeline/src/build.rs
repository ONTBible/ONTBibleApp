//! Le build — le vault devient des données consommables par une liseuse.
//!
//! ```text
//! dist/corpus.json        l'arborescence de navigation, les 70 slots
//! dist/books/<id>.json    le contenu complet d'un livre
//! dist/glossary.json      le lexique des intraduisibles
//! dist/shemot.json        les fiches des noms propres
//! dist/occurrences.json   lemme → toutes ses occurrences
//! dist/search.json        l'index de recherche
//! dist/daily.json         le vivier du verset du jour
//! dist/manifest.json      les empreintes et les chiffres
//! dist/report.md          l'état du corpus et les anomalies repérées
//! ```
//!
//! Rien ici n'est propre à une plateforme : la sortie est du JSON que Swift,
//! Kotlin et Rust lisent aussi bien. Le choix du socle de l'app ne change pas
//! une ligne de ce fichier.

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::fs;
use std::path::Path;

use serde::Serialize;

use crate::chapter::{parse_chapter, ChapterSource};
use crate::config::{display_name, glose, groupe, out, section, vault, REFERENCE, SKELETON, TREES};
use crate::controles;
use crate::inline::{collect_terms, plain_text, tidy, PlainOptions};
use crate::reference::{read_fiches, read_reference, BookName, Reference};
use crate::renvois;
use crate::schema::{
    Block, Book, BookOutline, BuildStats, Chapter, ChapterKind, Corpus, CorpusFile, CorpusOutline,
    DailyFile, DailyVerse, GlossaryEntry, GlossaryFile, Group, Inline, Manifest, Mode, ModeOutline,
    Occurrence, OccurrencesFile, SearchFile, SearchRecord, ShemEntry, ShemotFile, Status, Stub,
    TermLevel,
};
use crate::search::index_chapter;
use crate::vault::{read_tree, VaultBook};

#[derive(Debug, Clone)]
pub struct Issue {
    pub file: String,
    pub line: usize,
    pub message: String,
}

/// Une forme balisée dans le texte qu'aucune entrée du glossaire ne couvre.
#[derive(Debug, Clone)]
struct Unknown {
    count: u32,
    /// La forme exacte, casse comprise.
    form: String,
    /// Où on l'a vue la première fois — `bereshit-18:24`.
    where_: String,
    sample: String,
}

/// Cherche le lemme connu dont la forme inconnue pourrait dériver.
///
/// Purement **indicatif** : c'est une piste pour l'auteur, pas un verdict. Le
/// critère est le préfixe, ce qui attrape les pluriels et les construits —
/// `tsadiqim` → `tsadiq`, `shaliachim` → `shaliach` — sans prétendre
/// comprendre la morphologie hébraïque.
fn guess_lemma<'a>(form: &str, known: impl Iterator<Item = &'a str>) -> Option<String> {
    let mut best: Option<&str> = None;
    for lemma in known {
        if lemma.len() < 4 || !form.starts_with(lemma) || form == lemma {
            continue;
        }
        if best.is_none_or(|b| lemma.len() > b.len()) {
            best = Some(lemma);
        }
    }
    best.map(str::to_string)
}

/// Un fragment de texte d'une unité, avec son numéro de verset s'il en a un.
struct TextUnit<'a> {
    verse: Option<u32>,
    nodes: &'a [Inline],
}

/// Parcourt tous les fragments de texte d'une unité.
fn text_units(chapter: &Chapter) -> Vec<TextUnit<'_>> {
    fn walk<'a>(blocks: &'a [Block], into: &mut Vec<TextUnit<'a>>) {
        for block in blocks {
            match block {
                Block::Verses { verses } => {
                    for v in verses {
                        into.push(TextUnit {
                            verse: Some(v.n),
                            nodes: &v.nodes,
                        });
                    }
                }
                Block::Para { nodes } | Block::Heading { nodes, .. } | Block::Quote { nodes } => {
                    into.push(TextUnit { verse: None, nodes })
                }
                Block::List { items, .. } => {
                    for item in items {
                        into.push(TextUnit {
                            verse: None,
                            nodes: item,
                        });
                    }
                }
                Block::Table { headers, rows } => {
                    for cell in headers {
                        into.push(TextUnit {
                            verse: None,
                            nodes: cell,
                        });
                    }
                    for row in rows {
                        for cell in row {
                            into.push(TextUnit {
                                verse: None,
                                nodes: cell,
                            });
                        }
                    }
                }
                Block::Rule => {}
            }
        }
    }

    let mut out = Vec::new();
    walk(&chapter.blocks, &mut out);
    if let Some(footer) = &chapter.footer {
        walk(&footer.notes, &mut out);
    }
    out
}

/// Un extrait de contexte centré sur la forme rencontrée.
///
/// `from` permet de viser la Nᵉ occurrence : un même verset porte souvent
/// plusieurs fois le même terme — trois `chesed` en *Bereshit* 19:19 — et trois
/// extraits identiques ne renseigneraient sur rien.
///
/// Tout se compte en **caractères** et non en octets : une fenêtre de cent
/// cinquante octets couperait au milieu d'un mot hébreu, où chaque lettre en
/// pèse deux, et rendrait de l'UTF-8 invalide.
fn make_snippet(plain: &str, form: &str, width: usize, from: usize) -> String {
    let chars: Vec<char> = plain.chars().collect();
    let forme: Vec<char> = form.chars().collect();

    let at =
        (from..=chars.len().saturating_sub(forme.len())).find(|&i| chars[i..].starts_with(&forme));

    let Some(at) = at else {
        return chars
            .iter()
            .take(width)
            .collect::<String>()
            .trim()
            .to_string();
    };

    let half = width.saturating_sub(forme.len()) / 2;
    let start = at.saturating_sub(half);
    let end = (at + forme.len() + half).min(chars.len());

    let corps: String = chars[start..end].iter().collect();
    format!(
        "{}{}{}",
        if start > 0 { "…" } else { "" },
        corps.trim(),
        if end < chars.len() { "…" } else { "" }
    )
}

/// La position d'une sous-chaîne, en caractères.
fn index_of_chars(haystack: &[char], needle: &[char], from: usize) -> Option<usize> {
    if needle.is_empty() || needle.len() > haystack.len() {
        return None;
    }
    (from..=haystack.len() - needle.len()).find(|&i| haystack[i..].starts_with(needle))
}

struct ReadChapters {
    chapters: Vec<Chapter>,
    issues: Vec<Issue>,
    superseded: Vec<String>,
}

/// Lit toutes les unités des deux arborescences.
///
/// Les fichiers d'un même livre peuvent venir de `locked/` et de
/// `brouillons/` : la clé de fusion est l'identifiant d'unité, et **le
/// brouillon l'emporte** (§12 — « pour ceux-ci, lire `brouillons/…` »).
fn read_chapters(racine: &Path) -> ReadChapters {
    // L'ordre de parcours est **conservé** : les unités verrouillées d'abord,
    // puis les brouillons, chacune dans l'ordre alphabétique des fichiers que
    // `read_tree` garantit.
    //
    // Un `BTreeMap` trierait les deux arborescences ensemble, ce qui est plus
    // canonique — mais changerait l'ordre des occurrences affichées sous une
    // fiche de lexique. Le déterminisme, qui est le vrai enjeu, vient déjà du
    // tri des fichiers dans `read_tree`.
    let mut ordre: Vec<String> = Vec::new();
    let mut chapters: HashMap<String, Chapter> = HashMap::new();
    let mut issues = Vec::new();
    let mut superseded = Vec::new();

    for (etat, arbre) in TREES {
        let status = if etat == "locked" {
            Status::Locked
        } else {
            Status::Brouillon
        };

        for book in read_tree(&racine.join(arbre)) {
            for file in &book.files {
                let absolu = book.dir.join(file);
                let Ok(text) = fs::read_to_string(&absolu) else {
                    continue;
                };
                let relatif = absolu
                    .strip_prefix(racine)
                    .unwrap_or(&absolu)
                    .to_string_lossy()
                    .to_string();

                let parsed = parse_chapter(&ChapterSource {
                    path: relatif.clone(),
                    text,
                    book_id: book.id.clone(),
                    status,
                });
                let key = format!("{}/{}", book.id, parsed.chapter.id);

                if let Some(existante) = chapters.get(&key) {
                    if existante.status == Status::Brouillon {
                        continue;
                    }
                    superseded.push(existante.source.clone());
                }

                for issue in parsed.issues {
                    issues.push(Issue {
                        file: relatif.clone(),
                        line: issue.line,
                        message: issue.message,
                    });
                }
                if !chapters.contains_key(&key) {
                    ordre.push(key.clone());
                }
                chapters.insert(key, parsed.chapter);
            }
        }
    }

    ReadChapters {
        chapters: ordre
            .into_iter()
            .filter_map(|k| chapters.remove(&k))
            .collect(),
        issues,
        superseded,
    }
}

/// Assemble les livres du squelette et les unités rédigées.
fn assemble(
    skeleton: &[VaultBook],
    chapters: &[Chapter],
    names: &HashMap<String, BookName>,
) -> Vec<Corpus> {
    let mut by_book: HashMap<&str, Vec<&Chapter>> = HashMap::new();
    for chapter in chapters {
        by_book.entry(&chapter.book_id).or_default().push(chapter);
    }

    let mut ordre_corpus: Vec<String> = Vec::new();
    let mut corpora: HashMap<String, Corpus> = HashMap::new();

    let mut slots: Vec<&VaultBook> = skeleton.iter().collect();
    slots.sort_by_key(|b| b.slot);

    for entry in slots {
        let mut units: Vec<Chapter> = by_book
            .get(entry.id.as_str())
            .map(|v| v.iter().map(|c| (*c).clone()).collect())
            .unwrap_or_default();
        units.sort_by_key(|u| u.n);

        let intro = units.iter().find(|u| u.kind == ChapterKind::Intro).cloned();
        let body: Vec<Chapter> = units
            .iter()
            .filter(|u| u.kind == ChapterKind::Chapter)
            .cloned()
            .collect();

        // Le nom canonique vient du §2.6 ; à défaut, du titre et du sous-titre
        // qu'un chapitre porte déjà.
        let declared = names.get(&entry.id);
        let from_title = body.first().map(|c| {
            c.title
                .trim_end_matches(|c: char| c.is_ascii_digit() || c.is_whitespace())
                .trim()
                .to_string()
        });
        let from_subtitle = body
            .first()
            .and_then(|c| c.subtitle.clone())
            .or_else(|| intro.as_ref().and_then(|i| i.subtitle.clone()));

        let book = Book {
            id: entry.id.clone(),
            slot: entry.slot,
            title: declared.map(|d| d.translit.clone()).unwrap_or_else(|| {
                from_title
                    .filter(|t| !t.is_empty())
                    .unwrap_or_else(|| display_name(&entry.id))
            }),
            french: from_subtitle
                .as_ref()
                .map(|s| s.french.clone())
                .unwrap_or_else(|| entry.french.clone()),
            glose: glose(&entry.id).map(str::to_string),
            hebrew: declared
                .map(|d| d.hebrew.clone())
                .or_else(|| from_subtitle.as_ref().map(|s| s.hebrew.clone())),
            corpus_id: entry.corpus.id.clone(),
            mode_id: entry.mode.id.clone(),
            group_id: entry.groups.last().map(|g| g.id.clone()),
            empty: units.is_empty(),
            chapters: body,
            intro,
        };

        let corpus = corpora.entry(entry.corpus.id.clone()).or_insert_with(|| {
            ordre_corpus.push(entry.corpus.id.clone());
            let (fr, gl) = section(&entry.corpus.id).unwrap_or(("", None));
            Corpus {
                id: entry.corpus.id.clone(),
                title: display_name(&entry.corpus.id),
                french: (!fr.is_empty()).then(|| fr.to_string()),
                glose: gl.map(str::to_string),
                order: entry.corpus.order,
                modes: Vec::new(),
            }
        });

        if !corpus.modes.iter().any(|m| m.id == entry.mode.id) {
            let (fr, gl) = section(&entry.mode.id).unwrap_or(("", None));
            corpus.modes.push(Mode {
                id: entry.mode.id.clone(),
                title: display_name(&entry.mode.id),
                french: (!fr.is_empty()).then(|| fr.to_string()),
                glose: gl.map(str::to_string),
                order: entry.mode.order,
                // Remplis après coup, quand tous les livres du mode sont
                // connus : l'ordre des conteneurs est celui de leurs livres,
                // et on ne le devine pas depuis le premier venu.
                groups: Vec::new(),
                books: Vec::new(),
            });
        }
        corpus
            .modes
            .iter_mut()
            .find(|m| m.id == entry.mode.id)
            .unwrap()
            .books
            .push(book);
    }

    let mut result: Vec<Corpus> = ordre_corpus
        .into_iter()
        .filter_map(|id| corpora.remove(&id))
        .collect();
    result.sort_by_key(|c| c.order);
    for corpus in &mut result {
        corpus.modes.sort_by_key(|m| m.order);
        for mode in &mut corpus.modes {
            mode.groups = groupes_du_mode(&mode.books);
        }
    }
    result
}

/// Les conteneurs d'un mode, dans l'ordre où leurs livres paraissent.
///
/// L'ordre vient des **livres**, jamais d'une liste écrite à côté : c'est le
/// corpus qui décide où tombe une coupure, et une liste recopiée finirait par
/// diverger de lui sans que rien ne le dise.
///
/// Un conteneur rencontré mais non déclaré dans `GROUPES` est **ignoré en
/// silence**, à dessein : le regroupement est un ornement de lecture, et une
/// table des matières qui refuse de se rendre pour un identifiant inconnu
/// coûterait plus au lecteur que le groupe ne lui apporte.
fn groupes_du_mode(books: &[Book]) -> Vec<Group> {
    let mut vus: Vec<&str> = Vec::new();
    for id in books.iter().filter_map(|b| b.group_id.as_deref()) {
        if !vus.contains(&id) {
            vus.push(id);
        }
    }
    vus.into_iter()
        .filter_map(|id| {
            let (french, glose, rupture) = groupe(id)?;
            Some(Group {
                id: id.to_string(),
                title: display_name(id),
                french: french.to_string(),
                glose: glose.map(str::to_string),
                rupture: rupture.map(str::to_string),
            })
        })
        .collect()
}

struct Indexed {
    occurrences: BTreeMap<String, Vec<Occurrence>>,
    unknown: BTreeMap<String, Unknown>,
}

/// Construit l'index inversé des intraduisibles.
///
/// C'est ce qui rend possible le geste à la Bible Strong : toucher `chesed`
/// ouvre sa fiche **et** la liste de tous les passages où il paraît.
fn index_occurrences(
    chapters: &[Chapter],
    glossary: &mut [GlossaryEntry],
    form_index: &HashMap<String, String>,
) -> Indexed {
    let known: HashSet<String> = glossary.iter().map(|e| e.lemma.clone()).collect();
    let mut occurrences: BTreeMap<String, Vec<Occurrence>> = BTreeMap::new();
    let mut unknown: BTreeMap<String, Unknown> = BTreeMap::new();

    for chapter in chapters {
        for unit in text_units(chapter) {
            let mut terms = Vec::new();
            collect_terms(unit.nodes, TermLevel::Body, &mut terms);
            if terms.is_empty() {
                continue;
            }

            // Deux textes de référence : le corps seul, et le corps avec ses
            // gloses. Chaque forme est cherchée dans **celui de son niveau**,
            // sinon l'extrait ne la contiendrait pas.
            let corps = tidy(&plain_text(unit.nodes, PlainOptions::default()));
            let avec_gloses = tidy(&plain_text(
                unit.nodes,
                PlainOptions {
                    gloss: true,
                    ..Default::default()
                },
            ));
            let corps_chars: Vec<char> = corps.chars().collect();
            let gloses_chars: Vec<char> = avec_gloses.chars().collect();

            let mut cursors: HashMap<String, usize> = HashMap::new();

            for term in terms {
                // La règle de déduction du §2.5 : une forme dérivée ouvre la
                // fiche de son lemme.
                let lemma = if known.contains(&term.lemma) {
                    Some(term.lemma.clone())
                } else {
                    form_index.get(&term.lemma).cloned()
                };

                let (plain, plain_chars) = match term.level {
                    TermLevel::Body => (&corps, &corps_chars),
                    TermLevel::Gloss => (&avec_gloses, &gloses_chars),
                };

                let cle = format!("{:?} {}", term.level, term.v);
                let from = *cursors.get(&cle).unwrap_or(&0);
                let forme: Vec<char> = term.v.chars().collect();
                let at = index_of_chars(plain_chars, &forme, from);
                cursors.insert(
                    cle,
                    match at {
                        Some(i) => i + forme.len(),
                        None => from,
                    },
                );

                let Some(lemma) = lemma else {
                    unknown
                        .entry(term.lemma.clone())
                        .and_modify(|u| u.count += 1)
                        .or_insert_with(|| Unknown {
                            count: 1,
                            form: term.v.clone(),
                            where_: match unit.verse {
                                Some(v) => format!("{}:{}", chapter.id, v),
                                None => chapter.id.clone(),
                            },
                            sample: make_snippet(plain, &term.v, 110, from),
                        });
                    continue;
                };

                occurrences.entry(lemma).or_default().push(Occurrence {
                    book_id: chapter.book_id.clone(),
                    chapter_id: chapter.id.clone(),
                    verse: unit.verse,
                    form: term.v.clone(),
                    level: term.level,
                    snippet: make_snippet(plain, &term.v, 150, from),
                });
            }
        }
    }

    for entry in glossary.iter_mut() {
        let vide = Vec::new();
        let list = occurrences.get(&entry.lemma).unwrap_or(&vide);
        entry.count = list.len() as u32;
        entry.body_count = list.iter().filter(|o| o.level == TermLevel::Body).count() as u32;
        entry.gloss_count = entry.count - entry.body_count;
    }

    Indexed {
        occurrences,
        unknown,
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Les formes de sortie
// ─────────────────────────────────────────────────────────────────────────────

// Les formes de sortie vivent dans `schema` — voir « Les fichiers publiés ».
// Elles étaient privées ici, ce qui obligeait chaque liseuse à les redeviner à
// la lecture : c'est précisément la divergence que `schema` existe pour
// empêcher. Il ne reste ici que les fabriques, qui allègent un `Book` en
// `BookOutline`.

fn stub(chapter: &Chapter) -> Stub {
    Stub {
        id: chapter.id.clone(),
        n: chapter.n,
        title: chapter.title.clone(),
        status: chapter.status,
        verse_count: chapter.verse_count,
        reference: chapter.subtitle.as_ref().and_then(|s| s.reference.clone()),
    }
}

fn outline(book: &Book) -> BookOutline {
    BookOutline {
        id: book.id.clone(),
        slot: book.slot,
        title: book.title.clone(),
        french: book.french.clone(),
        glose: book.glose.clone(),
        hebrew: book.hebrew.clone(),
        group_id: book.group_id.clone(),
        empty: book.empty,
        intro: book.intro.as_ref().map(stub),
        chapters: book.chapters.iter().map(stub).collect(),
    }
}

fn write_json<T: Serialize>(file: &Path, data: &T) -> std::io::Result<usize> {
    // Compact par défaut : ces fichiers sont embarqués dans un binaire d'app,
    // pas lus par un humain. `search.json` seul gagne 40 % à ne pas être
    // indenté.
    //
    // `ONT_PRETTY=1` les rend lisibles, pour l'inspection à la main — c'est la
    // seule façon de regarder un arbre d'inline sans passer par `jq`. La
    // sortie indentée ne doit jamais être livrée : elle change les empreintes
    // du manifeste, donc ferait retélécharger tout le corpus.
    let body = if std::env::var("ONT_PRETTY").is_ok_and(|v| v != "0" && !v.is_empty()) {
        serde_json::to_string_pretty(data).expect("sérialisation")
    } else {
        serde_json::to_string(data).expect("sérialisation")
    };
    if let Some(parent) = file.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(file, &body)?;
    Ok(body.len())
}

// ─────────────────────────────────────────────────────────────────────────────

pub struct BuildResult {
    pub stats: BuildStats,
    pub search_records: usize,
    pub issues: usize,
    pub bytes: usize,
    /// Les `**…**` d'une fiche qui ne mènent à aucune entrée.
    ///
    /// Compté à part des `unknown_terms`, qui ne relèvent que le corps du
    /// texte : une fiche ne passe pas par l'indexation des chapitres, et sa
    /// faute restait donc muette.
    pub ors_morts: usize,
    /// Les `[[…]]` du corpus qui ne mènent à aucune fiche.
    ///
    /// Ce ne sont **pas des erreurs** : le §2.10 veut qu'une fiche dise ce qui
    /// reste à venir, et le vault porte des renvois vers des porteurs pas encore
    /// écrits. C'est la liste de ce qui manque, et c'est pour ça qu'on ne
    /// dégrade pas le Shem en texte nu — dégrader ferait disparaître la liste.
    pub shemot_sans_fiche: usize,
    /// Les intraduisibles **déclarés au §2.5 et jamais définis au §3**.
    ///
    /// Le trou que ce compteur bouche : `neshamah`, `emunah`, `tsadiq`,
    /// `tsedaqah` et `mabbul` étaient balisés dans tout le corpus, affichés en
    /// or et touchables, et le §3 ne disait rien d'eux. Trois gardes les ont
    /// laissés passer — celle du site, et les deux d'ici.
    ///
    /// Aucune ne se trompait. Toutes vérifiaient que le mot **mène** quelque
    /// part, jamais que ce quelque part **dise** quelque chose. C'est plus
    /// facile à écrire, et c'est ce qui reste faux.
    pub sans_definition: usize,
    /// Le nombre d'**occurrences** de liens livrés qui n'ouvrent rien.
    pub liens_morts: usize,
    /// Le nombre de **lemmes distincts** concernés — ce qu'il y a à corriger.
    pub liens_morts_lemmes: usize,
    /// Les unités dont la densité d'apparat tombe sous la moitié de la
    /// référence du §4.1.
    pub sous_glosees: usize,
    /// Combien de chapitres la mesure a couverts — le dénominateur du chiffre
    /// précédent, sans lequel il ne veut rien dire.
    pub chapitres_mesures: usize,
    /// La moins glosée, et sa valeur.
    ///
    /// **Un compteur seul devient un décor.** « 24 unités sous le seuil » ne
    /// change pas d'un build à l'autre et cesse d'être lu ; le nom de la
    /// dernière, lui, bouge dès qu'on travaille — et c'est celle par laquelle
    /// on commencerait.
    pub moins_glosee: Option<(String, f64)>,
}

/// Construit le corpus. Rend les chiffres, ou l'erreur qui a tout arrêté.
pub fn build() -> Result<BuildResult, String> {
    let racine = vault();
    let sortie = out();

    let skeleton = read_tree(&racine.join(SKELETON));
    if skeleton.is_empty() {
        return Err(format!(
            "Aucun slot trouvé sous {}. Vérifier ONT_VAULT.",
            racine.join(SKELETON).display()
        ));
    }

    let ids: HashSet<String> = skeleton.iter().map(|b| b.id.clone()).collect();
    let texte_reference = fs::read_to_string(racine.join(REFERENCE))
        .map_err(|e| format!("lecture de {REFERENCE} : {e}"))?;
    let Reference {
        mut glossary,
        form_index,
        book_names,
    } = read_reference(&texte_reference, &ids);

    // Les fiches denses recouvrent la définition tirée de `CLAUDE.md`. Elles ne
    // remplacent que ce champ : l'hébreu, les formes, le rendu et la règle de
    // balisage restent au document de référence, qui en est la source.
    let fiches = read_fiches(&racine);
    // `fiches_orphelines` se calcule plus bas, une fois les Shemot connus : le
    // dossier `lexique/` porte deux espèces de fiches depuis la troisième
    // couche, et il fallait les deux pour savoir laquelle est orpheline.
    for entry in glossary.iter_mut() {
        if let Some(fiche) = fiches.get(&entry.lemma) {
            let blocs = &fiche.blocs;
            entry.definition = Some(blocs.clone());
        }
    }

    // Un mot d'or qui ne mène nulle part, dans une fiche.
    //
    // Le §2.5 réserve `**…**` aux intraduisibles : le mot sort en or et promet
    // une entrée de lexique. Employé pour insister — « le poids **réel** » —,
    // il promet une fiche qui n'existe pas, et c'est le défaut même que le
    // §2.5 bis a été écrit pour supprimer.
    //
    // Le rapport le relève déjà pour le **corps du texte**. Les fiches y
    // échappaient : elles n'entrent pas dans `index_occurrences`, qui ne
    // parcourt que les chapitres. Trois lots de fiches ont donc été écrits avec
    // la faute, et rien ne l'a dit — c'est la vigilance qui rattrapait, ce qui
    // ne tient pas à cent fiches.
    let connus: HashSet<String> = glossary
        .iter()
        .flat_map(|e| {
            std::iter::once(e.lemma.clone())
                .chain(e.forms.iter().map(|f| crate::inline::slugify(f)))
        })
        .collect();
    let mut ors_morts: Vec<String> = Vec::new();
    for entry in &glossary {
        // **D'où vient la définition**, et non « d'où on la croit venue ». Une
        // entrée sans fiche tire sa définition du `CLAUDE.md` : annoncer
        // `lexique/merkavah.md` enverrait corriger un fichier qui n'existe pas.
        let source = if fiches.contains_key(&entry.lemma) {
            format!("lexique/{}.md", entry.lemma)
        } else {
            format!("CLAUDE.md — entrée {}", entry.title)
        };
        for bloc in entry.definition.iter().flatten() {
            let Block::Para { nodes } = bloc else {
                continue;
            };
            collect_or_morts(nodes, &connus, &source, &mut ors_morts);
        }
    }
    ors_morts.sort();
    ors_morts.dedup();

    // **Déclaré n'est pas défini.** `tagged` dit que le terme est balisé (§2.5),
    // `definition` qu'il a un champ sémantique (§3). Un terme peut avoir l'un
    // sans l'autre : il paraît alors en or, il est touchable, et sa fiche
    // n'apprend rien.
    let sans_definition: Vec<String> = glossary
        .iter()
        .filter(|e| e.tagged && e.definition.is_none())
        .map(|e| e.title.clone())
        .collect();

    let lu = read_chapters(&racine);
    let mut corpora = assemble(&skeleton, &lu.chapters, &book_names);

    // **Les renvois se lient après l'assemblage, et il n'y a pas le choix.**
    //
    // Résoudre « Bereshit 9:5 » demande de savoir quelle unité couvre 9:1-17,
    // donc de connaître **toutes** les plages du corpus. On ne peut pas le
    // faire en lisant un chapitre : à ce moment-là, on ignore encore ce que
    // contiennent les autres.
    {
        let index = renvois::Index::nouveau(&corpora);
        for corpus in &mut corpora {
            for mode in &mut corpus.modes {
                for livre in &mut mode.books {
                    // `intro` **et** `chapters` : un livre peut n'être qu'une
                    // intro — `chazon-avraham` n'a aucun chapitre —, et un
                    // renvoi écrit là n'était lié nulle part.
                    for unite in unites_mut(livre) {
                        let origine = unite.id.clone();
                        renvois::lier(&mut unite.blocks, &index, &origine);
                    }
                }
            }
        }
    }
    let corpora = corpora;

    // **Les Shemot sans fiche**, relevés sur le corpus assemblé — donc sur ce
    // que le lecteur verra, et non sur ce que le vault contient. Un renvoi dans
    // une unité non publiée ne doit pas figurer dans la liste de travail.
    let noms_de_fiches: HashSet<String> = fiches.keys().cloned().collect();
    let mut shemot_sans_fiche: Vec<String> = Vec::new();
    for corpus in &corpora {
        for mode in &corpus.modes {
            for livre in &mode.books {
                for unite in unites(livre) {
                    for bloc in &unite.blocks {
                        match bloc {
                            Block::Para { nodes } | Block::Heading { nodes, .. } => {
                                collect_shemot_sans_fiche(
                                    nodes,
                                    &noms_de_fiches,
                                    &mut shemot_sans_fiche,
                                )
                            }
                            Block::Verses { verses } => {
                                for v in verses {
                                    collect_shemot_sans_fiche(
                                        &v.nodes,
                                        &noms_de_fiches,
                                        &mut shemot_sans_fiche,
                                    )
                                }
                            }
                            _ => {}
                        }
                    }
                }
            }
        }
    }
    shemot_sans_fiche.sort();
    shemot_sans_fiche.dedup();

    // **L'intro compte autant qu'un chapitre.** Trois parcours l'oubliaient —
    // celui-ci, celui des Shemot sans fiche, et le lieur de renvois — alors que
    // le rendu, lui, y arrivait. Deux chemins sur la même donnée, l'un complet
    // et l'autre non : le lecteur voyait un nom en terre brûlée, le touchait,
    // et la feuille ne trouvait rien.
    //
    // `Yaho'el` était le seul lemme du corpus à n'exister que dans une intro,
    // rendu huit fois et indexé zéro. `chazon-avraham` n'a **aucun chapitre** :
    // tout son contenu est une intro, et ses six autres Shemot n'étaient
    // sauvés que par leurs occurrences ailleurs. Relevé par la session du
    // vault, en comparant les lemmes rendus dans `dist/books` à l'index.
    //
    // **On ne publie que les porteurs que le corpus nomme.** Le vault tient 305
    // fiches, le corpus publié en emploie 205 : embarquer les cent autres
    // ferait payer au lecteur des noms qu'aucune unité écrite ne prononce.
    // Elles arriveront avec leurs unités.
    let mut shemot_employes: Vec<String> = Vec::new();
    for corpus in &corpora {
        for mode in &corpus.modes {
            for livre in &mode.books {
                for unite in unites(livre) {
                    for bloc in &unite.blocks {
                        match bloc {
                            Block::Para { nodes } | Block::Heading { nodes, .. } => {
                                collect_shem_lemmes(nodes, &mut shemot_employes)
                            }
                            Block::Verses { verses } => {
                                for v in verses {
                                    collect_shem_lemmes(&v.nodes, &mut shemot_employes)
                                }
                            }
                            _ => {}
                        }
                    }
                }
            }
        }
    }
    shemot_employes.sort();
    shemot_employes.dedup();

    // **Une fiche orpheline, maintenant qu'il y a deux espèces de fiches.**
    //
    // Le contrôle demandait « ce nom de fichier est-il un lemme du
    // glossaire ? ». C'était la bonne question tant que `lexique/` ne contenait
    // que des intraduisibles. Depuis la troisième couche il y tient aussi les
    // fiches de Shemot, **qui n'ont pas d'entrée de glossaire par
    // construction** — un porteur n'est pas un concept, et c'est toute la
    // raison d'être de la couche.
    //
    // La section listait donc les cent quatre-vingt-dix-sept fiches de noms
    // propres, toutes fausses. À ce taux elle n'est pas seulement inutile :
    // elle **noie le signal qu'elle portait**, puisqu'une vraie fiche
    // d'intraduisible orpheline y serait devenue invisible. Une garde qui crie
    // toujours ne garde plus rien.
    //
    // Un critère par espèce, donc : un lemme du glossaire, ou un Shem que le
    // corpus nomme. Ce qui n'est ni l'un ni l'autre est bien du travail perdu
    // — y compris une fiche de Shem écrite pour un nom qu'aucune unité publiée
    // ne prononce, qui est le même défaut sous l'autre espèce.
    let lemmes: HashSet<&str> = glossary.iter().map(|e| e.lemma.as_str()).collect();
    let porteurs: HashSet<&str> = shemot_employes.iter().map(String::as_str).collect();
    let mut fiches_orphelines: Vec<String> = fiches
        .keys()
        .filter(|l| !lemmes.contains(l.as_str()) && !porteurs.contains(l.as_str()))
        .cloned()
        .collect();
    fiches_orphelines.sort();

    let shemot: Vec<ShemEntry> = shemot_employes
        .iter()
        .filter_map(|lemme| {
            fiches.get(lemme).map(|fiche| ShemEntry {
                lemma: lemme.clone(),
                title: fiche.titre.clone(),
                definition: fiche.blocs.clone(),
            })
        })
        .collect();

    let indexed = index_occurrences(&lu.chapters, &mut glossary, &form_index);

    let books: Vec<&Book> = corpora
        .iter()
        .flat_map(|c| c.modes.iter().flat_map(|m| m.books.iter()))
        .collect();
    let written: Vec<&&Book> = books.iter().filter(|b| !b.empty).collect();

    let _ = fs::remove_dir_all(&sortie);
    let mut bytes = 0usize;

    // Chaque fichier est écrit depuis sa forme de `schema`, et non depuis un
    // `json!` monté à la main. La différence n'est pas cosmétique : une clé
    // mal orthographiée dans un `json!` passe la compilation et ne se voit
    // qu'à la lecture, chez la liseuse, sous la forme d'un champ manquant.
    bytes += write_json(
        &sortie.join("corpus.json"),
        &CorpusFile {
            schema: 1,
            corpora: corpora
                .iter()
                .map(|c| CorpusOutline {
                    id: c.id.clone(),
                    title: c.title.clone(),
                    french: c.french.clone(),
                    glose: c.glose.clone(),
                    order: c.order,
                    modes: c
                        .modes
                        .iter()
                        .map(|m| ModeOutline {
                            id: m.id.clone(),
                            title: m.title.clone(),
                            french: m.french.clone(),
                            glose: m.glose.clone(),
                            order: m.order,
                            groups: m.groups.clone(),
                            books: m.books.iter().map(outline).collect(),
                        })
                        .collect(),
                })
                .collect(),
        },
    )
    .map_err(|e| e.to_string())?;

    for book in &written {
        bytes += write_json(
            &sortie.join("books").join(format!("{}.json", book.id)),
            *book,
        )
        .map_err(|e| e.to_string())?;
    }

    bytes += write_json(
        &sortie.join("shemot.json"),
        &ShemotFile {
            schema: 1,
            entries: shemot.clone(),
        },
    )
    .map_err(|e| e.to_string())?;

    bytes += write_json(
        &sortie.join("glossary.json"),
        &GlossaryFile {
            schema: 1,
            entries: glossary.clone(),
        },
    )
    .map_err(|e| e.to_string())?;

    bytes += write_json(
        &sortie.join("occurrences.json"),
        &OccurrencesFile {
            schema: 1,
            by_lemma: indexed.occurrences.clone(),
        },
    )
    .map_err(|e| e.to_string())?;

    // L'index de recherche : un enregistrement par verset, titre ou paragraphe.
    let mut search_records: Vec<SearchRecord> = Vec::new();
    for book in &written {
        for unit in unites(book) {
            search_records.extend(index_chapter(unit));
        }
    }
    bytes += write_json(
        &sortie.join("search.json"),
        &SearchFile {
            schema: 1,
            records: search_records.clone(),
        },
    )
    .map_err(|e| e.to_string())?;

    // ── Le vivier du verset du jour ──────────────────────────────────────
    //
    // Un fichier à part, et pas l'index de recherche : celui-ci range un texte
    // **replié** — minuscules, accents retirés — parfait pour chercher,
    // illisible pour afficher.
    //
    // Il est petit et plat pour une raison précise : un widget iOS dispose
    // d'une trentaine de mégaoctets et doit se dessiner en quelques dizaines de
    // millisecondes. Y charger `books/bereshit.json` et ses 750 Ko d'arbre
    // d'inline le ferait tomber.
    let mut daily: Vec<DailyVerse> = Vec::new();
    for book in &written {
        for unit in unites(book) {
            // Seules les unités **verrouillées** : un brouillon ne fait pas
            // référence (§12) et n'a rien à faire sur un écran d'accueil. La
            // règle vit ici, dans la fabrique du vivier, et pas dans chacun des
            // trois endroits qui l'affichent — sinon elle finit appliquée à
            // deux endroits sur trois.
            if unit.status != Status::Locked {
                continue;
            }
            for block in &unit.blocks {
                let Block::Verses { verses } = block else {
                    continue;
                };
                for verse in verses {
                    // Le corps seul, sans l'appareil : un verset du jour se lit
                    // d'une traite, et les gloses font parfois quarante mots.
                    let text = tidy(&plain_text(&verse.nodes, PlainOptions::default()));
                    // Une fenêtre de longueur, et rien de plus savant. Trop
                    // court, le verset est une amorce sans sens propre ; trop
                    // long, il déborde du widget et arrive tronqué dans une
                    // notification.
                    //
                    // Comptée en **caractères** : en octets, un verset riche en
                    // hébreu serait écarté à tort, chaque lettre en pesant deux.
                    let longueur = text.chars().count();
                    if !(110..=300).contains(&longueur) {
                        continue;
                    }
                    daily.push(DailyVerse {
                        b: book.id.clone(),
                        c: unit.id.clone(),
                        n: verse.n,
                        r: format!("{}:{}", unit.title, verse.n),
                        t: text,
                    });
                }
            }
        }
    }
    bytes += write_json(
        &sortie.join("daily.json"),
        &DailyFile {
            schema: 1,
            verses: daily,
        },
    )
    .map_err(|e| e.to_string())?;

    let stats = BuildStats {
        books: books.len() as u32,
        books_written: written.len() as u32,
        chapters: written.iter().map(|b| b.chapters.len() as u32).sum(),
        intros: written.iter().filter(|b| b.intro.is_some()).count() as u32,
        verses: written
            .iter()
            .map(|b| b.chapters.iter().map(|c| c.verse_count).sum::<u32>())
            .sum(),
        glossary_entries: glossary.len() as u32,
        occurrences: indexed.occurrences.values().map(Vec::len).sum::<usize>() as u32,
        unknown_terms: indexed.unknown.keys().cloned().collect(),
        unused_entries: glossary
            .iter()
            .filter(|e| e.tagged && e.count == 0)
            .map(|e| e.lemma.clone())
            .collect(),
    };

    bytes += write_json(
        &sortie.join("manifest.json"),
        &Manifest {
            schema: 1,
            // L'estampille du **contenu**, pas de la compilation — la date du
            // dernier commit du vault, passée par `ONT_GENERE`.
            //
            // Le déterminisme est intact : deux exécutions sur le même vault
            // rendent la même date, donc le même octet, donc aucun
            // retéléchargement inutile. Un horodatage de build l'aurait rompu.
            //
            // Elle n'a servi à rien jusqu'au jour où un bundle est devenu plus
            // récent que le corpus publié. Une empreinte dit que deux corpus
            // diffèrent ; elle ne dit jamais lequel vient après.
            generated_at: crate::config::genere(),
            // **Le nom du vault, pas son chemin.**
            //
            // Le chemin absolu de la machine qui bâtit se retrouvait dans un
            // fichier committé : il basculait d'un contributeur à l'autre —
            // `ONTBibleApp/` chez l'un, `ONTBibleApp-android/` chez l'autre —
            // et faisait diverger la sortie de deux builds du même vault, ce qui
            // contredit le déterminisme que tout le reste tient. Il révélait
            // aussi l'arborescence du disque de qui publie.
            //
            // Personne ne le lit — ni les liseuses, ni le site. Il sert à dire
            // **de quel vault** un corpus vient, et le nom du dossier suffit.
            vault: racine
                .file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_default(),
            stats: stats.clone(),
        },
    )
    .map_err(|e| e.to_string())?;

    // **Les deux contrôles se calculent sur ce qui vient d'être écrit.**
    //
    // Pas sur le vault, pas sur une structure intermédiaire : sur les mêmes
    // valeurs que `write_json` a sérialisées quelques lignes plus haut. C'est
    // toute leur raison d'être — le rapport rendait `0` en normalisant
    // autrement que le fichier livré.
    let unites_publiees: Vec<&Chapter> = written.iter().flat_map(|b| unites(b)).collect();
    let liens_morts = controles::liens_morts(&unites_publiees, &glossary, &shemot);
    let hors_de_portee = controles::hors_de_portee(&unites_publiees);
    let formes_partagees = controles::formes_a_deux_proprietaires(&glossary);
    // **Les introductions sont hors de ce contrôle, et par construction.**
    //
    // Le §2.7 leur donne exactement la fonction inverse : elles portent le
    // cadre *une fois, en amont*, « afin que le corps garde la voix vécue et
    // que les gloses restent légères ». Une feuille d'introduction sans glose
    // fait donc son travail. La signaler, c'est reprocher à une chose d'être
    // ce qu'elle doit être — et six intros signalées d'office suffiraient à
    // faire de cette section un bruit qu'on cesse de lire.
    let mut densites: Vec<controles::Densite> = written
        .iter()
        .flat_map(|b| b.chapters.iter())
        .map(controles::densite)
        .collect();
    densites.sort_by(|a, b| {
        a.pour_mille()
            .partial_cmp(&b.pour_mille())
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    // **Le cliquet, posé après l'écriture du rapport et avant de rendre.**
    //
    // Après, pour que `dist/report.md` existe quand l'échec survient : sans
    // lui, celui qui reçoit l'échec n'a que le nombre et doit refaire à la main
    // le relevé que le pipeline vient de faire.
    let rapport = format_report(
        &corpora,
        &glossary,
        &Anomalies {
            issues: &lu.issues,
            unknown: &indexed.unknown,
            superseded: &lu.superseded,
            fiches_orphelines: &fiches_orphelines,
            ors_morts: &ors_morts,
            shemot_sans_fiche: &shemot_sans_fiche,
            liens_morts: &liens_morts,
            densites: &densites,
            hors_de_portee,
            formes_partagees: &formes_partagees,
        },
        &racine,
    );
    fs::write(sortie.join("report.md"), rapport).map_err(|e| e.to_string())?;

    let occurrences_mortes: usize = liens_morts.iter().map(|l| l.occurrences).sum();
    if occurrences_mortes > controles::PLAFOND_LIENS_MORTS {
        return Err(format!(
            "{occurrences_mortes} liens livrés n'ouvrent rien, le plafond est à {}.\n\
             \n\
             Le compte a monté : une balise neuve pointe sur un lemme qui n'existe\n\
             pas dans l'index livré. `dist/report.md` vient d'être écrit et nomme\n\
             lesquels, section « Liens livrés qui n'ouvrent rien ».\n\
             \n\
             Deux issues, et une seule est bonne selon le cas :\n\
             — si la forme est déclarée au §2.5, l'entrée existe sous le lemme du\n\
             singulier et c'est l'émission qu'il faut corriger, pas la balise ;\n\
             — si rien ne la déclare, c'est une fiche à écrire ou un gras à retirer.\n\
             \n\
             Relever `PLAFOND_LIENS_MORTS` est possible, et se dit dans le commit :\n\
             un cliquet qu'on desserre sans le nommer ne cliquette plus.",
            controles::PLAFOND_LIENS_MORTS
        ));
    }

    Ok(BuildResult {
        stats,
        search_records: search_records.len(),
        issues: lu.issues.len(),
        bytes,
        ors_morts: ors_morts.len(),
        shemot_sans_fiche: shemot_sans_fiche.len(),
        sans_definition: sans_definition.len(),
        liens_morts: liens_morts.iter().map(|l| l.occurrences).sum(),
        liens_morts_lemmes: liens_morts.len(),
        sous_glosees: densites
            .iter()
            .filter(|d| sous_glosee(d, &densites))
            .count(),
        chapitres_mesures: densites.len(),
        moins_glosee: densites.first().map(|d| (d.unite.clone(), d.pour_mille())),
    })
}

/// Descend dans un arbre d'inline et relève les termes sans entrée.
/// Récolte les lemmes de tous les Shemot rencontrés.
fn collect_shem_lemmes(nodes: &[Inline], out: &mut Vec<String>) {
    for n in nodes {
        match n {
            Inline::Shem { lemma, .. } => out.push(lemma.clone()),
            Inline::Em { children }
            | Inline::Accentuation { children }
            | Inline::Gloss { children }
            | Inline::Link { children, .. } => collect_shem_lemmes(children, out),
            _ => {}
        }
    }
}

/// Récolte les Shemot dont la fiche manque.
///
/// Le pendant de [`collect_or_morts`] pour la troisième couche. Il ne dit pas
/// « ce nom est faux » mais « ce porteur n'a pas encore sa fiche » — c'est une
/// liste de travail, pas une liste d'erreurs.
fn collect_shemot_sans_fiche(nodes: &[Inline], fiches: &HashSet<String>, out: &mut Vec<String>) {
    for n in nodes {
        match n {
            Inline::Shem { v, lemma } => {
                if !fiches.contains(lemma) {
                    out.push(format!("**{v}** — `lexique/{lemma}.md`"));
                }
            }
            Inline::Em { children }
            | Inline::Accentuation { children }
            | Inline::Gloss { children }
            | Inline::Link { children, .. } => collect_shemot_sans_fiche(children, fiches, out),
            _ => {}
        }
    }
}

fn collect_or_morts(
    nodes: &[Inline],
    connus: &HashSet<String>,
    source: &str,
    out: &mut Vec<String>,
) {
    for n in nodes {
        match n {
            Inline::Term { v, lemma } => {
                if !connus.contains(lemma) {
                    out.push(format!("`{source}` — **{v}**"));
                }
            }
            Inline::Em { children }
            | Inline::Accentuation { children }
            | Inline::Gloss { children }
            | Inline::Link { children, .. } => collect_or_morts(children, connus, source, out),
            _ => {}
        }
    }
}

/// Ce que le rapport relève, en un seul paramètre.
///
/// Groupé parce que la liste s'allongeait à chaque contrôle ajouté, et que
/// huit paramètres positionnels finissent par se prendre l'un pour l'autre —
/// tous des tranches, tous du même type.
struct Anomalies<'a> {
    issues: &'a [Issue],
    unknown: &'a BTreeMap<String, Unknown>,
    superseded: &'a [String],
    fiches_orphelines: &'a [String],
    ors_morts: &'a [String],
    /// Les Shemot que le corpus nomme et pour lesquels aucune fiche n'existe.
    ///
    /// **Ils étaient comptés, triés, dédoublonnés — puis seul `.len()`
    /// survivait**, et le `Vec` était jeté. Le rapport annonçait « 10 Shemot
    /// sans fiche » sans dire lesquels, ce qui ne permet à personne d'agir :
    /// il faut alors refaire à la main le relevé que le pipeline venait de
    /// faire. Les trois autres compteurs ont tous leur section ; celui-ci
    /// était le seul à n'avoir qu'un nombre.
    shemot_sans_fiche: &'a [String],
    /// Les liens **livrés** qui ne retombent sur aucune entrée livrée.
    ///
    /// Distinct de `ors_morts` et de `shemot_sans_fiche`, qui demandent « une
    /// fiche existe-t-elle pour ce terme ? » en traversant `forms`. Celui-ci
    /// demande « le lemme écrit dans le nœud est-il une clé du fichier
    /// d'index ? » — la question que se pose la liseuse, et la seule qui dise
    /// ce que le lecteur obtiendra.
    liens_morts: &'a [controles::LienMort],
    /// La densité d'apparat par unité, §4.1.
    densites: &'a [controles::Densite],
    /// Les nœuds touchables que les parcours restreints ne visitent pas.
    hors_de_portee: usize,
    /// Les formes que deux entrées revendiquent.
    formes_partagees: &'a [(String, Vec<String>)],
}

/// Une unité tombe-t-elle **très en dessous** de la référence du §4.1 ?
///
/// Le §4.1 écrit *« très en dessous »* sans le chiffrer, et il a raison de ne
/// pas le faire : c'est un jugement. Le contrôle doit pourtant trancher pour
/// nommer quelqu'un, donc il pose son seuil **ici, en clair, à la moitié** —
/// et le rapport l'écrit, afin que le seuil se discute au lieu de se subir.
fn sous_glosee(d: &controles::Densite, toutes: &[controles::Densite]) -> bool {
    let Some(reference) = toutes.iter().find(|r| r.unite == controles::REFERENCE) else {
        // Sans la référence dans le corpus bâti, on ne compare rien plutôt que
        // de comparer à une constante inventée.
        return false;
    };
    d.unite != controles::REFERENCE && d.pour_mille() < reference.pour_mille() / 2.0
}

fn format_report(
    corpora: &[Corpus],
    glossary: &[GlossaryEntry],
    a: &Anomalies,
    racine: &Path,
) -> String {
    let Anomalies {
        issues,
        unknown,
        superseded,
        fiches_orphelines,
        ors_morts,
        shemot_sans_fiche,
        liens_morts,
        densites,
        hors_de_portee,
        formes_partagees,
    } = *a;
    let books: Vec<&Book> = corpora
        .iter()
        .flat_map(|c| c.modes.iter().flat_map(|m| m.books.iter()))
        .collect();
    let written: Vec<&&Book> = books.iter().filter(|b| !b.empty).collect();

    let mut l: Vec<String> = vec![
        "# ONT — rapport de build".into(),
        String::new(),
        format!("Vault : `{}`", racine.display()),
        String::new(),
        "## Couverture".into(),
        String::new(),
        format!("- Slots au total : **{}**", books.len()),
        format!("- Slots rédigés : **{}**", written.len()),
        format!(
            "- Unités : **{}** chapitres, **{}** feuilles d'introduction",
            written.iter().map(|b| b.chapters.len()).sum::<usize>(),
            written.iter().filter(|b| b.intro.is_some()).count()
        ),
        format!(
            "- Versets : **{}**",
            written
                .iter()
                .map(|b| b.chapters.iter().map(|c| c.verse_count).sum::<u32>())
                .sum::<u32>()
        ),
        String::new(),
        "| Livre | Slot | Verrouillés | Brouillons | Intro | Versets |".into(),
        "|---|---:|---:|---:|:-:|---:|".into(),
    ];

    for book in &written {
        let locked = book
            .chapters
            .iter()
            .filter(|c| c.status == Status::Locked)
            .count();
        let drafts = book.chapters.len() - locked;
        let verses: u32 = book.chapters.iter().map(|c| c.verse_count).sum();
        l.push(format!(
            "| *{}* | {} | {} | {} | {} | {} |",
            book.title,
            book.slot,
            locked,
            drafts,
            if book.intro.is_some() { "✓" } else { "—" },
            verses
        ));
    }

    let used: Vec<&GlossaryEntry> = glossary.iter().filter(|e| e.count > 0).collect();
    l.extend([
        String::new(),
        "## Glossaire".into(),
        String::new(),
        format!(
            "- Entrées : **{}** — dont **{}** intraduisibles balisés",
            glossary.len(),
            glossary.iter().filter(|e| e.tagged).count()
        ),
        format!(
            "- Entrées attestées dans le corpus rédigé : **{}**",
            used.len()
        ),
        String::new(),
        "### Les vingt intraduisibles les plus présents".into(),
        String::new(),
        "| Terme | Hébreu | Corps | Gloses | Total | Premier emploi |".into(),
        "|---|---|---:|---:|---:|---|".into(),
    ]);

    let mut tries = used.clone();
    tries.sort_by_key(|t| std::cmp::Reverse(t.count));
    for e in tries.iter().take(20) {
        l.push(format!(
            "| **{}** | {} | {} | {} | {} | {} |",
            e.title,
            e.hebrew.as_deref().unwrap_or("—"),
            e.body_count,
            e.gloss_count,
            e.count,
            e.first_use.as_deref().unwrap_or("—")
        ));
    }

    // Une fiche écrite pour un lemme qui n'existe pas est du travail perdu :
    // elle est committée, publiée, et personne ne la lit jamais. Le nom de
    // fichier fait la jointure — `lexique/chesed.md` ↔ le lemme `chesed`.
    if !fiches_orphelines.is_empty() {
        l.extend([
            String::new(),
            "## Fiches sans entrée de glossaire".into(),
            String::new(),
            "Ces fiches de `lexique/` ne retombent sur aucun lemme : leur texte".into(),
            "n'atteint aucun lecteur. Le nom du fichier doit être le lemme.".into(),
            String::new(),
        ]);
        for f in fiches_orphelines {
            l.push(format!("- `lexique/{f}.md`"));
        }
    }

    // Un nom propre que le texte porte sans qu'aucune fiche ne l'explique :
    // le lecteur touche le mot et n'obtient rien.
    if !shemot_sans_fiche.is_empty() {
        l.extend([
            String::new(),
            "## Shemot sans fiche".into(),
            String::new(),
            "Ces noms propres sont employés dans le corpus publié et n'ont pas".into(),
            "de fiche dans `lexique/`. Le nom du fichier doit être le lemme.".into(),
            String::new(),
        ]);
        for s in shemot_sans_fiche {
            l.push(format!("- {s}"));
        }
    }

    // Le gras d'insistance dans une fiche promet une fiche qui n'existe pas.
    if !ors_morts.is_empty() {
        l.extend([
            String::new(),
            "## Mots d'or sans fiche, dans le lexique".into(),
            String::new(),
            "`**…**` promet une entrée de lexique. Employé pour insister, il".into(),
            "promet une fiche absente — c'est le défaut que le §2.5 bis supprime.".into(),
            "Passer ces formes en `==…==` (accentuation), ou leur écrire une entrée.".into(),
            String::new(),
        ]);
        for o in ors_morts {
            l.push(format!("- {o}"));
        }
    }

    if !unknown.is_empty() {
        let lemmes: Vec<&str> = glossary.iter().map(|e| e.lemma.as_str()).collect();
        l.extend([
            String::new(),
            "## Formes en gras absentes du glossaire".into(),
            String::new(),
            "Le §2.5 réserve `**…**` *exclusivement* aux intraduisibles. Chaque forme".into(),
            "ci-dessous est soit un intraduisible à déclarer, soit du gras à retirer.".into(),
            String::new(),
            "| Forme | Occ. | Où | Piste | Contexte |".into(),
            "|---|---:|---|---|---|".into(),
        ]);

        let mut rows: Vec<(&String, &Unknown)> = unknown.iter().collect();
        rows.sort_by_key(|r| std::cmp::Reverse(r.1.count));
        for (slug, info) in rows {
            let piste = guess_lemma(slug, lemmes.iter().copied())
                .map(|g| format!("dérivé de **{g}** ?"))
                .unwrap_or_else(|| "—".into());
            l.push(format!(
                "| `{}` | {} | {} | {} | {} |",
                info.form,
                info.count,
                info.where_,
                piste,
                info.sample.replace('|', "\\|")
            ));
        }
    }

    if !liens_morts.is_empty() {
        let occurrences: usize = liens_morts.iter().map(|l| l.occurrences).sum();
        let (recuperables, a_ecrire): (Vec<_>, Vec<_>) =
            liens_morts.iter().partition(|l| l.entree_reelle.is_some());
        l.extend([
            String::new(),
            "## Liens livrés qui n'ouvrent rien".into(),
            String::new(),
            format!(
                "**{occurrences} occurrences, {} lemmes distincts.** Mesuré sur `dist/` et",
                liens_morts.len()
            ),
            "non sur le vault : chaque `lemma` émis est comparé aux clés du fichier".into(),
            "d'index livré **dans le même build**. C'est la question que se pose la".into(),
            "liseuse, et la seule qui dise ce que le lecteur obtiendra.".into(),
            String::new(),
            "Les autres sections demandent *« une fiche existe-t-elle pour ce".into(),
            "terme ? »* en traversant `forms`, et peuvent donc rendre `0` pendant".into(),
            "que celle-ci compte des centaines : c'est exactement l'écart qui a".into(),
            "laissé passer le défaut — le rapport normalisait autrement que le".into(),
            "consommateur.".into(),
        ]);

        if !recuperables.is_empty() {
            l.extend([
                String::new(),
                "### L'entrée existe, sous un autre lemme".into(),
                String::new(),
                "La forme est **déclarée** au §2.5 et retombe bien sur une entrée —".into(),
                "mais le nœud livré porte la forme fléchie au lieu du lemme canonique,".into(),
                "et la liseuse indexe par lemme exact. ==Le lecteur reçoit un démenti".into(),
                "faux== : le mot est documenté, on lui dit qu'il ne l'est pas.".into(),
                String::new(),
                "Le remède est **à l'émission**. Le porter chez les consommateurs".into(),
                "obligerait chaque plateforme à réécrire sa propre normalisation pour".into(),
                "faire se rejoindre `mal'akhim` et `malakhim` — et deux normalisations".into(),
                "écrites séparément divergent, ce qui rendrait le défaut intermittent".into(),
                "au lieu de systématique.".into(),
                String::new(),
                "| Affiché | Lemme émis | Entrée réelle | Occ. | Vu d'abord |".into(),
                "|---|---|---|---:|---|".into(),
            ]);
            for m in &recuperables {
                l.push(format!(
                    "| {} | `{}` | `{}` | {} | `{}` |",
                    m.forme,
                    m.lemme,
                    m.entree_reelle.as_deref().unwrap_or("—"),
                    m.occurrences,
                    m.ou
                ));
            }
        }

        if !a_ecrire.is_empty() {
            l.extend([
                String::new(),
                "### Aucune entrée ne déclare cette forme".into(),
                String::new(),
                "Ceux-là sont une vraie liste de travail : la fiche est à écrire, ou".into(),
                "la balise est à retirer.".into(),
                String::new(),
                "| Affiché | Lemme émis | Couche | Occ. | Vu d'abord |".into(),
                "|---|---|---|---:|---|".into(),
            ]);
            for m in &a_ecrire {
                l.push(format!(
                    "| {} | `{}` | {} | {} | `{}` |",
                    m.forme, m.lemme, m.couche, m.occurrences, m.ou
                ));
            }
        }
    }

    if hors_de_portee > 0 || !formes_partagees.is_empty() {
        l.extend([
            String::new(),
            "## Ce que les autres parcours ne voient pas".into(),
            String::new(),
            "Deux relevés qui ne corrigent rien et ne jugent rien. Ils disent".into(),
            "seulement si un `0` affiché ailleurs est un zéro de corpus ou un zéro".into(),
            "d'instrument — **les deux s'écrivent pareil, et c'est le premier qu'on**".into(),
            "**lit**.".into(),
            String::new(),
        ]);
        if hors_de_portee > 0 {
            l.extend([
                format!(
                    "- **{hors_de_portee} nœuds touchables hors de portée des parcours restreints.**"
                ),
                "  `collect_shem_lemmes` et `collect_shemot_sans_fiche` ne lisent que".into(),
                "  `Heading`, `Para` et `Verses` de `blocks` : ni pied de section, ni".into(),
                "  liste, ni citation, ni tableau. Leur verdict peut être juste ; il".into(),
                "  n'est pas *démontré* tant que ce nombre n'est pas nul.".into(),
            ]);
        }
        if !formes_partagees.is_empty() {
            l.extend([
                format!(
                    "- **{} formes revendiquées par plusieurs entrées.** Le §2.5 en cite",
                    formes_partagees.len()
                ),
                "  certaines dans la puce voisine pour les en *écarter*, et l'extraction".into(),
                "  ne distingue pas une citation d'une déclaration. Sans conséquence".into(),
                "  aujourd'hui — la forme sort avec le lemme de sa propre entrée. Le jour".into(),
                "  où l'ordre de lecture changera, elle sortira avec l'autre :".into(),
                String::new(),
            ]);
            for (forme, lemmes) in formes_partagees {
                l.push(format!("  - `{forme}` → {}", lemmes.join(", ")));
            }
        }
    }

    if !densites.is_empty() {
        let reference = densites.iter().find(|d| d.unite == controles::REFERENCE);
        l.extend([
            String::new(),
            "## Densité d'apparat, par unité".into(),
            String::new(),
            "Le §4.1 impose de compter avant de clore — *« le seul contrôle qui ne".into(),
            "dépende pas de ce que le traducteur a fini par trouver évident »*. Une".into(),
            "commande qu'il faut penser à lancer est une commande qu'on oublie ;".into(),
            "elle tourne donc ici.".into(),
            String::new(),
            "**On rapporte aux mots du corps, non aux versets.** Un verset ONT n'a".into(),
            "pas de longueur fixe — le *Chazon Avraham* découpe une phrase de témoin".into(),
            "en plusieurs versets courts là où *Bereshit* suit le verset biblique.".into(),
            "Un ratio par verset dirait ce qu'on a décidé du découpage, pas ce qu'on".into(),
            "a écrit d'apparat.".into(),
            String::new(),
            "Deux colonnes, et il faut les deux : la **fréquence** dit si".into(),
            "l'implicite a été explicité *là où il se trouve*, le **volume** dit".into(),
            "s'il l'a été du tout. Une unité peut porter tout le volume attendu en".into(),
            "quelques blocs énormes — c'est lisible sur la page et illisible pour".into(),
            "l'œil qui suit le texte.".into(),
            String::new(),
        ]);
        match reference {
            Some(r) => l.push(format!(
                "Référence §4.1 — `{}` : **{:.1}** gloses / 1000 mots, volume **{:.2}**.",
                r.unite,
                r.pour_mille(),
                r.volume()
            )),
            None => l.push(
                "*La référence `bereshit-4` n'est pas dans ce build : aucune unité \
n'est signalée, faute de point de comparaison.*"
                    .into(),
            ),
        }
        // **Par livre d'abord.** La question que ce relevé pose n'est pas
        // « ce chapitre est-il assez glosé ? » mais « ce livre est-il sur un
        // autre régime ? » — et vingt-six lignes qui la répètent à chaque build
        // sont vingt-cinq façons de cesser de la lire.
        let mut par_livre: BTreeMap<&str, (usize, usize, usize, usize)> = BTreeMap::new();
        for d in densites {
            let e = par_livre.entry(d.livre.as_str()).or_default();
            e.0 += 1;
            e.1 += d.gloses;
            e.2 += d.mots_corps;
            if sous_glosee(d, densites) {
                e.3 += 1;
            }
        }
        l.extend([
            String::new(),
            "| Livre | Chapitres | gl./1000 mots | Sous le seuil |".into(),
            "|---|---:|---:|---:|".into(),
        ]);
        let mut lignes: Vec<(f64, String)> = par_livre
            .iter()
            .map(|(livre, (n, gl, mots, sous))| {
                let pm = if *mots == 0 {
                    0.0
                } else {
                    1000.0 * *gl as f64 / *mots as f64
                };
                (
                    pm,
                    format!(
                        "| `{livre}` | {n} | {pm:.1} | {} |",
                        if *sous == 0 {
                            "—".to_string()
                        } else {
                            format!("{sous} / {n}")
                        }
                    ),
                )
            })
            .collect();
        lignes.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
        for (_, ligne) in lignes {
            l.push(ligne);
        }

        l.extend([
            String::new(),
            "<details><summary>Le détail par chapitre</summary>".into(),
            String::new(),
            "| Unité | Versets | Gloses | gl./1000 mots | Volume | Plus longue | |".into(),
            "|---|---:|---:|---:|---:|---:|:-:|".into(),
        ]);
        for d in densites {
            let marque = if d.unite == controles::REFERENCE {
                "réf."
            } else if sous_glosee(d, densites) {
                "⚠"
            } else {
                ""
            };
            l.push(format!(
                "| `{}` | {} | {} | {:.1} | {:.2} | {} | {} |",
                d.unite,
                d.versets,
                d.gloses,
                d.pour_mille(),
                d.volume(),
                d.plus_longue,
                marque
            ));
        }
        l.extend([String::new(), "</details>".into()]);
        if reference.is_some() {
            l.extend([
                String::new(),
                "⚠ = sous **la moitié** de la référence. Le §4.1 écrit *« très en".into(),
                "dessous »* sans le chiffrer, et il a raison — c'est un jugement. Le".into(),
                "seuil est posé ici, en clair, pour qu'il se discute plutôt qu'il ne".into(),
                "se subisse. Un signalement n'est pas une faute : un livre peut".into(),
                "déclarer un régime allégé, et sa feuille d'introduction le dit.".into(),
                String::new(),
                "**Les feuilles d'introduction ne sont pas mesurées.** Le §2.7 leur".into(),
                "donne la fonction inverse — porter le cadre une fois en amont *afin".into(),
                "que* les gloses du corps restent légères. Une intro sans glose fait".into(),
                "son travail.".into(),
            ]);
        }
    }

    if !issues.is_empty() {
        // `BTreeSet` sur les fichiers : l'ordre du rapport ne doit pas dépendre
        // de l'ordre de parcours.
        let fichiers: BTreeSet<&str> = issues.iter().map(|i| i.file.as_str()).collect();
        l.extend([
            String::new(),
            "## Marqueurs déséquilibrés".into(),
            String::new(),
        ]);
        for fichier in fichiers {
            l.push(format!("- `{fichier}`"));
            for issue in issues.iter().filter(|i| i.file == fichier) {
                l.push(format!("  - ligne {} — {}", issue.line, issue.message));
            }
        }
    }

    if !superseded.is_empty() {
        l.extend([
            String::new(),
            "## Unités verrouillées masquées par un brouillon".into(),
            String::new(),
        ]);
        for f in superseded {
            l.push(format!("- `{f}`"));
        }
    }

    l.join("\n") + "\n"
}

/// Toutes les unités d'un livre — **l'intro comprise**.
///
/// Elle est une unité comme une autre : elle porte du texte, des Shemot, des
/// intraduisibles et des renvois. `chazon-avraham` n'est *que* cela — aucun
/// chapitre —, donc l'oublier revient à ne pas lire le livre.
///
/// Cette fonction existe parce que l'oubli s'est produit **trois fois**, dans
/// trois parcours écrits à des moments différents, pendant que deux autres
/// faisaient correctement `intro.iter().chain(chapters.iter())`. Un idiome
/// juste mais recopié à la main se recopie mal ; celui-ci ne se recopie plus.
///
/// Le défaut ne se voyait pas : le rendu atteignait les intros, l'indexeur non.
/// Deux chemins sur la même donnée, dont un seul complet. `Yaho'el` était rendu
/// huit fois en terre brûlée et absent de `shemot.json` — on touchait le nom,
/// la feuille ne trouvait rien.
fn unites(livre: &Book) -> impl Iterator<Item = &Chapter> {
    livre.intro.iter().chain(livre.chapters.iter())
}

/// La même, pour qui doit écrire dedans. Voir [`unites`].
fn unites_mut(livre: &mut Book) -> impl Iterator<Item = &mut Chapter> {
    livre.intro.iter_mut().chain(livre.chapters.iter_mut())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Une unité d'introduction dans un livre qui n'a que ça.
    fn livre_sans_chapitre(lemme: &str) -> Book {
        let unite = Chapter {
            id: "chazon-avraham-0-intro".into(),
            book_id: "chazon-avraham".into(),
            kind: ChapterKind::Intro,
            n: 0,
            title: "Chazon Avraham — introduction".into(),
            title_nodes: vec![],
            subtitle: None,
            status: Status::Brouillon,
            blocks: vec![Block::Para {
                nodes: vec![Inline::Shem {
                    v: "Yaho'el".into(),
                    lemma: lemme.into(),
                }],
            }],
            footer: None,
            verse_count: 0,
            lemmas: vec![],
            source: "chazon-avraham.md".into(),
        };
        Book {
            id: "chazon-avraham".into(),
            slot: 1,
            title: "Chazon Avraham".into(),
            french: "Apocalypse d'Abraham".into(),
            glose: None,
            hebrew: None,
            corpus_id: "nistarot".into(),
            mode_id: "nistarot".into(),
            group_id: None,
            chapters: vec![],
            intro: Some(unite),
            empty: false,
        }
    }

    /// **Un livre peut n'être qu'une introduction, et il faut le lire.**
    ///
    /// `chazon-avraham` n'a aucun chapitre. Trois parcours ne regardaient que
    /// `chapters` : l'indexeur des Shemot, le relevé de ceux sans fiche, et le
    /// lieur de renvois. Le rendu, lui, atteignait les intros — deux chemins
    /// sur la même donnée, dont un seul complet.
    ///
    /// `Yaho'el` était rendu huit fois en terre brûlée et absent de
    /// `shemot.json` : on touchait le nom, la feuille ne trouvait rien. Et la
    /// garde des fiches orphelines, qui s'appuie sur cette liste, l'aurait
    /// dénoncé comme du travail perdu — on aurait supprimé une fiche valide
    /// sur la foi du rapport.
    ///
    /// Relevé par la session du vault, en comparant les lemmes rendus dans
    /// `dist/books` à ceux de l'index. Deux chemins, deux comptes : 205 et 194.
    #[test]
    fn un_livre_sans_chapitre_est_lu_quand_meme() {
        let livre = livre_sans_chapitre("yahoel");
        assert_eq!(unites(&livre).count(), 1, "l'intro n'a pas été parcourue");

        let mut vus: Vec<String> = Vec::new();
        for unite in unites(&livre) {
            for bloc in &unite.blocks {
                if let Block::Para { nodes } = bloc {
                    collect_shem_lemmes(nodes, &mut vus);
                }
            }
        }
        assert_eq!(vus, ["yahoel"], "le Shem de l'intro n'est pas indexé");
    }

    /// L'intro vient **avant** les chapitres, et s'ajoute sans les remplacer.
    #[test]
    fn l_intro_s_ajoute_aux_chapitres_sans_les_evincer() {
        let mut livre = livre_sans_chapitre("yahoel");
        let mut chapitre = livre.intro.clone().unwrap();
        chapitre.id = "chazon-avraham-1".into();
        chapitre.n = 1;
        livre.chapters = vec![chapitre];
        let ids: Vec<&str> = unites(&livre).map(|u| u.id.as_str()).collect();
        assert_eq!(ids, ["chazon-avraham-0-intro", "chazon-avraham-1"]);
    }

    /// Le rapport nommait un nombre sans jamais nommer sa substance.
    ///
    /// Les Shemot sans fiche étaient calculés, triés, dédoublonnés — puis seul
    /// `.len()` survivait. « 10 Shemot sans fiche » ne permet à personne
    /// d'agir : il faut refaire à la main le relevé que le pipeline vient de
    /// faire. C'est ce qu'a dû faire la session du vault pour les retrouver.
    #[test]
    fn le_rapport_nomme_les_shemot_sans_fiche() {
        let sans = ["**Par'oh** — `lexique/paroh.md`".to_string()];
        // **Le cliquet, posé après l'écriture du rapport et avant de rendre.**
        //
        // Après, pour que `dist/report.md` existe quand l'échec survient : sans
        // lui, celui qui reçoit l'échec n'a que le nombre et doit refaire à la main
        // le relevé que le pipeline vient de faire.
        let rapport = format_report(
            &[],
            &[],
            &Anomalies {
                issues: &[],
                unknown: &BTreeMap::new(),
                superseded: &[],
                fiches_orphelines: &[],
                ors_morts: &[],
                shemot_sans_fiche: &sans,
                liens_morts: &[],
                densites: &[],
                hors_de_portee: 0,
                formes_partagees: &[],
            },
            Path::new("/vault"),
        );
        assert!(
            rapport.contains("## Shemot sans fiche"),
            "la section manque"
        );
        assert!(rapport.contains("Par'oh"), "le nom manque : {rapport}");
    }

    /// Une section vide ne s'écrit pas — comme les trois autres.
    #[test]
    fn sans_shem_orphelin_la_section_ne_parait_pas() {
        // **Le cliquet, posé après l'écriture du rapport et avant de rendre.**
        //
        // Après, pour que `dist/report.md` existe quand l'échec survient : sans
        // lui, celui qui reçoit l'échec n'a que le nombre et doit refaire à la main
        // le relevé que le pipeline vient de faire.
        let rapport = format_report(
            &[],
            &[],
            &Anomalies {
                issues: &[],
                unknown: &BTreeMap::new(),
                superseded: &[],
                fiches_orphelines: &[],
                ors_morts: &[],
                shemot_sans_fiche: &[],
                liens_morts: &[],
                densites: &[],
                hors_de_portee: 0,
                formes_partagees: &[],
            },
            Path::new("/vault"),
        );
        assert!(!rapport.contains("## Shemot sans fiche"));
    }

    #[test]
    fn l_extrait_se_centre_sur_la_forme() {
        let texte = "au commencement Elohim orchestra les cieux et la terre";
        let extrait = make_snippet(texte, "Elohim", 30, 0);
        assert!(extrait.contains("Elohim"));
    }

    #[test]
    fn l_extrait_ne_coupe_pas_au_milieu_d_un_caractere() {
        // Le cas qui distingue Rust de JavaScript : chaque lettre hébraïque
        // pèse deux octets. Une fenêtre comptée en octets rendrait de l'UTF-8
        // invalide, donc une panique.
        let texte = "וַיֵּרָא אֵלָיו יְהוָה וְהוּא יֹשֵׁב פֶּתַח הָאֹהֶל";
        let extrait = make_snippet(texte, "יְהוָה", 20, 0);
        assert!(!extrait.is_empty());
    }

    #[test]
    fn la_seconde_occurrence_donne_un_autre_extrait() {
        // Trois `chesed` dans un même verset ne doivent pas donner trois fois
        // le même extrait.
        let texte = "premier chesed puis beaucoup de mots au milieu et enfin second chesed final";
        let a = make_snippet(texte, "chesed", 30, 0);
        let b = make_snippet(texte, "chesed", 30, 40);
        assert_ne!(a, b);
    }

    #[test]
    fn la_piste_prend_le_prefixe_le_plus_long() {
        let connus = ["tsadiq", "tsa", "shaliach"];
        assert_eq!(
            guess_lemma("tsadiqim", connus.into_iter()),
            Some("tsadiq".into())
        );
        // Un lemme de moins de quatre lettres ne fait pas une piste : il
        // attraperait n'importe quoi.
        assert_eq!(guess_lemma("tsadiqim", ["tsa"].into_iter()), None);
    }

    #[test]
    fn une_forme_egale_a_son_lemme_n_est_pas_une_piste() {
        assert_eq!(guess_lemma("chesed", ["chesed"].into_iter()), None);
    }
}
