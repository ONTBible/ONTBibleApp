//! Schéma des données ONT — **le contrat**.
//!
//! Ce module est le seul endroit où la forme des données est décrite. Le vault
//! Obsidian entre d'un côté, les liseuses lisent de l'autre, et tout ce qui
//! voyage entre les deux est ici.
//!
//! ## Pourquoi ce fichier existe une seule fois
//!
//! Il était décrit trois fois : ici en TypeScript, dans le site en Rust, dans
//! l'app en Swift. Trois définitions du même schéma finissent par diverger, et
//! quand elles divergent le défaut est **muet** — la liseuse qui ne connaît pas
//! un type de nœud l'omet, la page s'affiche, et il manque un mot.
//!
//! C'est arrivé : quatre types de nœuds — `heb`, `link`, `quote`, `table` — ont
//! échappé au premier relevé du site parce qu'ils ne vivent que dans les
//! définitions du lexique, jamais dans un chapitre.
//!
//! Le site dépend désormais de ce module. Il en reste deux, et la troisième —
//! le Swift — est le prochain chantier.
//!
//! ## Les trois niveaux ne s'aplatissent pas
//!
//! Le principe directeur vient du CLAUDE.md §2.1 :
//!
//! ```text
//! niveau 1  le corps de la traduction        → Text
//! niveau 2  les gloses *[entre crochets]*    → Gloss
//! niveau 3  (translittération / hébreu)      → Translit
//! ```
//!
//! Plus les intraduisibles (§2.5) → `Term`, porte d'entrée du lexique : toucher
//! un `Term` ouvre sa fiche.

use serde::{Deserialize, Serialize};

// ─────────────────────────────────────────────────────────────────────────────
// Niveau inline — l'arbre d'un fragment de texte
// ─────────────────────────────────────────────────────────────────────────────

/// Un nœud du texte.
///
/// Sérialisé avec un champ `t` qui porte le type, comme en TypeScript :
/// `{"t":"text","v":"…"}`. La représentation est celle que les liseuses lisent
/// déjà — ce port ne change pas un octet du JSON produit.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "t", rename_all = "lowercase")]
pub enum Inline {
    /// Le corps de la traduction — niveau 1.
    Text { v: String },

    /// Un intraduisible (§2.5), balisé `**ainsi**`.
    ///
    /// `v` garde la casse exacte du texte — `**Elohim**` et `**elohim**` ne se
    /// composent pas pareil — et `lemma` est la clé de jointure vers le
    /// glossaire. La liseuse rend `v` et ouvre la fiche `lemma`.
    Term { v: String, lemma: String },

    /// Niveau 3 — `(*translittération* / hébreu)`.
    ///
    /// Les deux parts sont séparées parce qu'elles ne se composent pas pareil :
    /// la translittération est en italique dans la fonte latine, l'hébreu
    /// demande une fonte hébraïque et un passage en RTL.
    Translit { translit: String, hebrew: String },

    /// Un fragment en écriture hébraïque rencontré hors d'un nœud `translit`.
    ///
    /// Isolé pour que la liseuse sache où appliquer la fonte hébraïque sans
    /// avoir à refaire de la détection d'écriture.
    Heb { v: String },

    /// Niveau 2 — une glose `*[entre crochets en italique]*`.
    Gloss { children: Vec<Inline> },

    /// Une **accentuation** — ni corps ordinaire, ni intraduisible.
    ///
    /// La troisième catégorie, née d'un défaut : des mots mis en gras pour
    /// insister se retrouvaient déclarés intraduisibles, donc dorés et
    /// touchables, ouvrant une fiche vide. L'intention était juste, il lui
    /// manquait sa marque — `==ainsi==`, le surlignage natif d'Obsidian.
    ///
    /// **Le tag du fil change avec elle**, en `"accentuation"` — d'où le
    /// schéma du corpus monté à 2. Une app antérieure lèverait sur ce nœud
    /// inconnu ; le numéro de schéma la fait renoncer à la mise à jour bien
    /// avant, et elle garde son corpus embarqué, entier.
    Accentuation { children: Vec<Inline> },

    /// De l'italique ordinaire `*ainsi*` — renvois de livres, mots cités.
    Em { children: Vec<Inline> },

    /// Un lien Obsidian `[[cible]]` ou markdown `[texte](cible)`.
    Link { children: Vec<Inline>, href: String },

    /// Un retour à la ligne à l'intérieur d'un bloc.
    ///
    /// Le vault écrit un paragraphe par ligne ; quand plusieurs lignes se
    /// suivent sans ligne vide, c'est délibéré — le bloc de référence d'une
    /// feuille d'introduction empile ses champs ainsi. On préserve la coupure
    /// au lieu de la fondre en espace.
    Break,
}

// ─────────────────────────────────────────────────────────────────────────────
// Niveau bloc — la structure d'un fichier
// ─────────────────────────────────────────────────────────────────────────────

/// Un verset ONT.
///
/// `n` est la numérotation **interne** à l'unité (§2.2) : elle repart de 1 à
/// chaque unité et ne correspond pas au numéro biblique. Le renvoi biblique vit
/// dans `Subtitle::reference`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Verse {
    pub n: u32,
    pub nodes: Vec<Inline>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "t", rename_all = "lowercase")]
pub enum Block {
    Heading {
        level: u8,
        nodes: Vec<Inline>,
    },
    /// Un paragraphe de versets — un paragraphe peut en porter plusieurs.
    Verses {
        verses: Vec<Verse>,
    },
    /// De la prose sans numérotation — introductions, notes de pied.
    Para {
        nodes: Vec<Inline>,
    },
    List {
        ordered: bool,
        items: Vec<Vec<Inline>>,
    },
    Quote {
        nodes: Vec<Inline>,
    },
    Table {
        headers: Vec<Vec<Inline>>,
        rows: Vec<Vec<Vec<Inline>>>,
    },
    Rule,
}

// ─────────────────────────────────────────────────────────────────────────────
// Unités ONT
// ─────────────────────────────────────────────────────────────────────────────

/// L'état d'un texte dans le flux de validation (§12).
///
/// `Locked` fait référence ; `Brouillon` attend la relecture de l'auteur.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Status {
    Locked,
    Brouillon,
}

/// Le sous-titre de référence — `*(Genèse / בְּרֵאשִׁית 18:1-33)*`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Subtitle {
    pub french: String,
    pub hebrew: String,
    /// Le renvoi biblique tel qu'écrit. **Nul sur une introduction**, qui ne
    /// recouvre aucun verset — et c'est un piège qu'un `default` ne couvre pas :
    /// la clé est présente et vaut `null`.
    pub reference: Option<String>,
}

/// Le pied de page — version, verrou, décisions terminologiques de l'unité.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Footer {
    pub version: Option<String>,
    pub locked: bool,
    pub notes: Vec<Block>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ChapterKind {
    Chapter,
    Intro,
}

/// Une unité ONT : un chapitre fonctionnel, ou la feuille d'introduction d'un
/// livre (§2.7).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Chapter {
    /// `bereshit-18`, `toledot-adam-ve-chavah-0-intro`.
    pub id: String,
    pub book_id: String,
    pub kind: ChapterKind,
    /// Numéro d'unité ONT. `0` pour une introduction.
    pub n: u32,
    /// Le titre en clair — `Bereshit 18`.
    pub title: String,
    pub title_nodes: Vec<Inline>,
    pub subtitle: Option<Subtitle>,
    pub status: Status,
    pub blocks: Vec<Block>,
    pub footer: Option<Footer>,
    pub verse_count: u32,
    /// Les lemmes employés dans l'unité, dédupliqués.
    pub lemmas: Vec<String>,
    /// Chemin du fichier source, relatif à la racine du vault.
    pub source: String,
}

/// Un livre — un slot de `corpus-order.md`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Book {
    pub id: String,
    /// Le numéro global 01–70.
    pub slot: u32,
    /// Le nom hébreu translittéré — le vrai titre (§2.6).
    pub title: String,
    /// Le nom français, pont de navigation pour le lecteur occidental.
    pub french: String,
    /// Ce que le nom ONT veut dire — absent quand il n'a rien à dire de plus
    /// que son pont. *Marqus* est un nom d'homme ; *Machazeh Yohanan* nomme
    /// une modalité de vision qu'« Apocalypse » ne porte pas.
    #[serde(default)]
    pub glose: Option<String>,
    /// Le titre en écriture hébraïque, quand il est connu.
    pub hebrew: Option<String>,
    pub corpus_id: String,
    pub mode_id: String,
    /// Le conteneur intermédiaire éventuel — `eduyot`, `trei-asar`.
    pub group_id: Option<String>,
    pub chapters: Vec<Chapter>,
    pub intro: Option<Chapter>,
    /// Vrai tant qu'aucun texte n'a été rédigé pour ce slot.
    pub empty: bool,
}

/// Un conteneur intermédiaire — `eduyot`, `trei-asar`, les deux `igerot`.
///
/// ## Pourquoi il devient un objet, et non plus un simple identifiant
///
/// Les livres portaient déjà un `group_id`, qui traversait tout — pipeline,
/// schéma, `Corpus.swift` — sans qu'aucune interface ne l'affiche. Le
/// regroupement existait dans les données et **le lecteur ne le voyait nulle
/// part** : les vingt-et-une *Igerot* se lisaient comme une liste plate.
///
/// Or l'une de ces coupures n'est pas un rangement. `corpus-order.md` la nomme
/// **pivot herméneutique** : le *Ḥurban*, la destruction du Second Temple en
/// 70. Avant, les lettres parlent du Temple au présent — *Igeret HaIvrim* est
/// « le dernier mot du *Bayit* vivant ». Après, il n'existe plus.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Group {
    pub id: String,
    /// Le nom ONT — `Igerot lifnei haḤurban`.
    pub title: String,
    /// Le pont de navigation, comme pour les livres.
    pub french: String,
    /// Ce que le nom dit, quand ça ne se confond pas avec le pont.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub glose: Option<String>,
    /// La ligne de sens qui **précède** ce groupe, quand la coupure est une
    /// rupture et non une subdivision.
    ///
    /// Réservée au *Ḥurban* : *Eduyot* et *Trei Asar* regroupent, ils ne
    /// fracturent pas. Une césure marquée partout ne marquerait plus rien.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rupture: Option<String>,
}

/// Un mode fonctionnel — Torah, Nevi'im, Ketouvim, Nistarot (§1).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Mode {
    pub id: String,
    pub title: String,
    /// Le pont de navigation — le mot que le lecteur cherche.
    ///
    /// Les intraduisibles y sont **rendus** : *Torah* devient « la Loi ».
    pub french: String,
    /// Ce que le nom ONT veut dire, quand ça n'est pas déjà le pont.
    ///
    /// Les intraduisibles y **restent en hébreu** : *Torah* devient « la
    /// Fondation », *Berit Hadashah* « la berith renouvelée ». L'écart entre
    /// les deux colonnes est ce que le projet cherche à faire voir.
    #[serde(default)]
    pub glose: Option<String>,
    pub order: u32,
    /// Les conteneurs de ce mode, dans l'ordre où leurs livres paraissent.
    ///
    /// **La clé est toujours écrite, même vide.** Elle portait d'abord un
    /// `skip_serializing_if` — cinq modes sur huit n'ont pas de conteneur, et
    /// l'omettre paraissait sobre. C'était un défaut sérieux : le code Swift
    /// engendré déclare `public let groups: [Group]`, non optionnel, et un
    /// `Decodable` synthétisé **exige** la clé. Les liseuses déjà livrées
    /// auraient levé `keyNotFound` sur ces cinq modes, sans qu'aucune garde ne
    /// se déclenche — le numéro de schéma du corpus ne change pas ici.
    ///
    /// Une clé **en trop** est ignorée ; une clé **manquante** sur un champ
    /// non optionnel lève. Ce n'est pas la même chose, et c'est la confusion
    /// qui a produit ce défaut.
    #[serde(default)]
    pub groups: Vec<Group>,
    pub books: Vec<Book>,
}

/// Un corpus — la *Kenesset* ou la *Berit Hadashah*.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Corpus {
    pub id: String,
    pub title: String,
    /// Le pont de navigation — le mot que le lecteur cherche.
    ///
    /// Les intraduisibles y sont **rendus** : *Torah* devient « la Loi ».
    pub french: String,
    /// Ce que le nom ONT veut dire, quand ça n'est pas déjà le pont.
    ///
    /// Les intraduisibles y **restent en hébreu** : *Torah* devient « la
    /// Fondation », *Berit Hadashah* « la berith renouvelée ». L'écart entre
    /// les deux colonnes est ce que le projet cherche à faire voir.
    #[serde(default)]
    pub glose: Option<String>,
    pub order: u32,
    pub modes: Vec<Mode>,
}

// ─────────────────────────────────────────────────────────────────────────────
// Glossaire
// ─────────────────────────────────────────────────────────────────────────────

/// Une entrée du glossaire : un intraduisible, toutes formes confondues.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GlossaryEntry {
    /// La clé de jointure avec `Inline::Term::lemma`.
    pub lemma: String,
    /// La forme d'affichage — `chesed`, `El Elyon`, `She'ol`.
    pub title: String,
    /// Vrai si le terme est **balisé** dans le texte (§2.5) : il a donc des
    /// occurrences et devient une cible de toucher.
    ///
    /// Faux pour le reste du vocabulaire fixé (§3) — *bara* → « orchestrer ».
    /// Ces termes-là sont traduits dans le corps, donc invisibles au toucher,
    /// mais méritent leur fiche.
    pub tagged: bool,
    /// Toutes les formes balisées qui retombent sur ce lemme.
    pub forms: Vec<String>,
    pub hebrew: Option<String>,
    /// La traduction ONT fixée, quand le terme en a une (§3).
    pub rendering: Option<String>,
    /// Le champ sémantique complet (§3).
    pub definition: Option<Vec<Block>>,
    /// La note de balisage (§2.5) — règles de rendu, formes dérivées.
    pub tagging_note: Option<Vec<Block>>,
    /// Le premier emploi déclaré — `Bereshit 15:6`.
    pub first_use: Option<String>,
    /// La section du CLAUDE.md dont vient la définition — `3.2`.
    pub source_section: Option<String>,
    pub count: u32,
    /// Occurrences dans le corps (niveau 1).
    pub body_count: u32,
    /// Occurrences dans les gloses (niveau 2).
    pub gloss_count: u32,
}

/// Le niveau du texte où une forme a été rencontrée (§2.1).
///
/// La distinction n'est pas cosmétique : un intraduisible qui *paraît* dans le
/// texte et un intraduisible qui y est *expliqué* ne se cherchent pas de la
/// même façon. Les confondre reviendrait à aplatir les niveaux que tout l'ONT
/// s'emploie à tenir séparés.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TermLevel {
    Body,
    Gloss,
}

/// Une occurrence d'un intraduisible, pour l'index inversé.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Occurrence {
    pub book_id: String,
    pub chapter_id: String,
    /// Numéro de verset ONT. **Nul hors d'un verset** — titre, note,
    /// introduction. C'est le cas de 319 occurrences sur 2 033.
    pub verse: Option<u32>,
    /// La forme exacte employée — `Elohim` vs `elohim`.
    pub form: String,
    pub level: TermLevel,
    /// Un extrait de contexte en texte nu.
    pub snippet: String,
}

// ─────────────────────────────────────────────────────────────────────────────
// Sortie du pipeline
// ─────────────────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BuildStats {
    pub books: u32,
    pub books_written: u32,
    pub chapters: u32,
    pub intros: u32,
    pub verses: u32,
    pub glossary_entries: u32,
    pub occurrences: u32,
    /// Termes balisés dans le texte mais absents du glossaire.
    pub unknown_terms: Vec<String>,
    /// Entrées du glossaire qui n'apparaissent nulle part dans le corpus.
    pub unused_entries: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Manifest {
    pub schema: u32,
    pub generated_at: String,
    pub vault: String,
    pub stats: BuildStats,
}

/// Le genre d'un enregistrement d'index — pour classer les résultats.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RecordKind {
    Verse,
    Heading,
    Prose,
}

/// Une entrée indexable — un verset, un titre de section, un paragraphe.
///
/// Les noms de champs font une lettre : l'index est embarqué dans le binaire de
/// l'app, et soixante-dix livres en feront un fichier qu'on ne veut pas voir
/// grossir pour des noms lisibles que personne ne lit.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SearchRecord {
    /// Livre.
    pub b: String,
    /// Unité ONT.
    pub c: String,
    /// Numéro de verset ONT, ou `0` hors d'un verset.
    pub v: u32,
    /// Pour classer les résultats.
    pub k: RecordKind,
    /// Le corps de la traduction, plié — minuscules, sans diacritiques.
    pub t: String,
    /// Les gloses, pliées.
    pub g: String,
    /// L'hébreu dénudé de ses voyelles et de sa cantillation.
    pub h: String,
    /// Les lemmes présents, pour la recherche par terme.
    pub l: Vec<String>,
    /// Le texte du corps tel qu'il s'affiche — pour l'extrait de résultat.
    pub x: String,
}

/// Un verset candidat au verset du jour.
///
/// Volontairement plat et sans arbre d'inline : ce vivier est lu par un widget
/// iOS, qui dispose d'une trentaine de mégaoctets et doit se dessiner en
/// quelques dizaines de millisecondes. Les noms de champs sont d'une lettre
/// pour la même raison — le fichier est embarqué dans le binaire de l'app.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DailyVerse {
    /// Le livre.
    pub b: String,
    /// L'unité.
    pub c: String,
    /// Le numéro du verset.
    pub n: u32,
    /// Le renvoi affichable — « Bereshit 1:1 ».
    pub r: String,
    /// Le corps de la traduction, seul.
    pub t: String,
}

// ─────────────────────────────────────────────────────────────────────────────
// Les fichiers publiés
// ─────────────────────────────────────────────────────────────────────────────
//
// Ce que `dist/` contient réellement, fichier par fichier. Ces formes étaient
// privées dans `build.rs` — le pipeline les écrivait, et chaque liseuse les
// redevinait de son côté à la lecture. C'est exactement la divergence que ce
// module existe pour empêcher : elles montent donc ici, et portent
// `Deserialize` autant que `Serialize`.
//
// **Chaque enveloppe porte `schema` en premier champ**, et l'ordre compte : le
// JSON produit reprend l'ordre de déclaration, et `corpus-publie.py` empreinte
// ces fichiers pour le téléchargement incrémental de l'app. Réordonner un champ
// change l'empreinte, donc fait retélécharger tout le corpus à tout le monde.
// Ce n'est pas grave, mais ce n'est pas gratuit.

/// Une vue allégée d'une unité, pour l'arborescence de navigation.
///
/// Le sommaire porte les soixante-dix slots. Y mettre le texte complet ferait
/// une vingtaine de mégaoctets pour une page qui n'affiche que des titres :
/// `corpus.json` ne garde donc de chaque unité que de quoi la nommer et y
/// mener.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Stub {
    pub id: String,
    pub n: u32,
    pub title: String,
    pub status: Status,
    pub verse_count: u32,
    pub reference: Option<String>,
}

/// Un livre dans l'arborescence — sans son texte.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BookOutline {
    pub id: String,
    pub slot: u32,
    pub title: String,
    pub french: String,
    /// Ce que le nom ONT veut dire — voir `Book::glose`.
    #[serde(default)]
    pub glose: Option<String>,
    pub hebrew: Option<String>,
    pub group_id: Option<String>,
    pub empty: bool,
    pub intro: Option<Stub>,
    pub chapters: Vec<Stub>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ModeOutline {
    pub id: String,
    pub title: String,
    /// Le pont de navigation — le mot que le lecteur cherche.
    ///
    /// Les intraduisibles y sont **rendus** : *Torah* devient « la Loi ».
    pub french: String,
    /// Ce que le nom ONT veut dire, quand ça n'est pas déjà le pont.
    ///
    /// Les intraduisibles y **restent en hébreu** : *Torah* devient « la
    /// Fondation », *Berit Hadashah* « la berith renouvelée ». L'écart entre
    /// les deux colonnes est ce que le projet cherche à faire voir.
    #[serde(default)]
    pub glose: Option<String>,
    pub order: u32,
    /// Les conteneurs, portés jusqu'à la table des matières — c'est elle qui
    /// les affiche, donc c'est elle qui doit les recevoir.
    ///
    /// Toujours écrite, même vide — voir `Mode::groups`.
    #[serde(default)]
    pub groups: Vec<Group>,
    pub books: Vec<BookOutline>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CorpusOutline {
    pub id: String,
    pub title: String,
    /// Le pont de navigation — le mot que le lecteur cherche.
    ///
    /// Les intraduisibles y sont **rendus** : *Torah* devient « la Loi ».
    pub french: String,
    /// Ce que le nom ONT veut dire, quand ça n'est pas déjà le pont.
    ///
    /// Les intraduisibles y **restent en hébreu** : *Torah* devient « la
    /// Fondation », *Berit Hadashah* « la berith renouvelée ». L'écart entre
    /// les deux colonnes est ce que le projet cherche à faire voir.
    #[serde(default)]
    pub glose: Option<String>,
    pub order: u32,
    pub modes: Vec<ModeOutline>,
}

/// `dist/corpus.json` — l'arborescence de navigation.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CorpusFile {
    pub schema: u32,
    pub corpora: Vec<CorpusOutline>,
}

/// `dist/glossary.json` — le lexique des intraduisibles.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GlossaryFile {
    pub schema: u32,
    pub entries: Vec<GlossaryEntry>,
}

/// `dist/occurrences.json` — lemme → toutes ses occurrences.
///
/// `BTreeMap` et non `HashMap` : la sortie doit être **déterministe**. Deux
/// exécutions sur le même vault produisent le même octet, donc la même
/// empreinte, donc aucun retéléchargement inutile — et un `diff` entre deux
/// versions ne montre que ce qui a réellement changé.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OccurrencesFile {
    pub schema: u32,
    pub by_lemma: std::collections::BTreeMap<String, Vec<Occurrence>>,
}

/// `dist/search.json` — l'index de recherche.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SearchFile {
    pub schema: u32,
    pub records: Vec<SearchRecord>,
}

/// `dist/daily.json` — le vivier du verset du jour.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DailyFile {
    pub schema: u32,
    pub verses: Vec<DailyVerse>,
}

#[cfg(test)]
mod tests {
    use super::*;

    /// La clé `groups` est écrite même quand elle est vide.
    ///
    /// **Ce test garde une liseuse, pas une structure.** Le code Swift
    /// engendré déclare `public let groups: [Group]` — non optionnel. Un
    /// `Decodable` synthétisé exige alors la clé : l'omettre lèverait
    /// `keyNotFound` sur les cinq modes qui n'ont pas de conteneur, dans les
    /// apps **déjà installées**, et le numéro de schéma du corpus ne bougeant
    /// pas, aucune garde ne s'interposerait.
    ///
    /// Le piège est subtil et mérite d'être nommé ici : une clé **en trop**
    /// est ignorée par les décodeurs, une clé **manquante** sur un champ non
    /// optionnel lève. Éprouver la première ne dit rien de la seconde.
    #[test]
    fn un_mode_sans_conteneur_ecrit_quand_meme_la_cle() {
        let mode = Mode {
            id: "torah".into(),
            title: "Torah".into(),
            french: "la Loi".into(),
            glose: Some("la Fondation".into()),
            order: 1,
            groups: Vec::new(),
            books: Vec::new(),
        };
        let json = serde_json::to_string(&mode).expect("sérialisation");
        assert!(
            json.contains(r#""groups":[]"#),
            "la clé `groups` a disparu du mode : les liseuses livrées ne \
             décoderaient plus ce mode. Obtenu : {json}"
        );
    }

    /// Le tag de l'accentuation sur le fil est `"accentuation"`.
    ///
    /// Il l'est **depuis le schéma 2**, et pas avant : les versions 1.0.1 et
    /// 1.0.2 lisaient `"important"` et lèvent sur ce qu'elles ne connaissent
    /// pas. Ce qui les protège n'est pas ce nom, c'est le numéro de schéma —
    /// `CorpusUpdater` compare avant de télécharger et renonce à tout. Ce test
    /// tient les deux moitiés du contrat ensemble : changer ce mot sans monter
    /// le schéma casserait les lecteurs installés, en silence.
    #[test]
    fn l_accentuation_se_nomme_ainsi_sur_le_fil() {
        let noeud = Inline::Accentuation {
            children: vec![Inline::Text { v: "Jour".into() }],
        };
        let json = serde_json::to_string(&noeud).expect("sérialisation");
        assert!(
            json.contains(r#""t":"accentuation""#),
            "le tag du fil ne correspond plus au schéma 2 — vérifier que le \
             numéro de schéma a bougé avec lui. Obtenu : {json}"
        );
    }
}
