//! Le build — le vault devient des données consommables par une liseuse.
//!
//! ```text
//! dist/corpus.json        l'arborescence de navigation, les 70 slots
//! dist/books/<id>.json    le contenu complet d'un livre
//! dist/glossary.json      le lexique des intraduisibles
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
use crate::inline::{collect_terms, plain_text, tidy, PlainOptions};
use crate::reference::{read_fiches, read_reference, BookName, Reference};
use crate::renvois;
use crate::schema::{
    Block, Book, BookOutline, BuildStats, Chapter, ChapterKind, Corpus, CorpusFile, CorpusOutline,
    DailyFile, DailyVerse, GlossaryEntry, GlossaryFile, Group, Inline, Manifest, Mode, ModeOutline,
    Occurrence, OccurrencesFile, SearchFile, SearchRecord, Status, Stub, TermLevel,
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
                french: fr.to_string(),
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
                french: fr.to_string(),
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
    let lemmes: HashSet<&str> = glossary.iter().map(|e| e.lemma.as_str()).collect();
    let mut fiches_orphelines: Vec<String> = fiches
        .keys()
        .filter(|l| !lemmes.contains(l.as_str()))
        .cloned()
        .collect();
    fiches_orphelines.sort();
    for entry in glossary.iter_mut() {
        if let Some(blocs) = fiches.get(&entry.lemma) {
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
                    for unite in &mut livre.chapters {
                        let origine = unite.id.clone();
                        renvois::lier(&mut unite.blocks, &index, &origine);
                    }
                }
            }
        }
    }
    let corpora = corpora;
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
        for unit in book.intro.iter().chain(book.chapters.iter()) {
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
        for unit in book.intro.iter().chain(book.chapters.iter()) {
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
            // Sans dépendance de date : l'empreinte du contenu suffit à savoir
            // si le corpus a changé, et un horodatage rendrait deux builds du
            // même vault différents pour rien.
            generated_at: String::new(),
            vault: racine.to_string_lossy().to_string(),
            stats: stats.clone(),
        },
    )
    .map_err(|e| e.to_string())?;

    let rapport = format_report(
        &corpora,
        &glossary,
        &Anomalies {
            issues: &lu.issues,
            unknown: &indexed.unknown,
            superseded: &lu.superseded,
            fiches_orphelines: &fiches_orphelines,
            ors_morts: &ors_morts,
        },
        &racine,
    );
    fs::write(sortie.join("report.md"), rapport).map_err(|e| e.to_string())?;

    Ok(BuildResult {
        stats,
        search_records: search_records.len(),
        issues: lu.issues.len(),
        bytes,
        ors_morts: ors_morts.len(),
    })
}

/// Descend dans un arbre d'inline et relève les termes sans entrée.
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

#[cfg(test)]
mod tests {
    use super::*;

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
