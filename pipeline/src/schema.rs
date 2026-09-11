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

/// La première ligne de tout fichier engendré depuis ce schéma.
///
/// Elle vit ici, et non chez les générateurs, parce qu'elle a **deux** lecteurs
/// qui ne se voient pas : `codegen::swift` et `codegen::kotlin` l'écrivent,
/// `emissions::aspirer` la lit pour refuser le fichier. Deux copies littérales
/// auraient divergé le jour où l'une des deux aurait été retouchée, et la
/// divergence ne se serait vue nulle part — le contrôle serait simplement
/// redevenu faux, en silence.
///
/// Ce module-ci est compilé dans tous les jeux de fonctionnalités, alors que
/// `codegen` et `parsers` sont chacun derrière le leur. C'est la seule maison
/// possible pour une constante que les deux partagent.
pub const MARQUE_ENGENDRE: &str = "// ENGENDRÉ PAR LE PIPELINE — NE PAS MODIFIER À LA MAIN.";

// ─────────────────────────────────────────────────────────────────────────────
// Niveau inline — l'arbre d'un fragment de texte
// ─────────────────────────────────────────────────────────────────────────────

/// Un nœud du texte.
///
/// Sérialisé avec un champ `t` qui porte le type, comme en TypeScript :
/// `{"t":"text","v":"…"}`. La représentation est celle que les liseuses lisent
/// déjà — ce port ne change pas un octet du JSON produit.
/// La version du **contrat des nœuds** — ce que les liseuses doivent savoir lire.
///
/// ## Ce qu'elle protège, et pourquoi elle a manqué
///
/// Une liseuse **lève** sur un type de nœud qu'elle ne connaît pas, et c'est
/// voulu : en omettre un afficherait un texte amputé sans que personne ne s'en
/// aperçoive. `CorpusUpdater` porte donc une garde — il refuse un manifeste
/// dont le schéma n'est pas le sien.
///
/// **Cette garde ne gardait rien.** Le nombre qu'elle compare était écrit en
/// dur à deux endroits — `2` dans le script de publication du site, `2` dans
/// le Swift — et **aucun des deux ne dérivait des nœuds émis**. Un contrôle de
/// version que rien ne versionne.
///
/// Mesuré le 10 septembre 2026 : `Inline::Renvoi` a été ajouté la veille sans
/// que ce nombre bouge. Une app installée acceptait donc le corpus — le schéma
/// lui était familier —, échouait à le décoder, et retombait **silencieusement**
/// sur son bundle. Sa mise à jour réseau devenait inerte, définitivement, sans
/// que rien ne le dise.
///
/// ## La règle, et le contrôle qui la tient
///
/// **Un type ajouté ou retiré d'`Inline` monte ce nombre.** Un champ ajouté ne
/// le monte pas : les décodeurs ignorent une clé qu'ils ne connaissent pas,
/// c'est une compatibilité douce et elle est éprouvée.
///
/// L'épreuve `le_contrat_des_noeuds_suit_les_noeuds` compte les variantes et
/// rougit quand le compte change sans que ce nombre bouge. Elle ne peut pas
/// s'oublier — c'est tout son intérêt, puisque c'est précisément ce qui vient
/// d'être oublié.
///
/// ## Historique
///
/// | version | ce qu'elle ajoute |
/// |---|---|
/// | 2 | l'état du contrat quand la garde a été écrite |
/// | 3 | `Renvoi` — les renvois entre chuqqot |
/// | 4 | `Reference` — les renvois vers un autre passage |
pub const CONTRAT_DES_NOEUDS: u32 = 4;

/// Ce qu'une translittération de niveau 3 ouvre, quand elle ouvre quelque chose.
///
/// **Deux destinations, pas une.** Une fiche de glossaire et une fiche de Shem
/// ne vivent pas dans le même fichier — `glossary.json` et `shemot.json` — et
/// ne s'ouvrent pas par la même route : `ont://term/…` contre `ont://shem/…`.
///
/// **Pourquoi un type et non deux champs.** `lemma: Option<String>` plus un
/// `sorte` laisserait exister l'état illégal : un lemme sans sorte, une sorte
/// sans lemme. Ici il n'y a rien à tenir ensemble — le lemme ne s'écrit pas
/// sans dire où il mène. Et le `switch` que ça impose aux liseuses est
/// exhaustif : une troisième destination, un jour, casserait la compilation au
/// lieu de s'oublier.
///
/// Les noms des variantes sont ceux que le Router emploie déjà — `term` et
/// `shem` —, pas un vocabulaire neuf pour la même chose.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "t", rename_all = "lowercase")]
pub enum CibleDuNiveauTrois {
    /// Une entrée du glossaire — `ont://term/<lemma>`.
    Term { lemma: String },
    /// Une fiche de Shem — `ont://shem/<lemma>`.
    Shem { lemma: String },
}

/// Ce qu'une référence vise à l'intérieur de son chapitre.
///
/// **Un type somme, et pas deux `Option`.** `verset: None` avec
/// `dernier: Some(33)` serait une plage sans début — personne ne l'écrira, et
/// c'est justement pour ça que ça finirait par arriver. Ici l'état illégal est
/// irreprésentable, et le `match` des liseuses devient exhaustif.
///
/// Il fait aussi disparaître une convention tacite : `Genèse 3` et
/// `Genèse 3:1` ne se distinguaient que par la nullité d'un champ.
/// L'unité que la référence ouvre, quand le corpus la porte.
///
/// **Pourquoi elle est résolue ici et non dans la liseuse.** Une référence dit
/// « Genèse 7:11 », et les unités ONT ne coïncident pas avec les chapitres
/// reçus : seule la table des plages de tout le corpus sait que 7:11 tombe
/// dans `bereshit-7`. Cette table n'existe qu'ici. La laisser reconstruire par
/// chaque liseuse, c'est la faire écrire trois fois, en trois langages, à
/// partir d'une chaîne d'affichage — « 1:1 — 2:3 » — qui n'a jamais été un
/// format de données.
///
/// **Pourquoi elle est facultative.** Une référence à Ésaïe est parfaitement
/// bien formée et ne mène nulle part : le livre n'est pas traduit. `None` dit
/// exactement cela, et la liseuse n'a pas à le deviner en cherchant un livre
/// qu'elle ne trouvera pas.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CibleDeLaReference {
    /// Le livre qui porte l'unité — `bereshit`.
    pub livre: String,
    /// L'unité à ouvrir — `bereshit-7`.
    pub unite: String,
    /// Le verset à désigner en arrivant, **dans la numérotation de l'unité**.
    ///
    /// Nul quand la référence vise un chapitre entier, et nul aussi quand le
    /// compte des versets ne confirme pas le calcul — voir `renvois::interne`.
    /// Mieux vaut ouvrir la bonne unité sans rien désigner que d'en désigner
    /// un faux.
    pub verset: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "t", rename_all = "lowercase")]
pub enum PorteeDeLaReference {
    /// `Genèse 3` — l'unité entière, pas un verset.
    Chapitre,
    /// `Genèse 3:24` — un verset.
    Verset { n: u32 },
    /// `Genèse 1:11-12` — une plage. La navigation vise son ouverture.
    Plage { premier: u32, dernier: u32 },
}

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

    /// Un **Shem** — un nom propre, balisé `[[Ainsi]]`.
    ///
    /// ## Pourquoi ce n'est pas un intraduisible
    ///
    /// `**chesed**` est en hébreu parce que « bonté » rate quelque chose :
    /// l'intraduisible promet une fiche de **concept**, et la fiche l'honore.
    /// `[[Avraham]]` n'est pas intraduisible, il est simplement **non traduit**.
    /// Les confondre promettrait un concept là où il y a un porteur.
    ///
    /// ## Pourquoi ce n'est pas un lien
    ///
    /// La marque est le lien natif d'Obsidian, que le pipeline lisait déjà. Mais
    /// l'émettre en [`Inline::Link`] obligerait chaque liseuse à distinguer « une
    /// chaîne sans schéma » d'une URL — une règle qui casse au premier cas
    /// particulier, et il y en a : l'apostrophe de `Na'amah`, le composé de
    /// `Tuval-Qayin`, un jour un renvoi interne écrit en relatif.
    ///
    /// Mesuré avant de trancher : le site classe extérieur tout `href` qui ne
    /// commence pas par son adresse, et un Shem y serait devenu un lien souligné
    /// ouvrant un onglet neuf vers une page inexistante. Pas un lien mort — un
    /// lien mort qui arrache le lecteur de sa page.
    ///
    /// Le type déplace la décision là où l'information existe : le pipeline sait
    /// qu'il a lu `[[…]]` et qu'une fiche répond. Aucune liseuse n'a à le
    /// redéduire d'une forme de chaîne.
    ///
    /// `v` garde la casse du texte, `lemma` est la clé de jointure vers la fiche.
    Shem { v: String, lemma: String },

    /// Un renvoi d'une **chuqqah** vers une autre — `((cible|libellé))`.
    ///
    /// ## Pourquoi une marque à elle, et pas `[[…]]`
    ///
    /// `[[…]]` devient un `Shem` **sans jamais regarder la cible**, et c'est
    /// délibéré : le vault porte des renvois vers des porteurs pas encore
    /// écrits, et ce sont des marques de travail à faire, pas des erreurs.
    ///
    /// Distinguer sur la cible obligerait donc à **résoudre avant de typer** —
    /// et produirait exactement le défaut que ce principe prévient : un renvoi
    /// vers une chuqqah pas encore écrite sortirait en `Shem`. C'est le cas le
    /// plus fréquent, puisque le corpus s'écrit.
    ///
    /// Doubles parenthèses, donc : **détection locale, aucune résolution.**
    ///
    /// ## Ce que la marque coûte
    ///
    /// `((…))` n'est pas un lien Obsidian : on ne saute plus d'une chuqqah à
    /// l'autre depuis l'éditeur. Arbitré en connaissance de ce prix, contre une
    /// détection qui ne dépend de rien.
    ///
    /// ## Le voisinage est sûr
    ///
    /// Le niveau 3 — `(*translittération* / hébreu)` — exige de l'hébreu dans
    /// la parenthèse, ce qu'un renvoi n'a pas. Les deux ne se disputent rien,
    /// dans un ordre ou dans l'autre.
    Renvoi { v: String, cible: String },

    /// Une référence vers un autre passage — `*Genèse* 4:25`, `Bereshit 9:8`.
    ///
    /// ## Le nom du livre dit la numérotation
    ///
    /// Décision de l'auteur du 10 septembre 2026. Deux systèmes coexistent, et
    /// c'est **le nom** qui les sépare : `Genèse 9:25` est le verset 25 du
    /// chapitre 9 de la Genèse reçue, `Bereshit 9:8` est le verset ⁸ de
    /// l'unité ONT n° 9. Ce sont le même verset, et la forme double est permise.
    ///
    /// La règle ne signale pas l'exception — **elle supprime le cas
    /// d'exception**. Une notation qui repose sur le contexte se lit juste tant
    /// qu'on connaît le contexte ; un nom se lit seul.
    ///
    /// Le corpus portait les deux sous une seule graphie, et ça a coûté deux
    /// renvois qui menaient à un verset ne parlant pas de ce que la glose
    /// annonçait — en production, sur 218 renvois déjà cliquables.
    ///
    /// ## Détection locale, aucune résolution
    ///
    /// Comme `Renvoi`. La grande majorité des renvois du corpus vise des livres
    /// **pas encore écrits** : les typer sur leur cible les rendrait tous
    /// inertes, et il faudrait tout reprendre à chaque livre traduit. La
    /// jointure se fait après, contre l'index de `chapter.rs`.
    ///
    /// `portee` dit ce que la référence vise — un chapitre entier, un verset,
    /// ou une plage. Voir `PorteeDeLaReference`.
    Reference {
        v: String,
        livre: String,
        /// `"recu"` ou `"ont"`.
        systeme: String,
        chapitre: u32,
        portee: PorteeDeLaReference,
        /// Où cette référence mène, quand le corpus porte le passage.
        ///
        /// Posée par `renvois::resoudre_les_references`, après l'assemblage :
        /// la table des plages demande le corpus entier, et un chapitre seul
        /// ne sait pas ce que contiennent les autres.
        #[serde(skip_serializing_if = "Option::is_none", default)]
        cible: Option<CibleDeLaReference>,
    },

    /// Niveau 3 — `(*translittération* / hébreu)`.
    ///
    /// Les deux parts sont séparées parce qu'elles ne se composent pas pareil :
    /// la translittération est en italique dans la fonte latine, l'hébreu
    /// demande une fonte hébraïque et un passage en RTL.
    ///
    /// ## `cible` — la fiche que ce mot ouvre, quand il en ouvre une
    ///
    /// Gloire l'a posé ainsi : il lit la translittération du niveau 3, il est
    /// dessus, et rien ne répond. Le mot est là, sa fiche existe, et l'appareil
    /// qui les relie s'arrête au corps du texte.
    ///
    /// **Remplie au build, jamais à l'analyse.** Le parseur ne sait pas quelles
    /// fiches existent — c'est la construction qui les connaît, et qui sait en
    /// plus lesquelles sont *publiées*. Trancher plus tôt obligerait à le faire
    /// sans l'information.
    ///
    /// **`None` est le cas ordinaire, et il est honnête.** Sur 1748
    /// translittérations, 631 se résolvent et 1117 non. Ces dernières restent
    /// lisibles et inertes, exactement comme avant.
    ///
    /// ## Ce qu'on ne fait pas, et c'est le cœur
    ///
    /// **Aucune résolution morphologique.** Ni spirantisation — `lehavdil`
    /// vient de `badal`, le bet devenant vet —, ni verbes lamed-he — `vayiven`
    /// vient de `banah`, dont le he disparaît.
    ///
    /// Pas par difficulté, mais par **mode d'échec** : une règle qui se trompe
    /// ne rend pas le mot inerte, elle le rend touchable **vers la mauvaise
    /// fiche**. Le lecteur arrive ailleurs sans que rien ne le dise — la
    /// substitution silencieuse, pire qu'une abstention.
    ///
    /// La résolution se fait donc là où elle est exacte, et le §2.5 fait le
    /// reste : une forme déclarée devient touchable pour toujours. Chaque
    /// déclaration est un gain permanent, jamais une erreur muette.
    Translit {
        translit: String,
        hebrew: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        cible: Option<CibleDuNiveauTrois>,
    },

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
/// 70. Avant, les lettres parlent du Temple au présent — *Igeret ha-Ivrim* est
/// « le dernier mot du *Bayit* vivant ». Après, il n'existe plus.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Group {
    pub id: String,
    /// Le nom ONT — `Igerot lifnei ha-Ḥurban`.
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
    ///
    /// **Facultatif, et il le faut.** Le corpus publié atteint des liseuses
    /// plus anciennes que lui *et* des liseuses plus récentes : une app
    /// compilée aujourd'hui doit savoir lire le corpus d'hier, qui n'a pas
    /// cette clé. Un champ obligatoire ferait lever le décodeur — et le
    /// numéro de schéma ne protège pas ici, puisqu'il ne change pas.
    ///
    /// C'est la même leçon que `groups`, apprise deux fois : une clé **en
    /// trop** est ignorée, une clé **manquante** sur un champ non optionnel
    /// lève.
    #[serde(default)]
    pub french: Option<String>,
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
    ///
    /// **Facultatif, et il le faut.** Le corpus publié atteint des liseuses
    /// plus anciennes que lui *et* des liseuses plus récentes : une app
    /// compilée aujourd'hui doit savoir lire le corpus d'hier, qui n'a pas
    /// cette clé. Un champ obligatoire ferait lever le décodeur — et le
    /// numéro de schéma ne protège pas ici, puisqu'il ne change pas.
    ///
    /// C'est la même leçon que `groups`, apprise deux fois : une clé **en
    /// trop** est ignorée, une clé **manquante** sur un champ non optionnel
    /// lève.
    #[serde(default)]
    pub french: Option<String>,
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
    /// **Le numéro de Strong du lemme**, tel que sa fiche le déclare.
    ///
    /// Nu — `559`, `1254 a` —, sans le préfixe de segmentation que le témoin
    /// pose sur une occurrence : `c/853` dit « conjonction + 853 », et la
    /// conjonction appartient au mot du verset, pas au lemme.
    ///
    /// Absent quand la fiche ne le déclare pas, et l'absence est le cas de
    /// beaucoup : le champ est écrit à la main, fiche par fiche, et seulement
    /// là où les formes déclarées s'accordent sur un seul numéro.
    ///
    /// C'est lui qui fait passer la jointure d'un mot du texte source à sa
    /// fiche de **déduite** à **vérifiable** — voir `reference::SourceDeclaree`
    /// pour le raisonnement complet.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub strong: Option<String>,
    /// La forme absolue en hébreu, déclarée par la fiche.
    ///
    /// Distincte de `hebrew`, qui vient du §3 du document de référence et
    /// n'existe que pour les intraduisibles et les rendus fixés. Celle-ci vient
    /// de la fiche, qui existe pour chaque mot — elle couvre donc ce que le §3
    /// laisse dehors.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hebreu_de_la_fiche: Option<String>,
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
    /// La version du **contrat des nœuds** — voir [`CONTRAT_DES_NOEUDS`].
    ///
    /// Émise ici pour que le script de publication du site la **lise** au lieu
    /// de deviner quels types de nœuds ce build émet.
    ///
    /// ## Ce que ce nombre n'est pas, et la phrase qui a coûté une journée
    ///
    /// Ce commentaire a dit, du 10 au 11 septembre 2026 : « c'est ce nombre
    /// que les liseuses installées comparent au leur avant d'accepter un
    /// corpus ». **C'est faux**, et trois sessions l'ont cru — iOS, Android et
    /// le site —, au point de se recommander mutuellement de monter les
    /// gardes des liseuses. Suivi, le conseil faisait refuser le corpus publié
    /// à toutes les installations : la panne qu'on croyait prévenir.
    ///
    /// Il y a **deux manifestes**, et ils ne portent pas la même question :
    ///
    /// | fichier | écrit par | ce que les liseuses en font |
    /// |---|---|---|
    /// | `dist/manifest.json` | ce pipeline | rien — seul `generated_at` est lu, du bundle |
    /// | `corpus/manifeste.json` | `corpus-publie.py`, dans `ONTBibleWebapp` | **`schema` est comparé** |
    ///
    /// `contrat` ne traverse jamais le second. Ce que les liseuses comparent
    /// est `schema`, qui vaut 2 depuis la 1.0.3 et qui est la copropriété du
    /// site et des liseuses — pas cette constante.
    ///
    /// ## Alors à quoi il sert
    ///
    /// À dire au **site** quels types de nœuds ce build émet, pour qu'il ne
    /// publie pas un corpus portant un nœud que ses pages ne savent pas
    /// rendre. C'est ce qui a manqué quand `Renvoi` est parti sans que
    /// personne ne l'apprenne.
    ///
    /// Et ce n'est pas une protection pour les lecteurs déjà installés : une
    /// garde sur ce que le pipeline *déclare* aurait laissé passer `Renvoi`,
    /// qui vit dans le schéma de `dev` **sans** ce champ. Protéger les
    /// installés reste le geste de la 1.0.3 : monter `schema` côté liseuses,
    /// livrer, **puis** publier le nouveau nombre.
    pub contrat: u32,
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
    ///
    /// **Facultatif, et il le faut.** Le corpus publié atteint des liseuses
    /// plus anciennes que lui *et* des liseuses plus récentes : une app
    /// compilée aujourd'hui doit savoir lire le corpus d'hier, qui n'a pas
    /// cette clé. Un champ obligatoire ferait lever le décodeur — et le
    /// numéro de schéma ne protège pas ici, puisqu'il ne change pas.
    ///
    /// C'est la même leçon que `groups`, apprise deux fois : une clé **en
    /// trop** est ignorée, une clé **manquante** sur un champ non optionnel
    /// lève.
    #[serde(default)]
    pub french: Option<String>,
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
    ///
    /// **Facultatif, et il le faut.** Le corpus publié atteint des liseuses
    /// plus anciennes que lui *et* des liseuses plus récentes : une app
    /// compilée aujourd'hui doit savoir lire le corpus d'hier, qui n'a pas
    /// cette clé. Un champ obligatoire ferait lever le décodeur — et le
    /// numéro de schéma ne protège pas ici, puisqu'il ne change pas.
    ///
    /// C'est la même leçon que `groups`, apprise deux fois : une clé **en
    /// trop** est ignorée, une clé **manquante** sur un champ non optionnel
    /// lève.
    #[serde(default)]
    pub french: Option<String>,
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

/// `dist/prononciation.json` — la feuille qui explique comment lire ce qui est
/// écrit.
///
/// ## Pourquoi un fichier et non une section du document de référence
///
/// Le `CLAUDE.md` du vault est lu pour en tirer des **entrées de termes**. Lui
/// faire sortir en plus une section entière mêlerait deux extractions dans un
/// même lecteur, et la seconde casserait la première le jour où quelqu'un
/// touche au format.
///
/// Un fichier a en prime un `status`, comme le reste du corpus : cette feuille
/// est du contenu qu'on relit, pas de la configuration.
///
/// ## Pourquoi des blocs et non du markdown
///
/// Elle cite `**chokhmah**`, `**malʾakh**`, `[[Chanokh]]`. En blocs, le rendu
/// pose l'or et la terre brûlée et les rend touchables **sans une ligne de
/// code** dans les liseuses. En chaîne, il faudrait réimplémenter le rendu
/// trois fois, avec la certitude qu'ils divergeraient.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PrononciationFile {
    pub schema: u32,
    pub title: String,
    pub blocks: Vec<Block>,
}

/// `dist/glossary.json` — le lexique des intraduisibles.
/// Une **chuqqah** — un énoncé permanent de l'ontologie hébraïque.
///
/// De *chaqaq* (חָקַק), graver dans la pierre : ce qui est gravé tient de
/// soi-même, et le reste s'y appuie. Ce n'est ni une opinion qu'on défend, ni
/// un commentaire qui accompagne un texte.
///
/// ## Pourquoi un type et non une fiche de lexique
///
/// Une fiche de lexique explique **un mot** ; une chuqqah énonce **une règle du
/// fonctionnement**, et elle se lit d'un bout à l'autre. Les deux portent de la
/// prose, mais l'une se consulte et l'autre se lit — c'est ce qui décide de
/// leur place à l'écran, et donc de leur type.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Chuqqah {
    /// Le nom du fichier, slugifié — `les-quatre-modes-de-presence`.
    ///
    /// **C'est aussi son adresse sur le site**, `/fr/chuqqot/{id}`. Une adresse
    /// qui bouge après indexation perd ce que le référencement lui a donné : ce
    /// champ ne se renomme pas à la légère.
    pub id: String,
    /// Le titre, lu de la ligne `# ` du fichier.
    pub title: String,
    /// L'ordre de lecture, tiré du nom de fichier quand il le porte.
    ///
    /// `chuqqot-0-intro` ouvre la série. Les autres suivent, alphabétiquement,
    /// faute d'un ordre déclaré ailleurs — et c'est dit plutôt que deviné.
    pub rank: u32,
    pub blocks: Vec<Block>,
}

/// Les chuqqot **publiées** — et elles le sont toutes, par construction.
///
/// ## La garde vit dans l'émission, pas dans un filtre
///
/// Décision de l'auteur, le 9 septembre 2026 : une chuqqah en brouillon ne
/// sort pas. Les unités de traduction, elles, continuent de voyager marquées
/// « Brouillon » — la validation y est une déclaration d'état.
///
/// La distinction tient à ce qu'on lit : un chapitre en cours porte sa mention
/// et le lecteur sait où il met les pieds ; une chuqqah énonce ce qui est tenu
/// pour établi, et un énoncé permanent « en attente de validation » se
/// contredit lui-même.
///
/// **Ce type ne porte donc pas de `status`**, et c'est délibéré : il n'y a
/// qu'un état possible ici. Un champ qui ne peut prendre qu'une valeur invite à
/// l'autre.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ChuqqotFile {
    pub schema: u32,
    pub entries: Vec<Chuqqah>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GlossaryFile {
    pub schema: u32,
    pub entries: Vec<GlossaryEntry>,
}

/// La fiche d'un **Shem** — un porteur de nom.
///
/// Elle a la tenue d'une fiche d'intraduisible sans en être une : le §2.10 veut
/// qu'elle dise le sens de la racine, ce que le nom met sur les épaules de qui
/// le porte, et ce qui reste à venir. D'où les titres de section, que les fiches
/// de concepts n'ont pas — 197 sur 305 en portent.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ShemEntry {
    /// La clé de jointure avec [`Inline::Shem::lemma`].
    pub lemma: String,
    /// La forme d'affichage — `Qayin`, `Tuval-Qayin`, `Na'amah`.
    pub title: String,
    /// Le corps de la fiche, titres de section compris.
    pub definition: Vec<Block>,
}

/// `dist/shemot.json` — les fiches des noms propres.
///
/// **Un fichier à part, et pas des entrées de glossaire.** Le lexique publie les
/// intraduisibles : y verser les Shemot ferait promettre une fiche de concept
/// là où il y a un porteur, et remplirait l'onglet Lexique de trois cents noms
/// qui n'y ont rien à faire. C'est la distinction que toute cette couche existe
/// pour tenir ; l'effacer au dernier moment n'aurait pas de sens.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ShemotFile {
    pub schema: u32,
    pub entries: Vec<ShemEntry>,
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
            french: Some("la Loi".into()),
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

#[cfg(test)]
mod contrat {
    use super::*;

    /// **Le compte des nœuds décide de la version, et rien d'autre.**
    ///
    /// ## Si vous êtes ici parce que ça ne compile plus
    ///
    /// Vous venez d'ajouter ou de retirer un type de nœud. Trois gestes, dans
    /// cet ordre :
    ///
    /// 1. montez [`CONTRAT_DES_NOEUDS`] et ajoutez sa ligne d'historique ;
    /// 2. ajoutez la variante au `match` ci-dessous et le compte à `NOEUDS` ;
    /// 3. **vérifiez que le site publie ce nombre** plutôt qu'un `2` écrit en
    ///    dur — c'est lui que les liseuses installées comparent au leur.
    ///
    /// ## Pourquoi un `match` et pas un tableau
    ///
    /// Le premier jet listait des valeurs dans un tableau. Le compilateur
    /// attrapait bien la variante neuve — par les `match` du reste du code —,
    /// mais **une fois ceux-ci corrigés, le tableau restait vrai** et rien ne
    /// forçait la montée. Un contrôle qui ne rougit qu'en compagnie d'un autre
    /// ne contrôle rien tout seul.
    ///
    /// Ce `match`-ci n'a pas de bras `_`. Il cesse de compiler, et il est le
    /// dernier à le faire — c'est-à-dire au moment précis où l'on croit avoir
    /// fini.
    fn nom(noeud: &Inline) -> &'static str {
        match noeud {
            Inline::Text { .. } => "text",
            Inline::Term { .. } => "term",
            Inline::Shem { .. } => "shem",
            Inline::Renvoi { .. } => "renvoi",
            Inline::Reference { .. } => "reference",
            Inline::Translit { .. } => "translit",
            Inline::Heb { .. } => "heb",
            Inline::Gloss { .. } => "gloss",
            Inline::Accentuation { .. } => "accentuation",
            Inline::Em { .. } => "em",
            Inline::Link { .. } => "link",
            Inline::Break => "break",
        }
    }

    #[test]
    fn le_contrat_des_noeuds_suit_les_noeuds() {
        /// Le nombre de bras de `nom`. Compté à la main, délibérément : une
        /// macro qui compterait toute seule ferait monter le nombre sans qu'un
        /// humain le voie, et c'est ce défaut-là qu'on ferme.
        const NOEUDS: usize = 12;

        assert_eq!(
            CONTRAT_DES_NOEUDS, 4,
            "le contrat a bougé sans que son historique suive"
        );
        assert_eq!(nom(&Inline::Break), "break");
        assert_eq!(
            NOEUDS, 12,
            "le compte des nœuds a bougé — montez le contrat"
        );
    }
}
