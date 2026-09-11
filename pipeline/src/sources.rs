//! La couche des langues sources — `dist/sources/`.
//!
//! Le vault porte, sous `sources/`, le texte de chaque livre dans sa langue :
//! l'hébreu de la Kenesset, deux témoins grecs pour la Berit Hadashah, le
//! guèze de *Chanokh*, le latin du *Chazon Ezra*. Ce module les joint aux
//! unités ONT et les émet pour la liseuse.
//!
//! ```text
//! dist/sources/manifeste.json          les témoins, leurs licences, les empreintes
//! dist/sources/<témoin>/<livre>.json   un fichier par livre et par témoin
//! ```
//!
//! ## La jointure, et pourquoi elle est ici plutôt qu'à l'exécution
//!
//! Les fichiers du vault sont classés **par référence biblique** — `Gen.3.1` —
//! parce que c'est la clé native des éditions critiques. La liseuse, elle,
//! numérote **par unité ONT**, en repartant de ¹ à chaque **parashah** (§2.2).
//! Les deux ne se recouvrent pas, et faire la jointure à l'exécution
//! obligerait chaque plateforme à la refaire — trois fois, avec trois façons
//! de se tromper.
//!
//! Elle est donc faite ici, une fois. Le sous-titre de chaque unité porte la
//! plage — `*(Genèse / בְּרֵאשִׁית 9:18-29)*` — et c'est de là qu'elle se lit.
//!
//! ## `n` n'est pas une clé
//!
//! Le tableau des versets est **positionnel** : la liseuse parcourt ses
//! propres versets dans l'ordre et prend le nième. Le champ `n` est le numéro
//! **à afficher**, et il peut se répéter dans une même unité — *Bereshit* 7
//! couvre deux chapitres bibliques et porte donc deux fois un verset « 1 »,
//! comme le §2.2 le prescrit.
//!
//! Une implémentation qui indexerait par `n` écraserait vingt-deux versets sur
//! cette unité-là et marcherait partout ailleurs. C'est pourquoi `n` est émis :
//! il sert de ==garde== côté client, non de clé.
//!
//! ## Ce que ce module n'émet pas, et c'est délibéré
//!
//! **Aucune analyse morphologique.** Les étiquettes de MorphGNT sont sous
//! CC BY-SA, et celles d'OSHB sous CC BY. Les tenir hors de `dist/` règle la
//! question ==par construction== plutôt que par discipline : il n'y a rien à
//! cloisonner dans un fichier qui ne les porte pas. Le jour où la liseuse
//! voudra les lemmes, un fichier frère les portera, et la question se posera
//! là, isolée.

use crate::schema::{Block, Chapter, CibleDuNiveauTrois, Inline};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, HashMap};
use std::fs;
use std::path::Path;

/// Le dossier des sources dans le vault.
pub const SOURCES: &str = "sources";

// ───────────────────────── ce qu'on lit dans le vault ─────────────────────

#[derive(Debug, Deserialize)]
struct ManifesteVault {
    sources: BTreeMap<String, TemoinVault>,
}

#[derive(Debug, Deserialize)]
struct TemoinVault {
    nom: String,
    langue: String,
    attribution: String,
    #[serde(default)]
    temoin: Option<String>,
    livres: BTreeMap<String, LivreVault>,
}

#[derive(Debug, Deserialize)]
struct LivreVault {
    // `ont` est dans le manifeste du vault mais ne sert pas ici : la
    // correspondance numéro → slug vient du squelette, qui couvre aussi les
    // livres sans témoin. Le champ reste déclaré pour que la lecture échoue
    // si le vault cesse de l'écrire.
    #[allow(dead_code)]
    ont: u32,
    slug: String,
}

/// Une ligne de `<témoin>/<livre>-apparat.jsonl`.
///
/// ## Pourquoi ce fichier ne s'appelle pas « apparat » en aval
///
/// « Apparat critique » fait attendre des ==manuscrits== — le Sinaiticus, le
/// Vaticanus. Celui du SBLGNT n'en montre aucun : il compare **quatre
/// éditions imprimées** entre 1857 et 2012. Le mot tromperait le lecteur, et
/// il tromperait aussi la session qui lira ce code dans six mois. Le champ
/// émis s'appelle donc `editions` — il dit ce que le fichier compare, et rien
/// d'autre. Décision de la session iOS, et elle va plus loin que la mienne.
#[derive(Debug, Deserialize)]
struct EntreeApparat {
    c: u32,
    v: u32,
    lecon: String,
    editions: Vec<String>,
    #[serde(default)]
    crochets: Vec<String>,
    variantes: Vec<VarianteApparat>,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct VarianteApparat {
    pub t: String,
    pub editions: Vec<String>,
    /// Les éditions qui impriment la leçon ==tout en la tenant pour douteuse==
    /// — la notation ⟦ ⟧ de Westcott-Hort. Séparé d'`editions` parce qu'une
    /// distinction aplatie à l'émission serait irrécupérable à l'écran, et
    /// qu'elle tombe sur les passages les plus connus : la sueur de sang de
    /// Luc 22, la finale longue de Marc, la femme adultère.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub crochets: Vec<String>,
}

/// Ce qui est émis pour une unité : les endroits où les éditeurs divergent.
#[derive(Debug, Clone, Serialize)]
pub struct DivergencePubliee {
    /// La **position** dans le tableau des versets de l'unité. C'est la clé.
    pub i: usize,
    /// Le numéro affiché, pour que la liseuse vérifie qu'elle n'a pas glissé.
    /// Il se répète dans une unité à deux chapitres — voir l'en-tête.
    pub n: u32,
    pub lecon: String,
    pub editions: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub crochets: Vec<String>,
    pub variantes: Vec<VarianteApparat>,
}

#[derive(Debug, Clone, Serialize)]
pub struct EditionsComparees {
    pub temoin: String,
    pub unites: BTreeMap<String, Vec<DivergencePubliee>>,
}

/// Une ligne de `<témoin>/<livre>.jsonl`.
#[derive(Debug, Deserialize)]
struct VersetSource {
    c: u32,
    v: u32,
    w: Vec<MotSource>,
}

#[derive(Debug, Deserialize)]
struct MotSource {
    t: String,
    /// L'étiquetage **OSHB**, quand le témoin le porte.
    ///
    /// Il était lu et jeté : seul `t` survivait, et le verset sortait joint en
    /// une seule chaîne. C'est ce qui rendait impossible la seule chose que le
    /// lecteur demande devant un verset hébreu — toucher **un mot**.
    #[serde(default)]
    oshb: Option<OshbSource>,
}

#[derive(Debug, Deserialize)]
struct OshbSource {
    /// Le numéro de Strong, éventuellement préfixé — « 121 », « b/7225 ».
    lem: String,
    /// Le code morphologique — « HNp », « HVqp3ms ».
    morph: String,
}

// ───────────────────────────── ce qu'on émet ──────────────────────────────

#[derive(Debug, Clone, Serialize)]
pub struct ManifesteSources {
    pub schema: u32,
    /// **De quand date cette génération**, au même format et par la même
    /// fonction que le manifeste du corpus.
    ///
    /// ## Ce qui manquait, et ce que ça bloquait
    ///
    /// Le manifeste des sources ne portait aucune date. Relevé par la session
    /// macOS en ouvrant le chantier de `SourcesUpdater` : ses deux gardes
    /// d'âge — refuser une génération plus vieille, purger au lancement ce qui
    /// est antérieur au bundle — sont **indélivrables** sans estampille.
    ///
    /// Le corpus en portait une depuis toujours ; les sources sont nées sans,
    /// et personne ne l'a vu tant que personne n'a eu à comparer deux
    /// générations.
    ///
    /// ## Vide plutôt que fausse
    ///
    /// `config::genere` rend une chaîne **vide** quand `ONT_GENERE` manque ou
    /// n'a pas la forme exacte. C'est la doctrine du corpus, et elle vaut ici
    /// pour la même raison : les liseuses comparent ces chaînes, et une date
    /// voisine mais mal formée s'ordonne n'importe comment. Un dossier figé se
    /// voit et se répare ; un dossier silencieusement remplacé par du plus
    /// ancien ne se voit pas.
    ///
    /// ## Une seule estampille pour la génération entière
    ///
    /// Pas une par témoin. L'invariant que la session macOS a posé et que
    /// j'adopte : **une génération = un dossier atomique = une estampille ; le
    /// bundle est le plancher ; sous le plancher on purge, on ne fusionne
    /// jamais.**
    ///
    /// Il dissout la crainte que j'avais formulée — une génération plus neuve
    /// pour le grec et plus vieille pour l'hébreu. Elle ne peut pas exister si
    /// l'on ne bascule jamais un témoin seul.
    pub genere: String,
    pub temoins: BTreeMap<String, TemoinPublie>,
    pub livres: BTreeMap<String, LivrePublie>,
}

#[derive(Debug, Clone, Serialize)]
pub struct TemoinPublie {
    pub nom: String,
    pub langue: String,
    /// La phrase exacte à afficher sous le texte. Jamais recomposée par l'app.
    pub attribution: String,
    /// Ce que ce témoin est dans la chaîne — second degré, traduction, etc.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub degre: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct LivrePublie {
    /// Vide quand aucun témoin n'existe — et alors `transmission` doit parler.
    pub temoins: BTreeMap<String, FichierPublie>,
    /// Ce que le lecteur lit quand il n'y a pas de source. Écrit dans le
    /// vault, jamais composé par l'app.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub transmission: Option<String>,
    /// Là où les **éditions imprimées** divergent — jamais les manuscrits.
    /// À côté de `temoins`, jamais dedans : `temoins` répond à « que porte ce
    /// témoin ici », celui-ci à « où les éditeurs se sont-ils séparés ». Deux
    /// questions, deux fichiers ; les mêler ferait passer un désaccord
    /// d'éditeur pour un témoin textuel.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub editions: Option<FichierPublie>,
    /// `temoin` — le texte est perdu ; `fichier` — il existe mais aucune
    /// édition n'en est réutilisable. Quatre des six livres sans source
    /// recevront la leur : un rendu qui dirait « jamais » les trahirait.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cause: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct FichierPublie {
    pub chemin: String,
    pub octets: usize,
    pub sha256: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct LivreSources {
    pub temoin: String,
    pub unites: BTreeMap<String, Vec<VersetPublie>>,
}

#[derive(Debug, Clone, Serialize)]
pub struct VersetPublie {
    /// Le numéro **à afficher**. Pas une clé — voir l'en-tête du module.
    pub n: u32,
    pub t: String,
    /// Le verset **mot à mot**, quand le témoin est étiqueté.
    ///
    /// `t` reste, et ce n'est pas une redondance : il porte la ponctuation et
    /// les espaces que la liste de mots perd, et c'est lui qu'on copie ou
    /// qu'on lit à voix haute. La liste, elle, est ce qu'on touche.
    ///
    /// Vide quand le témoin n'étiquette pas — le guèze de Dillmann, par
    /// exemple. La liseuse rend alors le verset sans mots touchables, ce qui
    /// est exact : il n'y a rien à ouvrir.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub mots: Vec<MotPublie>,
}

/// Un mot du texte source, et la fiche qu'il ouvre quand il en ouvre une.
#[derive(Debug, Clone, Serialize)]
pub struct MotPublie {
    /// La forme telle qu'elle est écrite, voyelles et cantillation comprises.
    pub t: String,
    /// Le numéro de Strong, tel que le témoin l'écrit.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lem: Option<String>,
    /// Le code morphologique du témoin.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub morph: Option<String>,
    /// La translittération de ce mot, **telle que le vault l'a écrite**.
    ///
    /// ## Elle n'est pas calculée, et elle ne le sera pas
    ///
    /// Translittérer l'hébreu vocalisé est une affaire de règles — shewa mobile
    /// ou quiescent, daguesh fort ou doux, spirantisation des *begadkefat* — et
    /// chacune a ses exceptions. Une règle qui se trompe ici ne rend pas le mot
    /// muet : elle **affiche** une forme fausse, sous le mot, avec l'aplomb
    /// d'un fait. Le lecteur n'a rien pour la démentir.
    ///
    /// Le vault, lui, en a déjà écrit un millier à la main dans ses nœuds
    /// `translit` du niveau 3. On les **récolte**, on ne les invente pas — voir
    /// [`Translitterations`].
    ///
    /// ## Absente est l'état ordinaire
    ///
    /// Deux mots sur trois n'en ont pas, et l'absence doit rester distincte
    /// d'une chaîne vide : la liseuse ne dessine alors rien sous le mot, au
    /// lieu de dessiner une ligne vide qui ferait croire à une lacune du
    /// vault.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub translit: Option<String>,
    /// La fiche ONT que ce mot ouvre — absente quand aucune ne lui correspond.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cible: Option<CibleDuNiveauTrois>,
}

// ─────────────────────── la jointure d'un mot à sa fiche ───────────────────

/// **Ce qui relie un mot hébreu à une fiche du glossaire.**
///
/// ## Pourquoi pas le numéro de Strong, qui serait pourtant la bonne clé
///
/// Parce que les fiches ONT n'en portent pas. Elles portent leur forme
/// hébraïque — `adam` → `אָדָם` —, et c'est tout ce qu'on a. Inventer une table
/// Strong → lemme reviendrait à introduire une donnée que personne ne
/// maintient, pour un gain qu'on ne saurait pas vérifier.
///
/// ## Deux épreuves, dans cet ordre, et la seconde peut refuser
///
/// 1. **La forme vocalisée**, cantillation ôtée. `אָדָ֥ם` devient `אָדָם` et
///    tombe exactement sur la fiche. Aucune ambiguïté possible : mesuré sur la
///    Genèse, 548 mots, zéro collision.
/// 2. **Le squelette consonantique**, voyelles ôtées en plus. C'est lui qui
///    ramasse les formes fléchies — `בְּרֹ֤א`, `בָּרָ֣א` et `בָּרָ֥א` mènent tous
///    à `bara`. Il porte 1 355 mots au lieu de 548.
///
/// La seconde épreuve **coûte l'ambiguïté**, et le corpus la nomme : trois
/// squelettes sur cent trente en portent deux — `דבר` est *davar* et *dibber*,
/// `קדש` est *qadash* et *qodesh*, `ראה` est *roeh* et *raah*. Une voyelle les
/// sépare, et le squelette l'a perdue.
///
/// ## Une quatrième ambiguïté, et elle n'est pas encore arrivée
///
/// La session des langues sources l'a relevée le 11 septembre 2026 : `אֵת`
/// (Strong 853, la particule d'accusatif) et `אֶת` (854, la préposition
/// « avec ») **partagent leur squelette**. Une voyelle les sépare.
///
/// Aujourd'hui aucune fiche ne porte ce squelette, donc rien n'est mal lié.
/// Mais `אֵת` est **le mot le plus fréquent du corpus sans fiche** — 328
/// occurrences sur Genèse 1-19 —, et c'est celui que tout le monde désigne
/// comme le plus rentable à écrire. Le jour où il en aura une, les 15
/// occurrences de `אֶת` ouvriront la sienne, et personne ne le verra.
///
/// **Ce qui a été essayé et écarté** : refuser tout squelette que le témoin
/// voit porter plusieurs numéros de Strong. Mesuré, ça retire 187 jointures
/// sur 478 — et à tort, parce que `אדם` porte 120 (l'humain) et 121 (Adam)
/// qui sont légitimement la même fiche. Une garde qui refuse un tiers du juste
/// pour attraper quinze fautes n'est pas une garde, c'est un renoncement.
///
/// Le vrai remède est ailleurs et il est simple : **que la fiche porte son
/// propre numéro de Strong**, écrit dans le vault à côté de son hébreu. La
/// jointure devient alors exacte et vérifiable, au lieu d'être déduite. C'est
/// une question de convention de vault, posée à son auteur.
///
/// **Ces trois-là ne mènent nulle part.** C'est la règle que le niveau 3 a déjà
/// payée : une jointure qui se trompe ne rend pas le mot inerte, elle le rend
/// touchable **vers la mauvaise fiche** — et le lecteur ne peut pas le voir. Un
/// mot sans fiche se lit comme un mot sans fiche ; un mot qui ouvre la fiche
/// d'un autre se lit comme la vérité.
pub struct LiaisonDesMots {
    /// **Le numéro de Strong déclaré par la fiche**, et c'est la seule épreuve
    /// vérifiable des trois.
    ///
    /// Les deux autres déduisent : elles rapprochent deux formes hébraïques et
    /// pallient ce que la vocalisation perd. Celle-ci compare ce que la fiche
    /// **dit** à ce que le témoin **dit** — deux affirmations, pas deux
    /// apparences.
    ///
    /// D'où sa place en tête : là où elle répond, les autres n'ont pas à
    /// deviner. Et là où elle se trompe, le témoin la contredit — un squelette
    /// qui se trompe, lui, est silencieux.
    strongs: HashMap<String, CibleDuNiveauTrois>,
    /// Le chemin inverse : le lemme d'une fiche → le numéro qu'elle déclare.
    ///
    /// Sert au veto, jamais à joindre. Voir `cible`.
    strong_de: HashMap<String, String>,
    /// **Le numéro qu'une fiche ne déclare pas, mais que le témoin lui donne.**
    ///
    /// Quand une fiche porte `אֵל` et que le témoin n'attribue qu'un seul
    /// numéro à cette forme exacte, ce numéro **est** celui de la fiche — la
    /// chaîne est attestée de bout en bout, rien n'est supposé.
    ///
    /// Ça ne sert pas à joindre davantage : ça sert à **refuser**. Sans lui,
    /// `אֶל` la préposition ouvrait la fiche de `ʾEl` le nom divin, quatre-vingt-
    /// dix fois, parce que leur squelette est le même et qu'aucune des deux ne
    /// déclarait de numéro.
    ///
    /// Rempli par `apprendre_du_temoin`, une fois par livre.
    strong_atteste: HashMap<String, String>,
    vocalisees: HashMap<String, CibleDuNiveauTrois>,
    /// Squelette → fiche, **seulement quand il n'en désigne qu'une**.
    consonantiques: HashMap<String, CibleDuNiveauTrois>,
}

/// Ce qu'une fiche déclare d'elle-même, pour la jointure.
pub struct FichePourLaJointure<'a> {
    pub lemme: &'a str,
    /// L'hébreu du §3, quand le terme y a une entrée.
    pub hebreu: Option<&'a str>,
    /// Le numéro de Strong que la fiche déclare — `559`, `1254 a`.
    pub strong: Option<&'a str>,
}

impl LiaisonDesMots {
    pub fn nouvelle<'a>(fiches: impl IntoIterator<Item = FichePourLaJointure<'a>>) -> Self {
        let mut strongs = HashMap::new();
        let mut strong_de = HashMap::new();
        let mut vocalisees = HashMap::new();
        let mut par_squelette: HashMap<String, Vec<String>> = HashMap::new();
        for fiche in fiches {
            let lemme = fiche.lemme;
            if let Some(strong) = fiche.strong {
                let nu = numero_nu(strong);
                strong_de.insert(lemme.to_string(), nu.clone());
                strongs.insert(
                    nu,
                    CibleDuNiveauTrois::Term {
                        lemma: lemme.to_string(),
                    },
                );
            }
            let Some(hebreu) = fiche.hebreu else { continue };
            let vocalisee = sans_cantillation(hebreu);
            if vocalisee.is_empty() {
                continue;
            }
            vocalisees.insert(
                vocalisee.clone(),
                CibleDuNiveauTrois::Term {
                    lemma: lemme.to_string(),
                },
            );
            par_squelette
                .entry(consonnes(&vocalisee))
                .or_default()
                .push(lemme.to_string());
        }
        let consonantiques = par_squelette
            .into_iter()
            .filter_map(|(squelette, mut lemmes)| {
                lemmes.sort();
                lemmes.dedup();
                // **Un seul prétendant, sinon rien.** Voir l'en-tête du type.
                (lemmes.len() == 1).then(|| {
                    (
                        squelette,
                        CibleDuNiveauTrois::Term {
                            lemma: lemmes.remove(0),
                        },
                    )
                })
            })
            .collect();
        Self {
            strongs,
            strong_de,
            strong_atteste: HashMap::new(),
            vocalisees,
            consonantiques,
        }
    }

    /// **Fait dire au témoin le numéro que la fiche tait.**
    ///
    /// Pour chaque forme hébraïque qu'une fiche porte, on regarde quel numéro
    /// le témoin donne à cette forme **exacte**, vocalisation comprise. S'il
    /// n'en donne qu'un, il est attesté et sert de veto ; s'il en donne
    /// plusieurs, on ne conclut pas.
    ///
    /// Appelée une fois par livre, avant la jointure de ses mots.
    fn apprendre_du_temoin(&mut self, mots: impl IntoIterator<Item = (String, String)>) {
        let mut vus: HashMap<String, Option<String>> = HashMap::new();
        for (forme, lem) in mots {
            let f = sans_cantillation(&forme);
            if !self.vocalisees.contains_key(&f) {
                continue;
            }
            let n = numero_nu(&lem);
            match vus.get(&f) {
                None => {
                    vus.insert(f, Some(n));
                }
                Some(Some(deja)) if *deja != n => {
                    vus.insert(f, None);
                }
                _ => {}
            }
        }
        for (forme, numero) in vus {
            let Some(numero) = numero else { continue };
            if let Some(CibleDuNiveauTrois::Term { lemma }) = self.vocalisees.get(&forme) {
                // Ne recouvre jamais ce que la fiche déclare elle-même.
                self.strong_atteste
                    .entry(lemma.clone())
                    .or_insert_with(|| numero.clone());
            }
        }
    }

    fn cible(&self, mot: &str, lem: Option<&str>) -> Option<CibleDuNiveauTrois> {
        let numero = lem.map(numero_nu);

        // **Le numéro d'abord**, parce qu'il est le seul vérifiable.
        if let Some(c) = numero.as_ref().and_then(|n| self.strongs.get(n)) {
            return Some(c.clone());
        }

        let vocalisee = sans_cantillation(mot);
        let par_la_forme = self
            .vocalisees
            .get(&vocalisee)
            .or_else(|| self.consonantiques.get(&consonnes(&vocalisee)))
            .cloned()?;

        // **Et le numéro a aussi un droit de veto.**
        //
        // C'est là qu'il rapporte le plus, et ce n'est pas là qu'on l'attend.
        // Mesuré à l'écran au premier build qui l'employait :
        //
        //   - `shem` déclare `8034`, « le nom » — et soixante-cinq mots
        //     portant `8035`, qui est *Shem fils de Noach*, s'y joignaient par
        //     la forme ;
        //   - `אֶל` (413, la préposition « vers ») joignait la fiche `el`
        //     quatre-vingt-dix fois.
        //
        // Les deux formes sont identiques, et seule la fonction du mot les
        // sépare. Aucune normalisation de l'hébreu ne peut le voir — c'est
        // précisément ce que « un squelette qui se trompe est silencieux »
        // décrit.
        //
        // Donc : quand la fiche dit son numéro **et** que le témoin en dit un
        // autre, on ne joint pas. Deux affirmations qui se contredisent ne
        // valent pas mieux qu'une absence ; elles valent moins, parce qu'une
        // absence se voit.
        //
        // Une fiche qui ne déclare rien ne peut rien contredire : la jointure
        // par la forme passe alors comme avant, avec sa part de risque, et
        // c'est un argument de plus pour écrire la Source partout.
        if let (Some(n), CibleDuNiveauTrois::Term { lemma }) = (&numero, &par_la_forme) {
            let declare = self
                .strong_de
                .get(lemma)
                .or_else(|| self.strong_atteste.get(lemma));
            if let Some(declare) = declare {
                if declare != n {
                    return None;
                }
            }
        }
        Some(par_la_forme)
    }
}

/// Le numéro de Strong **nu**, sans le préfixe de segmentation du témoin.
///
/// Le WLC écrit `c/853` — conjonction plus 853 —, `d/776`, `b/7225`. Le
/// préfixe appartient à **l'occurrence** : il dit qu'un waw ou un article a
/// été soudé devant le mot dans ce verset-là. Le lemme, lui, est le nombre.
///
/// La lettre qui suit, en revanche, reste : `1254 a` et `1254 b` sont deux
/// mots que Strong distingue, et les confondre rouvrirait le défaut qu'on
/// ferme.
fn numero_nu(lem: &str) -> String {
    lem.rsplit('/').next().unwrap_or(lem).trim().to_string()
}

/// Ôte les signes de cantillation et le maqaf, garde les voyelles.
///
/// La cantillation est une notation **musicale** : elle dit comment chanter le
/// verset, jamais quel mot c'est. Deux occurrences du même mot en portent des
/// différentes selon leur place dans la phrase — c'est ce qui fait que `אֱלֹהִ֑ים`
/// et `אֱלֹהִ֖ים` sont le même mot et ne se comparent pas tels quels.
fn sans_cantillation(s: &str) -> String {
    s.chars()
        .filter(|c| {
            !matches!(
                *c,
                '\u{0591}'
                    ..='\u{05AF}'
                        | '\u{05BD}'
                        | '\u{05BE}'
                        | '\u{05BF}'
                        | '\u{05C0}'
                        | '\u{05C3}'
                        | '\u{05C6}'
            )
        })
        .collect::<String>()
        .trim()
        .to_string()
}

/// Ôte les voyelles en plus — il ne reste que les consonnes.
fn consonnes(s: &str) -> String {
    s.chars()
        .filter(|c| {
            !matches!(
                *c,
                '\u{05B0}'..='\u{05BC}' | '\u{05C1}' | '\u{05C2}' | '\u{05C7}'
            )
        })
        .collect()
}

// ───────────────── la translittération, récoltée et jamais inventée ───────

/// **Ce qui donne à un mot source sa translittération** — et refuse quand le
/// vault n'est pas d'accord avec lui-même.
///
/// ## Pourquoi une récolte plutôt qu'un translittérateur
///
/// Passer de l'hébreu vocalisé à des lettres latines demande une chaîne de
/// règles : shewa mobile ou quiescent, daguesh fort ou doux, spirantisation
/// des *begadkefat*, gutturales qui refusent le redoublement. Elles se codent.
/// Ce n'est pas la difficulté qui arrête, c'est le **mode d'échec** : une
/// jointure fausse rend un mot touchable vers la mauvaise fiche, et le lecteur
/// peut au moins s'en apercevoir en arrivant ; une translittération fausse
/// **s'affiche sous le mot** et ressemble en tout point à un fait. Rien, dans
/// sa graphie, ne dit qu'elle a été devinée.
///
/// Le vault en a déjà écrit un millier de sa main, dans les apparats du
/// niveau 3 — `(*bereshit* / בְּרֵאשִׁית)`. Chacun est un couple vérifié par
/// quelqu'un qui lit l'hébreu. On les relève, et l'on s'arrête là.
///
/// ## Deux épreuves, dans cet ordre, et la première porte le sens
///
/// 1. **Le verset.** Les couples du niveau 3 de l'unité et de la **position**
///    où le mot se trouve. C'est l'exact.
/// 2. **Le corpus entier**, pour les mots qu'aucun apparat de leur propre
///    verset ne glose. Une forme que le corpus translittère de deux façons
///    n'en reçoit alors aucune — c'est la règle de [`LiaisonDesMots`] : **un
///    seul prétendant, sinon rien.**
///
/// ## Pourquoi le verset d'abord, et pourquoi ce n'est pas un raffinement
///
/// La première version de ce type n'avait que la seconde épreuve. Elle refusait
/// `אֱלֹהִים` — écrit `ʾElohim` à un endroit, `ʾelohim` à un autre — et le
/// relevé disait « désaccord de casse ». L'auteur a répondu, le 11 septembre
/// 2026, que ce n'en était pas un :
///
/// > « On garde les deux, et on utilise `ʾElohim` quand c'est pour parler de
/// > YHWH, et `ʾelohim` quand c'est pour parler des autres `ʾeloah`/`ʾelohim`
/// > autres que le seul et le vrai YHWH. »
///
/// La distinction n'est donc pas typographique, elle est **sémantique** : la
/// même forme hébraïque se translittère selon **qui elle désigne dans ce
/// verset-là**. Une table qui va de la forme à la translittération ne peut pas
/// la porter — elle a jeté le référent avant même d'arriver à la garde.
///
/// La garde n'avait pas tort : elle refusait pour la bonne raison. C'est la
/// **clé** qui était trop grossière, et replier la casse aurait effacé la
/// distinction au lieu de la servir — en la faisant passer pour du bruit.
///
/// Le vault a déjà tranché, occurrence par occurrence, dans le verset même.
/// Il n'y a rien à arbitrer ici : seulement à ne plus perdre l'information en
/// aplatissant.
///
/// ## Le verset se désigne par sa **position**, jamais par son numéro
///
/// Même clé que [`attacher`], et pour la même raison : quand une **parashah**
/// couvre deux chapitres bibliques, la numérotation repart de ¹ (§2.2) et
/// *Bereshit* 7 porte deux versets « 1 ». Une table indexée par numéro
/// donnerait à l'un la translittération de l'autre — sur cette unité-là
/// seulement, et sans rien dire.
///
/// ## La cantillation ôtée des deux côtés, les voyelles gardées
///
/// La cantillation est une notation musicale : `בָּרָ֣א` et `בָּרָ֥א` sont le même
/// mot, et le vault n'écrit pas ses apparats avec les te'amim du verset. On
/// compare donc les formes dévêtues de leurs accents — voir
/// [`sans_cantillation`].
///
/// Les voyelles, **non**. Le squelette `דבר` porte *davar* et *dibber* : c'est
/// exactement la voyelle qui les sépare, et c'est exactement ce que la
/// translittération est là pour montrer. L'ôter ici reviendrait à jeter la
/// réponse pour élargir la question.
#[derive(Debug, Default)]
pub struct Translitterations {
    /// Forme hébraïque sans cantillation → sa translittération, **seulement
    /// quand le corpus n'en donne qu'une**.
    par_forme: HashMap<String, String>,
    /// Combien de formes la garde a refusées.
    ///
    /// **Gardé, et dit.** Une garde qui refuse en silence ne se distingue pas
    /// d'une récolte qui n'a rien trouvé : le jour où le parcours cesserait de
    /// descendre dans les gloses, la couverture tomberait sans qu'aucun compte
    /// ne bouge.
    refusees: usize,
    /// Unité → position du verset → ses propres couples.
    ///
    /// La table qui porte la décision de l'auteur. Consultée **avant**
    /// `par_forme`, et c'est tout l'objet de la reprise du 11 septembre 2026.
    par_verset: HashMap<String, BTreeMap<usize, HashMap<String, String>>>,
}

/// Ce que la jointure a donné, mot à mot — et surtout ce qu'elle aurait donné
/// sans le verset.
///
/// ## `discordants` est le seul chiffre qui prouve quelque chose
///
/// Les trois premiers disent la couverture, qui se serait mesurée aussi bien
/// avant la reprise. Le quatrième compte les mots que les deux méthodes
/// translittèrent **différemment** : c'est exactement la distinction que
/// l'aplatissement perdait. À zéro, la reprise n'aurait rien changé en
/// pratique, et il faudrait le dire plutôt que de croire avoir corrigé
/// quelque chose.
#[derive(Debug, Default, Clone, Copy)]
pub struct BilanDesTranslitterations {
    /// Mots translittérés par le niveau 3 de leur **propre verset**.
    pub par_le_verset: u32,
    /// Mots que seul le corpus entier a su translittérer.
    pub par_le_corpus: u32,
    /// Mots dont le verset et le corpus ne disent **pas la même chose**. Le
    /// verset l'emporte ; ce compte dit ce que la table plate se trompait de
    /// donner.
    pub discordants: u32,
    /// Mots que le corpus **refusait** — deux translittérations hors contexte —
    /// et que leur propre verset tranche.
    ///
    /// C'est le cas d'`אֱלֹהִים`, et c'est la raison d'être de la reprise :
    /// l'ancienne table ne les contournait pas, elle les effaçait.
    pub recuperes: u32,
    /// Mots laissés sans translittération.
    pub sans: u32,
}

impl BilanDesTranslitterations {
    pub fn couverts(&self) -> u32 {
        self.par_le_verset + self.par_le_corpus
    }

    pub fn total(&self) -> u32 {
        self.couverts() + self.sans
    }
}

/// La règle « un seul prétendant, sinon rien », appliquée à une liste.
///
/// Sert aux deux étages — le corpus entier et un verset seul —, et c'est
/// voulu : deux écritures de la même garde finiraient par diverger, et rien ne
/// dirait laquelle croire.
fn table_sure<'a>(
    couples: impl IntoIterator<Item = (&'a str, &'a str)>,
) -> (HashMap<String, String>, usize) {
    let mut vues: HashMap<String, Option<String>> = HashMap::new();
    for (translit, hebreu) in couples {
        let forme = sans_cantillation(hebreu);
        let dit = translit.trim().to_string();
        if forme.is_empty() || dit.is_empty() {
            continue;
        }
        match vues.get(&forme) {
            // Déjà vue, et la même : rien ne change.
            Some(Some(deja)) if *deja == dit => {}
            // Déjà vue, et une autre : la forme ne dit plus rien.
            Some(_) => {
                vues.insert(forme, None);
            }
            None => {
                vues.insert(forme, Some(dit));
            }
        }
    }
    let refusees = vues.values().filter(|d| d.is_none()).count();
    (
        vues.into_iter()
            .filter_map(|(forme, dit)| dit.map(|d| (forme, d)))
            .collect(),
        refusees,
    )
}

impl Translitterations {
    /// Récolte des couples `(translit, hébreu)` déjà relevés.
    ///
    /// Séparée du parcours du corpus pour une raison d'épreuve : c'est ici
    /// qu'est la décision — accepter, refuser —, et une épreuve doit pouvoir
    /// l'atteindre sans monter un corpus entier.
    pub fn recoltee<'a>(couples: impl IntoIterator<Item = (&'a str, &'a str)>) -> Self {
        let (par_forme, refusees) = table_sure(couples);
        Self {
            par_forme,
            refusees,
            par_verset: HashMap::new(),
        }
    }

    /// Range les couples d'**un** verset, désigné par son unité et sa position.
    ///
    /// La même garde qu'au corpus, et elle ne sert presque jamais ici : il
    /// faudrait qu'un seul verset translittère deux fois la même forme de deux
    /// façons. Si ça arrive, le verset se tait et le corpus répond — c'est-à-
    /// dire qu'il se tait aussi, puisqu'il a vu les deux.
    pub fn ajouter_le_verset(
        &mut self,
        unite: &str,
        position: usize,
        couples: &[(String, String)],
    ) {
        let (table, _) = table_sure(couples.iter().map(|(t, h)| (t.as_str(), h.as_str())));
        if table.is_empty() {
            return;
        }
        self.par_verset
            .entry(unite.to_string())
            .or_default()
            .insert(position, table);
    }

    /// Ce que le niveau 3 de **ce verset-là** dit de ce mot.
    fn dans_le_verset(&self, unite: &str, position: usize, mot: &str) -> Option<String> {
        self.par_verset
            .get(unite)?
            .get(&position)?
            .get(&sans_cantillation(mot))
            .cloned()
    }

    /// La translittération de ce mot, si le corpus en donne une et une seule.
    fn pour(&self, mot: &str) -> Option<String> {
        self.par_forme.get(&sans_cantillation(mot)).cloned()
    }

    /// **La jointure telle qu'elle est publiée** — le verset, puis le corpus.
    ///
    /// Rend aussi ce qu'il faut pour le bilan : le verset l'emporte, et l'on
    /// sait dire quand il contredit le corpus.
    fn a_l_occurrence(
        &self,
        unite: &str,
        position: usize,
        mot: &str,
        bilan: &mut BilanDesTranslitterations,
    ) -> Option<String> {
        let du_corpus = self.pour(mot);
        match self.dans_le_verset(unite, position, mot) {
            Some(du_verset) => {
                match du_corpus.as_deref() {
                    // Le corpus disait autre chose : la table plate donnait le
                    // mauvais mot, et rien ne l'aurait montré.
                    Some(autre) if autre != du_verset => bilan.discordants += 1,
                    Some(_) => {}
                    // Le corpus se taisait, faute d'avoir su choisir. Le verset,
                    // lui, sait — parce que l'auteur y a déjà tranché.
                    None => bilan.recuperes += 1,
                }
                bilan.par_le_verset += 1;
                Some(du_verset)
            }
            None => match du_corpus {
                Some(d) => {
                    bilan.par_le_corpus += 1;
                    Some(d)
                }
                None => {
                    bilan.sans += 1;
                    None
                }
            },
        }
    }

    /// Combien de formes sont retenues — pour le relevé, rien d'autre.
    pub fn retenues(&self) -> usize {
        self.par_forme.len()
    }

    /// Combien la garde en a refusées pour ambiguïté.
    pub fn refusees(&self) -> usize {
        self.refusees
    }
}

/// Relève les couples `(translit, hébreu)` d'une suite de blocs.
///
/// **La descente passe par les gloses**, parce que c'est là que le niveau 3
/// vit : `(*chesed* / חֶסֶד)` s'écrit le plus souvent dans un commentaire. Un
/// parcours de surface en manquerait la majorité sans rien dire — il
/// récolterait simplement moins, et la couverture serait basse sans cause
/// visible.
fn couples_des_blocs(blocs: &[Block], dans: &mut Vec<(String, String)>) {
    for bloc in blocs {
        match bloc {
            Block::Heading { nodes, .. } | Block::Para { nodes } | Block::Quote { nodes } => {
                couples_des_noeuds(nodes, dans)
            }
            Block::Verses { verses } => {
                for v in verses {
                    couples_des_noeuds(&v.nodes, dans);
                }
            }
            Block::List { items, .. } => {
                for item in items {
                    couples_des_noeuds(item, dans);
                }
            }
            Block::Table { headers, rows } => {
                for cellule in headers.iter().chain(rows.iter().flatten()) {
                    couples_des_noeuds(cellule, dans);
                }
            }
            Block::Rule => {}
        }
    }
}

fn couples_des_noeuds(noeuds: &[Inline], dans: &mut Vec<(String, String)>) {
    for noeud in noeuds {
        match noeud {
            Inline::Translit {
                translit, hebrew, ..
            } => dans.push((translit.clone(), hebrew.clone())),
            Inline::Gloss { children }
            | Inline::Em { children }
            | Inline::Accentuation { children }
            | Inline::Link { children, .. } => couples_des_noeuds(children, dans),
            _ => {}
        }
    }
}

/// Récolte la table sur les unités **publiées**.
///
/// ## L'unité entière, titre et pied compris
///
/// C'est la leçon que `niveau_trois::resoudre_l_unite` a déjà payée : un titre
/// d'unité et les notes d'un pied de page sont livrés comme le reste, et un
/// parcours qui s'arrêterait à `blocks` y laisserait des couples au sol. Ici
/// l'oubli serait muet — moins de mots translittérés, sans qu'aucun compte ne
/// bouge.
///
/// ## Le publié, et non le vault
///
/// On récolte sur ce que le lecteur reçoit. Un apparat écrit dans une unité
/// non publiée ne fait pas autorité sur un mot que le lecteur voit aujourd'hui
/// — et il pourrait, à lui seul, rendre une forme ambiguë et l'effacer de la
/// table.
pub fn translitterations(unites: &[Chapter]) -> Translitterations {
    // ── Le corpus entier, d'abord ────────────────────────────────────────
    let mut couples: Vec<(String, String)> = Vec::new();
    for unite in unites {
        couples_des_noeuds(&unite.title_nodes, &mut couples);
        couples_des_blocs(&unite.blocks, &mut couples);
        if let Some(pied) = &unite.footer {
            couples_des_blocs(&pied.notes, &mut couples);
        }
    }
    let mut table =
        Translitterations::recoltee(couples.iter().map(|(t, h)| (t.as_str(), h.as_str())));

    // ── Puis chaque verset, à sa position ────────────────────────────────
    //
    // **La position se compte exactement comme `preparer` la comptera** : les
    // `Block::Verses` à plat, dans l'ordre, et rien d'autre — elle court donc
    // *à travers* les paragraphes, et ne repart pas avec eux. Deux façons de
    // numéroter les mêmes versets finiraient par diverger d'un cran, et un
    // décalage d'un cran produit un fichier bien formé que rien ne distingue
    // d'un fichier juste.
    for unite in unites {
        let mut position = 0usize;
        for bloc in &unite.blocks {
            let Block::Verses { verses } = bloc else {
                continue;
            };
            for v in verses {
                let mut du_verset = Vec::new();
                couples_des_noeuds(&v.nodes, &mut du_verset);
                if !du_verset.is_empty() {
                    table.ajouter_le_verset(&unite.id, position, &du_verset);
                }
                position += 1;
            }
        }
    }
    table
}

// ───────────────────────────── la plage biblique ──────────────────────────

/// Une plage de versets bibliques, dépliée en couples ordonnés.
///
/// Quatre formes traversent le corpus, et il faut les quatre :
///
/// ```text
/// 3            un chapitre entier
/// 7-8          une plage de chapitres
/// 9:18-29      une plage de versets dans un chapitre
/// 1:1 — 2:3    d'un chapitre à l'autre
/// ```
///
/// Le tiret peut être court, demi-cadratin ou cadratin — le corpus emploie les
/// trois, et n'en distinguer qu'un ferait échouer une unité sur quatre sans
/// que rien ne le dise.
fn deplier(reference: &str, versets_par_chapitre: &BTreeMap<u32, u32>) -> Option<Vec<(u32, u32)>> {
    let r = reference.trim();
    let tiret = |s: &str| s.replace(['—', '–'], "-");
    let r = tiret(r);

    let nombre = |s: &str| s.trim().parse::<u32>().ok();
    let tout = |c: u32| -> Option<Vec<(u32, u32)>> {
        let n = *versets_par_chapitre.get(&c)?;
        Some((1..=n).map(|v| (c, v)).collect())
    };

    // « 1:1 - 2:3 »
    if let Some((g, d)) = r.split_once('-') {
        if let (Some((c1, v1)), Some((c2, v2))) = (g.split_once(':'), d.split_once(':')) {
            let (c1, v1) = (nombre(c1)?, nombre(v1)?);
            let (c2, v2) = (nombre(c2)?, nombre(v2)?);
            let mut out = Vec::new();
            for c in c1..=c2 {
                let dernier = *versets_par_chapitre.get(&c)?;
                let debut = if c == c1 { v1 } else { 1 };
                let fin = if c == c2 { v2 } else { dernier };
                out.extend((debut..=fin).map(|v| (c, v)));
            }
            return Some(out);
        }
        // « 9:18-29 »
        if let Some((c, v1)) = g.split_once(':') {
            let (c, v1, v2) = (nombre(c)?, nombre(v1)?, nombre(d)?);
            return Some((v1..=v2).map(|v| (c, v)).collect());
        }
        // « 7-8 »
        let (c1, c2) = (nombre(g)?, nombre(d)?);
        let mut out = Vec::new();
        for c in c1..=c2 {
            out.extend(tout(c)?);
        }
        return Some(out);
    }

    // « 3 »
    tout(nombre(&r)?)
}

// ───────────────────────────────── l'émission ─────────────────────────────

/// Ce que la préparation rend : de quoi écrire, et de quoi parler.
///
/// Une structure nommée plutôt qu'un quadruplet — clippy le demandait, et il
/// avait raison sur le fond : `Result<Option<(A, Vec<(String, B)>, Vec<String>,
/// Vec<String>)>>` oblige à relire la signature pour savoir lequel des deux
/// `Vec<String>` porte les écarts et lequel porte les relevés.
pub struct Preparation {
    pub manifeste: ManifesteSources,
    /// `(chemin relatif, contenu)` pour chaque livre × témoin.
    pub fichiers: Vec<(String, LivreSources)>,
    /// Les fichiers frères des divergences d'éditions.
    pub fichiers_editions: Vec<(String, EditionsComparees)>,
    /// Les unités écartées faute de jointure sûre. Rien de faux n'est émis.
    pub ecartees: Vec<String>,
    /// Ce qui mérite l'œil de l'auteur sans rien empêcher.
    pub releves: Vec<String>,
    /// **La longueur réelle de chaque chapitre biblique** — `(livre ONT,
    /// chapitre) → son dernier verset`, telle que les témoins la portent.
    ///
    /// ## À quoi ça sert ailleurs, puisque la jointure n'en a pas besoin
    ///
    /// `renvois::interne` doit connaître la longueur du premier chapitre d'une
    /// plage à cheval, et il la **déduit** du nombre de versets de l'unité. La
    /// déduction est juste tant que l'unité porte un verset par verset
    /// biblique — et elle ne peut pas s'apercevoir qu'une unité en a réuni
    /// deux, puisque c'est de ce compte-là qu'elle part.
    ///
    /// Ce module est le seul endroit du pipeline qui lise la longueur vraie :
    /// elle est dans les `.jsonl` du vault, nulle part ailleurs. On la sort
    /// donc ici pour que `renvois::eprouver_les_deductions` puisse confronter
    /// l'affirmation à la mesure.
    ///
    /// ## Ce qui n'y figure pas, et pourquoi l'absence est un état
    ///
    /// Un chapitre n'entre ici que si **tous** les fichiers sources qui le
    /// couvrent lui donnent la même longueur. Deux cas l'en font sortir, et
    /// aucun des deux n'est une panne :
    ///
    /// - **les témoins se contredisent** — l'Apocalypse 12 porte 18 versets au
    ///   SBLGNT et 17 au byzantin. La longueur « réelle » n'est alors pas un
    ///   fait unique, et prendre l'une des deux serait choisir sans le dire ;
    /// - **deux livres reçus partagent un livre ONT** — `melakhim` couvre 1 et
    ///   2 Rois, dont les chapitres 1 portent le même numéro sans être le même
    ///   chapitre. La clé `(melakhim, 1)` ne désigne alors rien de précis.
    ///
    /// L'absence vaut donc **non mesuré**, et le contrôle en aval la traite
    /// comme telle — jamais comme un succès. Un contrôle qui rend vert faute
    /// d'avoir regardé est pire qu'un contrôle absent.
    pub longueurs_de_chapitre: BTreeMap<(String, u32), u32>,
    /// Ce que la jointure des translittérations a donné — voir
    /// [`BilanDesTranslitterations`].
    pub translitterations: BilanDesTranslitterations,
}

/// Accroche les divergences d'éditions aux positions d'une unité.
///
/// ## Pourquoi par position et non par numéro de verset
///
/// Le numéro affiché ==n'est pas unique dans une unité== : quand une
/// **parashah** couvre deux chapitres bibliques, la numérotation repart de ¹
/// au second (§2.2 du vault). *Bereshit* 7 porte ainsi deux versets « 1 ».
///
/// Un apparat accroché par numéro s'attacherait donc aux deux — sur cette
/// unité-là seulement, et sans rien dire. C'est le défaut qui passe tous les
/// essais sauf un, et l'essai qui le trouve n'est écrit que par quelqu'un qui
/// connaissait déjà le piège.
///
/// La position, elle, est unique par construction.
fn attacher(
    plage: &[(u32, u32)],
    versets: &[VersetPublie],
    par_ref: &BTreeMap<(u32, u32), Vec<EntreeApparat>>,
) -> Vec<DivergencePubliee> {
    let mut out = Vec::new();
    for (i, cle_ref) in plage.iter().enumerate() {
        for e in par_ref.get(cle_ref).into_iter().flatten() {
            out.push(DivergencePubliee {
                i,
                n: versets[i].n,
                lecon: e.lecon.clone(),
                editions: e.editions.clone(),
                crochets: e.crochets.clone(),
                variantes: e.variantes.clone(),
            });
        }
    }
    out
}

/// Lit `sources/` et rend ce qu'il faut écrire — ou l'erreur qui arrête tout.
///
/// Un vault sans `sources/` rend `Ok(None)` : la couche est facultative, et
/// son absence n'est pas une panne.
pub fn preparer(
    racine: &Path,
    unites: &[Chapter],
    transmissions: &BTreeMap<u32, (String, String)>,
    numero_vers_slug: &BTreeMap<u32, String>,
    liaison: &mut LiaisonDesMots,
    translitterations: &Translitterations,
) -> Result<Option<Preparation>, String> {
    let dossier = racine.join(SOURCES);
    let manifeste = dossier.join("MANIFEST.json");
    if !manifeste.is_file() {
        return Ok(None);
    }
    let brut = fs::read_to_string(&manifeste)
        .map_err(|e| format!("lecture de {}: {e}", manifeste.display()))?;
    let vault: ManifesteVault = serde_json::from_str(&brut)
        .map_err(|e| format!("{} illisible : {e}", manifeste.display()))?;

    let mut temoins = BTreeMap::new();
    // Les unités écartées faute de jointure sûre — dites au rapport, jamais
    // émises de travers.
    let mut sautees: Vec<String> = Vec::new();
    // Ce qui mérite l'œil de l'auteur sans rien empêcher.
    let mut releves: Vec<String> = Vec::new();
    let mut editions_par_livre: BTreeMap<String, FichierPublie> = BTreeMap::new();
    let mut fichiers_editions: Vec<(String, EditionsComparees)> = Vec::new();
    let mut livres: BTreeMap<String, LivrePublie> = BTreeMap::new();
    let mut fichiers = Vec::new();
    // La longueur de chaque chapitre biblique pendant qu'on l'établit.
    //
    // `Some(n)` : tous les fichiers sources vus jusqu'ici disent `n`. `None` :
    // ils se contredisent — et une longueur contestée n'est pas une longueur.
    // Voir `Preparation::longueurs_de_chapitre` pour les deux façons dont ça
    // arrive, et pour ce que l'absence signifie en aval.
    let mut longueurs: BTreeMap<(String, u32), Option<u32>> = BTreeMap::new();
    // Ce que la jointure des translittérations aura donné, pour le relevé.
    let mut bilan = BilanDesTranslitterations::default();

    for (cle, t) in &vault.sources {
        temoins.insert(
            cle.clone(),
            TemoinPublie {
                nom: t.nom.clone(),
                langue: t.langue.clone(),
                attribution: t.attribution.clone(),
                degre: t.temoin.clone(),
            },
        );

        for (livre_source, meta) in &t.livres {
            let chemin = dossier.join(cle).join(format!("{livre_source}.jsonl"));
            let contenu = fs::read_to_string(&chemin)
                .map_err(|e| format!("lecture de {}: {e}", chemin.display()))?;

            // **Une passe d'apprentissage avant la jointure.**
            //
            // Le témoin porte, pour chaque forme, le numéro que le lexique
            // tait. On le lui demande une fois par livre, avant de joindre quoi
            // que ce soit — voir `apprendre_du_temoin`.
            //
            // Deux passes sur le même contenu plutôt qu'une : la seconde a
            // besoin de ce que la première établit, et joindre au fil de la
            // lecture reviendrait à décider avant de savoir.
            liaison.apprendre_du_temoin(
                contenu
                    .lines()
                    .filter_map(|l| {
                        let v: VersetSource = serde_json::from_str(l).ok()?;
                        Some(
                            v.w.into_iter()
                                .filter_map(|m| m.oshb.map(|o| (m.t, o.lem)))
                                .collect::<Vec<_>>(),
                        )
                    })
                    .flatten(),
            );

            // (chapitre, verset) → texte joint
            let mut par_ref: BTreeMap<(u32, u32), String> = BTreeMap::new();
            // (chapitre, verset) → les mots, quand le témoin les étiquette.
            let mut mots_par_ref: BTreeMap<(u32, u32), Vec<MotPublie>> = BTreeMap::new();
            let mut par_chapitre: BTreeMap<u32, u32> = BTreeMap::new();
            for ligne in contenu.lines().filter(|l| !l.trim().is_empty()) {
                let v: VersetSource = serde_json::from_str(ligne)
                    .map_err(|e| format!("{} : ligne illisible — {e}", chemin.display()))?;
                let texte =
                    v.w.iter()
                        .map(|m| m.t.as_str())
                        .collect::<Vec<_>>()
                        .join(" ");
                let mots: Vec<MotPublie> =
                    v.w.iter()
                        .filter(|m| m.oshb.is_some())
                        .map(|m| {
                            let o = m.oshb.as_ref().expect("filtré juste au-dessus");
                            MotPublie {
                                cible: liaison.cible(&m.t, Some(&o.lem)),
                                // **Pas ici.** À cette ligne on lit un `.jsonl`
                                // classé par référence biblique : on ne sait pas
                                // encore dans quelle unité ni à quelle position
                                // ce verset tombera, et c'est précisément ce qui
                                // décide de la translittération. Elle est posée
                                // plus bas, quand la jointure est faite.
                                translit: None,
                                t: m.t.clone(),
                                lem: Some(o.lem.clone()),
                                morph: Some(o.morph.clone()),
                            }
                        })
                        .collect();
                if !mots.is_empty() {
                    mots_par_ref.insert((v.c, v.v), mots);
                }
                par_ref.insert((v.c, v.v), texte);
                let e = par_chapitre.entry(v.c).or_insert(0);
                *e = (*e).max(v.v);
            }

            // **Le versement au relevé des longueurs, ici et pas plus bas.**
            //
            // `par_chapitre` est complet dès cette ligne, et il le reste quoi
            // qu'il advienne des unités : la garde de jointure qui suit peut
            // sauter une unité — un brouillon divergent —, mais la longueur du
            // chapitre, elle, est un fait du témoin, pas de l'unité. La
            // mesurer avant est ce qui permet au contrôle d'aval d'attraper
            // précisément les brouillons que la garde laisse passer.
            for (&c, &dernier) in &par_chapitre {
                longueurs
                    .entry((meta.slug.clone(), c))
                    .and_modify(|acquis| {
                        if *acquis != Some(dernier) {
                            *acquis = None;
                        }
                    })
                    .or_insert(Some(dernier));
            }

            let mut unites_publiees: BTreeMap<String, Vec<VersetPublie>> = BTreeMap::new();
            // La plage biblique de chaque unité, gardée pour l'apparat : il
            // s'accroche aux mêmes positions que les versets.
            let mut plages: BTreeMap<String, Vec<(u32, u32)>> = BTreeMap::new();
            for u in unites.iter().filter(|u| u.book_id == meta.slug) {
                let Some(reference) = u.subtitle.as_ref().and_then(|s| s.reference.as_deref())
                else {
                    continue; // une introduction ne recouvre aucun verset
                };
                let Some(plage) = deplier(reference, &par_chapitre) else {
                    return Err(format!(
                        "{} : la plage « {reference} » de {} n'a pas été comprise. \
                         Quatre formes sont admises — `3`, `7-8`, `9:18-29`, `1:1 — 2:3`.",
                        cle, u.id
                    ));
                };

                // ── La garde de jointure ──────────────────────────────────
                //
                // Si le compte des versets ONT ne tombe pas sur la plage
                // déclarée, la jointure glisserait d'un cran sur toute
                // l'unité — et un décalage produit un fichier bien formé que
                // rien ne distingue d'un fichier juste. On s'arrête.
                if plage.len() != u.verse_count as usize {
                    let verrouillee = u.footer.as_ref().is_some_and(|f| f.locked);
                    let dit = format!(
                        "{} : {} annonce « {reference} » — {} versets bibliques — \
                         mais en porte {}. Soit le sous-titre est faux, soit l'unité \
                         est incomplète ; dans les deux cas la jointure serait fausse.",
                        cle,
                        u.id,
                        plage.len(),
                        u.verse_count
                    );
                    // Une unité **verrouillée** qui diverge est un défaut : elle a
                    // été validée, donc son sous-titre engage. On s'arrête.
                    //
                    // Un **brouillon** qui diverge est un chantier en cours, et
                    // arrêter tout le corpus pour ça punirait l'auteur d'écrire.
                    // On saute l'unité — mieux vaut pas de source qu'une source
                    // décalée d'un cran — et on le dit au rapport.
                    if verrouillee {
                        return Err(dit);
                    }
                    sautees.push(dit);
                    continue;
                }

                let numeros: Vec<u32> = u
                    .blocks
                    .iter()
                    .flat_map(|b| match b {
                        Block::Verses { verses } => verses.iter().map(|v| v.n).collect(),
                        _ => Vec::new(),
                    })
                    .collect();

                // ── La rupture de numérotation, vérifiée et non redéclarée ──
                //
                // Le §2.2 du vault fait repartir la numérotation à ¹ quand un
                // nouveau chapitre biblique s'ouvre au milieu d'une parashah.
                // La rupture est donc **déjà dans la donnée** — le passage de
                // 24 à 1 dans la suite des `n`.
                //
                // On aurait pu la déclarer au manifeste. On ne le fait pas :
                // ce serait écrire une seconde fois un fait que le tableau
                // porte, et deux écritures du même fait finissent par se
                // contredire — sans que rien ne dise laquelle croire.
                //
                // ## Et pourquoi ce n'est qu'un relevé, non une garde
                //
                // La première version arrêtait la construction quand la
                // rupture ne tombait pas sur le changement de chapitre. Elle a
                // mordu au premier essai — sur `bereshit-1`, qui est
                // ==légitime== : l'unité couvre Gn 1:1—2:3 et numérote 1 à 34
                // sans repartir, parce que le §2.3 tient 2:1-3 pour le
                // couronnement du même récit. `bereshit-7`, lui, repart entre
                // Gn 7 et 8, qui sont deux mouvements.
                //
                // La règle du §2.2 n'est donc pas mécanique, elle est
                // ==fonctionnelle== : elle suit ce que l'unité accomplit, pas
                // le découpage de Langton. Une garde ne peut pas trancher ça.
                //
                // Et surtout : ==la jointure n'en dépend pas==. Elle est
                // positionnelle — 34 versets ONT contre 34 versets bibliques,
                // dans l'ordre — et le fait que la numérotation reparte ou non
                // ne déplace aucun verset. On relève donc l'écart pour
                // l'auteur, et on n'arrête rien.
                let ruptures: Vec<usize> = (1..numeros.len())
                    .filter(|&i| numeros[i] < numeros[i - 1])
                    .collect();
                let changements: Vec<usize> = (1..plage.len())
                    .filter(|&i| plage[i].0 != plage[i - 1].0)
                    .collect();
                if ruptures != changements {
                    releves.push(format!(
                        "{} : la numérotation repart à ¹ aux positions {:?} quand \
                         « {reference} » change de chapitre aux positions {:?} \
                         (§2.2 — la jointure reste juste, elle est positionnelle)",
                        u.id, ruptures, changements
                    ));
                }

                let mut sortie = Vec::with_capacity(plage.len());
                for (i, cle_ref) in plage.iter().enumerate() {
                    let Some(texte) = par_ref.get(cle_ref) else {
                        return Err(format!(
                            "{} : {}:{} manque au témoin, réclamé par {}.",
                            cle, cle_ref.0, cle_ref.1, u.id
                        ));
                    };
                    // ── La translittération, à l'occurrence ──────────────
                    //
                    // `i` est la position dans l'unité, la même clé que
                    // `attacher` : le niveau 3 de **ce verset-là** répond
                    // d'abord, le corpus entier ensuite. Voir
                    // `Translitterations`.
                    let mut mots = mots_par_ref.get(cle_ref).cloned().unwrap_or_default();
                    for mot in &mut mots {
                        mot.translit =
                            translitterations.a_l_occurrence(&u.id, i, &mot.t, &mut bilan);
                    }
                    sortie.push(VersetPublie {
                        n: numeros.get(i).copied().unwrap_or((i + 1) as u32),
                        t: texte.clone(),
                        mots,
                    });
                }
                plages.insert(u.id.clone(), plage);
                unites_publiees.insert(u.id.clone(), sortie);
            }

            if unites_publiees.is_empty() {
                continue; // le livre n'a pas encore d'unité écrite
            }

            // ── Les divergences d'éditions, s'il y en a ───────────────────
            //
            // Même clé que les témoins — unité ONT et position — et pour la
            // même raison : un apparat joint par (livre, chapitre, verset)
            // s'accrocherait à ==deux endroits== dans une unité qui couvre
            // deux chapitres bibliques, puisque le numéro de verset y repasse
            // par ¹. Bereshit 7 le ferait ; les autres non. C'est le défaut
            // qui passe tous les essais sauf un.
            let chemin_app = dossier
                .join(cle)
                .join(format!("{livre_source}-apparat.jsonl"));
            if chemin_app.is_file() {
                let brut_app = fs::read_to_string(&chemin_app)
                    .map_err(|e| format!("lecture de {}: {e}", chemin_app.display()))?;
                let mut par_ref_app: BTreeMap<(u32, u32), Vec<EntreeApparat>> = BTreeMap::new();
                for ligne in brut_app.lines().filter(|l| !l.trim().is_empty()) {
                    let e: EntreeApparat = serde_json::from_str(ligne).map_err(|err| {
                        format!("{} : ligne illisible — {err}", chemin_app.display())
                    })?;
                    par_ref_app.entry((e.c, e.v)).or_default().push(e);
                }

                let mut divergences: BTreeMap<String, Vec<DivergencePubliee>> = BTreeMap::new();
                for (id_unite, versets) in &unites_publiees {
                    let Some(plage) = plages.get(id_unite) else {
                        continue;
                    };
                    let pour_l_unite = attacher(plage, versets, &par_ref_app);
                    if !pour_l_unite.is_empty() {
                        divergences.insert(id_unite.clone(), pour_l_unite);
                    }
                }

                if !divergences.is_empty() {
                    let rendu_app = EditionsComparees {
                        temoin: cle.clone(),
                        unites: divergences,
                    };
                    let corps_app = serde_json::to_string(&rendu_app).map_err(|e| e.to_string())?;
                    let relatif_app = format!("sources/{cle}/{}-editions.json", meta.slug);
                    editions_par_livre.insert(
                        meta.slug.clone(),
                        FichierPublie {
                            octets: corps_app.len(),
                            sha256: sha256(corps_app.as_bytes()),
                            chemin: relatif_app.clone(),
                        },
                    );
                    fichiers_editions.push((relatif_app, rendu_app));
                }
            }

            let rendu = LivreSources {
                temoin: cle.clone(),
                unites: unites_publiees,
            };
            let corps = serde_json::to_string(&rendu).map_err(|e| e.to_string())?;
            let relatif = format!("sources/{cle}/{}.json", meta.slug);
            livres
                .entry(meta.slug.clone())
                .or_insert_with(|| LivrePublie {
                    temoins: BTreeMap::new(),
                    editions: None,
                    transmission: None,
                    cause: None,
                })
                .temoins
                .insert(
                    cle.clone(),
                    FichierPublie {
                        octets: corps.len(),
                        sha256: sha256(corps.as_bytes()),
                        chemin: relatif.clone(),
                    },
                );
            fichiers.push((relatif, rendu));
        }
    }

    // ── Les livres sans témoin ────────────────────────────────────────────
    //
    // Un `temoins: {}` sans phrase serait un aveuglement, pas un fait : le
    // lecteur verrait un vide sans savoir pourquoi. La phrase vient du vault
    // — l'app ne la compose jamais — et son absence arrête la construction.
    for (numero, (phrase, cause)) in transmissions {
        let Some(slug) = numero_vers_slug.get(numero) else {
            return Err(format!(
                "corpus-order.md déclare le livre {numero} sans texte source, \
                 mais aucun slot de ce numéro n'existe dans le vault."
            ));
        };
        let e = livres.entry(slug.clone()).or_insert_with(|| LivrePublie {
            temoins: BTreeMap::new(),
            editions: None,
            transmission: None,
            cause: None,
        });
        e.transmission = Some(phrase.clone());
        e.cause = Some(cause.clone());
    }

    // Les divergences d'éditions rejoignent leur livre au manifeste.
    for (slug, fichier) in editions_par_livre {
        if let Some(l) = livres.get_mut(&slug) {
            l.editions = Some(fichier);
        }
    }

    Ok(Some(Preparation {
        manifeste: ManifesteSources {
            schema: 1,
            genere: crate::config::genere(),
            temoins,
            livres,
        },
        fichiers,
        fichiers_editions,
        ecartees: sautees,
        releves,
        // Seules les longueurs **unanimes** sortent. Une longueur contestée
        // est retirée plutôt que tranchée : en aval, son absence se lira
        // « non mesuré », ce qui est exactement ce qu'elle est.
        longueurs_de_chapitre: longueurs
            .into_iter()
            .filter_map(|(cle, n)| n.map(|n| (cle, n)))
            .collect(),
        translitterations: bilan,
    }))
}

/// L'empreinte, en hexadécimal minuscule — la forme que vérifient les clients.
fn sha256(octets: &[u8]) -> String {
    let mut h = Sha256::new();
    h.update(octets);
    h.finalize().iter().map(|o| format!("{o:02x}")).collect()
}

/// Lit la table de `corpus-order.md` : les livres sans texte en langue source.
///
/// Rend `numéro ONT → (phrase, cause)`. La phrase est ce que le lecteur lit ;
/// la cause vaut `temoin` — le livre ne survit dans aucun manuscrit de sa
/// langue — ou `fichier` — le témoin existe mais aucune édition n'en est
/// réutilisable. ==La distinction n'est pas cosmétique== : quatre de ces six
/// livres recevront leur source, et un rendu qui dirait « perdu » les
/// trahirait.
///
/// Les marques `==…==` de l'apparat du vault sont retirées : elles servent au
/// traducteur, pas au lecteur.
pub fn lire_transmissions(racine: &Path) -> Result<BTreeMap<u32, (String, String)>, String> {
    let chemin = racine.join("corpus-order.md");
    let texte =
        fs::read_to_string(&chemin).map_err(|e| format!("lecture de {}: {e}", chemin.display()))?;
    let Some(debut) = texte.find("## Les livres sans texte en langue source") else {
        return Ok(BTreeMap::new());
    };
    let section = &texte[debut..];
    let fin = section[3..]
        .find("\n## ")
        .map(|i| i + 3)
        .unwrap_or(section.len());

    let mut out = BTreeMap::new();
    for ligne in section[..fin].lines() {
        let l = ligne.trim();
        if !l.starts_with('|') {
            continue;
        }
        let cases: Vec<&str> = l.trim_matches('|').split('|').map(str::trim).collect();
        if cases.len() < 4 {
            continue;
        }
        let Ok(numero) = cases[0].parse::<u32>() else {
            continue; // l'en-tête et le filet
        };
        let nettoyer = |s: &str| s.replace("==", "").trim().to_string();
        let phrase = nettoyer(cases[2]);
        // « fichier ==À confirmer par l'auteur== » → « fichier »
        let cause = nettoyer(cases[3])
            .split_whitespace()
            .next()
            .unwrap_or_default()
            .to_string();
        if phrase.is_empty() || cause.is_empty() {
            return Err(format!(
                "corpus-order.md : le livre {numero} est déclaré sans texte source \
                 mais sa phrase ou sa cause manque."
            ));
        }
        out.insert(numero, (phrase, cause));
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entree(c: u32, v: u32, lecon: &str) -> EntreeApparat {
        EntreeApparat {
            c,
            v,
            lecon: lecon.into(),
            editions: vec!["WH".into()],
            crochets: Vec::new(),
            variantes: vec![VarianteApparat {
                t: "autre".into(),
                editions: vec!["RP".into()],
                crochets: Vec::new(),
            }],
        }
    }

    /// **La jointure d'un mot à sa fiche, et son refus.**
    ///
    /// Les trois cas qui décident, et le troisième est le seul qui compte :
    /// une jointure qui se trompe est invisible au lecteur.
    #[test]
    fn un_mot_ouvre_sa_fiche_quand_elle_est_seule() {
        fn fiche<'a>(l: &'a str, h: &'a str, st: Option<&'a str>) -> FichePourLaJointure<'a> {
            FichePourLaJointure {
                lemme: l,
                hebreu: Some(h),
                strong: st,
            }
        }
        let liaison = LiaisonDesMots::nouvelle([
            fiche("elohim", "אֱלֹהִים", Some("430")),
            fiche("bara", "בָּרָא", None),
            // Les deux qu'un squelette confond : une voyelle les sépare.
            fiche("davar", "דָּבָר", Some("1697")),
            fiche("dibber", "דִּבֵּר", Some("1696")),
        ]);

        // Vocalisé, cantillation ôtée — le cas exact.
        assert_eq!(
            liaison.cible("אֱלֹהִ֑ים", None),
            Some(CibleDuNiveauTrois::Term {
                lemma: "elohim".into()
            })
        );
        // Fléchi : seul le squelette tombe juste, et il est seul à le porter.
        assert_eq!(
            liaison.cible("בְּרֹ֤א", None),
            Some(CibleDuNiveauTrois::Term {
                lemma: "bara".into()
            })
        );
        // **Ambigu : rien.** `דבר` est *davar* et *dibber* ; la forme
        // vocalisée du texte ne coïncide avec aucune des deux fiches, et le
        // squelette en désigne deux. Ouvrir l'une des deux serait mentir.
        assert_eq!(liaison.cible("וַיְדַבֵּ֥ר", None), None);
        // Un mot qu'aucune fiche ne nomme.
        assert_eq!(liaison.cible("אֵ֥ת", None), None);
    }

    /// **La récolte des translittérations, et son refus.**
    ///
    /// Trois cas, et le deuxième est le seul qui coûte : une translittération
    /// fausse ne rend pas le mot muet, elle s'affiche dessous avec l'aplomb
    /// d'un fait.
    #[test]
    fn une_forme_rend_sa_translitteration_quand_elle_est_seule() {
        let table = Translitterations::recoltee([
            // Écrit deux fois, à l'identique : une seule voix, ça passe.
            ("bereshit", "בְּרֵאשִׁית"),
            ("bereshit", "בְּרֵאשִׁית"),
            // Le vault hésite : `ʾElohim` quand il nomme, `ʾelohim` quand il
            // désigne. Deux voix, donc aucune.
            ("ʾElohim", "אֱלֹהִים"),
            ("ʾelohim", "אֱלֹהִים"),
            // Ce que la voyelle sépare reste séparé : on n'ôte pas le niqqud.
            ("davar", "דָּבָר"),
            ("dibber", "דִּבֵּר"),
        ]);

        // Le couple sûr passe — et la cantillation du témoin ne l'empêche
        // pas : le vault écrit ses apparats sans les te'amim du verset.
        assert_eq!(
            table.pour("בְּרֵאשִׁ֖ית"),
            Some("bereshit".to_string()),
            "la cantillation est une notation musicale, jamais un autre mot"
        );
        // **Le couple ambigu ne rend rien.** C'est toute la garde.
        assert_eq!(
            table.pour("אֱלֹהִ֑ים"),
            None,
            "deux translittérations pour une forme : afficher l'une des deux \
             serait trancher à la place de l'auteur, et sans le dire"
        );
        // Les voyelles ne sont pas ôtées : `דבר` ne ramasse pas les deux.
        assert_eq!(table.pour("דָּבָ֥ר"), Some("davar".to_string()));
        assert_eq!(
            table.pour("דִּבֶּ֥ר"),
            None,
            "une forme fléchie n'est pas la fiche"
        );
        // Un mot dont le corpus ne parle pas.
        assert_eq!(table.pour("אֵ֥ת"), None);

        // Et les comptes, pour que le relevé du build dise vrai.
        assert_eq!(table.retenues(), 3, "bereshit, davar, dibber");
        assert_eq!(table.refusees(), 1, "אֱלֹהִים, et elle seule");
    }

    /// **La distinction que l'aplatissement perdait.**
    ///
    /// `אֱלֹהִים` est `ʾElohim` quand il désigne YHWH et `ʾelohim` quand il
    /// désigne les autres. Hors contexte, la forme ne dit donc rien — et c'est
    /// juste. Dans son verset, elle dit ce que l'auteur y a écrit.
    #[test]
    fn une_forme_recoit_la_translitteration_de_son_propre_verset() {
        let mut table = Translitterations::recoltee([
            ("ʾElohim", "אֱלֹהִים"),
            ("ʾelohim", "אֱלֹהִים"),
            ("bara", "בָּרָא"),
        ]);
        // Hors contexte, la garde tient : la forme porte deux translittérations.
        assert_eq!(table.pour("אֱלֹהִ֑ים"), None);

        let couple = |t: &str, h: &str| vec![(t.to_string(), h.to_string())];
        table.ajouter_le_verset("bereshit-1", 0, &couple("ʾElohim", "אֱלֹהִים"));
        table.ajouter_le_verset("bereshit-1", 30, &couple("ʾelohim", "אֱלֹהִים"));

        let mut bilan = BilanDesTranslitterations::default();
        // **Le même mot, deux versets, deux translittérations** — et aucune
        // des deux n'a été devinée.
        assert_eq!(
            table.a_l_occurrence("bereshit-1", 0, "אֱלֹהִ֑ים", &mut bilan),
            Some("ʾElohim".to_string()),
            "au verset où l'auteur parle de YHWH"
        );
        assert_eq!(
            table.a_l_occurrence("bereshit-1", 30, "אֱלֹהִ֖ים", &mut bilan),
            Some("ʾelohim".to_string()),
            "au verset où il parle des autres"
        );
        // Un mot qu'aucun apparat de son verset ne glose retombe sur le corpus.
        assert_eq!(
            table.a_l_occurrence("bereshit-1", 5, "בְּרֹ֤א", &mut bilan),
            None,
            "le corpus ne connaît que la forme exacte, pas le squelette"
        );
        assert_eq!(
            table.a_l_occurrence("bereshit-1", 5, "בָּרָ֣א", &mut bilan),
            Some("bara".to_string())
        );
        // Et là où aucun verset ne tranche, l'ambiguïté vaut toujours silence.
        assert_eq!(
            table.a_l_occurrence("bereshit-1", 5, "אֱלֹהִ֑ים", &mut bilan),
            None,
            "hors d'un verset qui le dise, choisir serait trancher"
        );

        assert_eq!(bilan.par_le_verset, 2);
        assert_eq!(bilan.par_le_corpus, 1);
        assert_eq!(bilan.recuperes, 2, "deux mots que la table plate effaçait");
        assert_eq!(bilan.sans, 2);
    }

    /// **Le verset l'emporte, et le désaccord se compte.**
    ///
    /// Sans ce compte, une reprise qui ne changerait rien en pratique
    /// ressemblerait trait pour trait à une reprise qui corrige.
    #[test]
    fn le_verset_l_emporte_sur_le_corpus_et_le_desaccord_se_dit() {
        let mut table = Translitterations::recoltee([("vayiqach", "וַיִּקַּח")]);
        table.ajouter_le_verset(
            "bereshit-3",
            2,
            &[("vayiqqach".to_string(), "וַיִּקַּח".to_string())],
        );

        let mut bilan = BilanDesTranslitterations::default();
        assert_eq!(
            table.a_l_occurrence("bereshit-3", 2, "וַיִּקַּ֥ח", &mut bilan),
            Some("vayiqqach".to_string()),
            "ce que dit le verset, non ce que dit la moyenne du corpus"
        );
        assert_eq!(bilan.discordants, 1);
        // Ailleurs, le corpus reste la réponse.
        assert_eq!(
            table.a_l_occurrence("bereshit-3", 9, "וַיִּקַּ֖ח", &mut bilan),
            Some("vayiqach".to_string())
        );
        assert_eq!(bilan.discordants, 1, "un désaccord, pas deux");
        assert_eq!(bilan.par_le_corpus, 1);
    }

    /// **La position, et non le numéro affiché.**
    ///
    /// Une unité qui couvre deux chapitres bibliques porte deux versets « 1 »
    /// (§2.2). Une table indexée par numéro donnerait au second la
    /// translittération du premier — sur cette unité-là seulement, et sans
    /// rien dire. C'est le défaut qui passe tous les essais sauf celui-ci.
    #[test]
    fn deux_versets_numero_un_recoivent_chacun_le_sien() {
        fn translit(t: &str, h: &str) -> Inline {
            Inline::Translit {
                translit: t.into(),
                hebrew: h.into(),
                cible: None,
            }
        }
        fn v(n: u32, noeud: Inline) -> crate::schema::Verse {
            crate::schema::Verse {
                n,
                nodes: vec![noeud],
            }
        }

        let unite = Chapter {
            id: "bereshit-7".into(),
            book_id: "bereshit".into(),
            kind: crate::schema::ChapterKind::Chapter,
            n: 7,
            title: "Bereshit 7".into(),
            title_nodes: Vec::new(),
            subtitle: None,
            status: crate::schema::Status::Brouillon,
            // Deux paragraphes : la position court **à travers** les blocs.
            blocks: vec![
                Block::Verses {
                    verses: vec![
                        v(1, translit("ʾElohim", "אֱלֹהִים")),
                        v(2, translit("bara", "בָּרָא")),
                    ],
                },
                Block::Verses {
                    // Gn 8 s'ouvre : la numérotation repart à ¹.
                    verses: vec![v(1, translit("ʾelohim", "אֱלֹהִים"))],
                },
            ],
            footer: None,
            verse_count: 3,
            lemmas: Vec::new(),
            source: String::new(),
        };

        let table = translitterations(std::slice::from_ref(&unite));
        let mut bilan = BilanDesTranslitterations::default();
        assert_eq!(
            table.a_l_occurrence("bereshit-7", 0, "אֱלֹהִ֑ים", &mut bilan),
            Some("ʾElohim".to_string()),
            "position 0 — le premier verset « 1 »"
        );
        assert_eq!(
            table.a_l_occurrence("bereshit-7", 2, "אֱלֹהִ֖ים", &mut bilan),
            Some("ʾelohim".to_string()),
            "position 2 — le second verset « 1 », dans le bloc suivant"
        );
        assert_eq!(
            bilan.recuperes, 2,
            "les deux seraient muets sans leur verset"
        );
    }

    /// **Le parcours descend dans les gloses**, et ça se mesure.
    ///
    /// `(*chesed* / חֶסֶד)` s'écrit le plus souvent *dans* un commentaire. Un
    /// parcours de surface récolterait simplement moins, sans rien dire — la
    /// couverture tomberait, et rien n'en nommerait la cause.
    #[test]
    fn la_recolte_descend_dans_la_glose_et_le_pied_de_page() {
        fn translit(t: &str, h: &str) -> Inline {
            Inline::Translit {
                translit: t.into(),
                hebrew: h.into(),
                cible: None,
            }
        }

        let blocs = vec![
            Block::Verses {
                verses: vec![crate::schema::Verse {
                    n: 1,
                    nodes: vec![Inline::Gloss {
                        children: vec![Inline::Em {
                            children: vec![translit("chesed", "חֶסֶד")],
                        }],
                    }],
                }],
            },
            Block::Para {
                nodes: vec![translit("bereshit", "בְּרֵאשִׁית")],
            },
        ];

        let mut couples = Vec::new();
        couples_des_blocs(&blocs, &mut couples);
        assert_eq!(couples.len(), 2, "la glose emboîtée compte comme le reste");

        let table =
            Translitterations::recoltee(couples.iter().map(|(t, h)| (t.as_str(), h.as_str())));
        assert_eq!(table.pour("חֶ֥סֶד"), Some("chesed".to_string()));
    }

    /// **Le veto du numéro, et les deux chemins par lesquels il arrive.**
    ///
    /// C'est l'épreuve du défaut qui était vivant dans le corpus le
    /// 11 septembre 2026 : `אֶל`, la préposition « vers » (413), ouvrait la
    /// fiche de `ʾEl` le nom divin (410) — **quatre-vingt-dix fois**, parce que
    /// leur squelette consonantique est le même et qu'aucune des deux fiches ne
    /// déclarait son numéro.
    #[test]
    fn le_numero_refuse_ce_que_la_forme_confond() {
        // `shem` déclare le sien : le veto part de la fiche.
        let liaison = LiaisonDesMots::nouvelle([FichePourLaJointure {
            lemme: "shem",
            hebreu: Some("שֵׁם"),
            strong: Some("8034"),
        }]);
        assert_eq!(
            liaison.cible("שֵׁ֣ם", Some("8034")),
            Some(CibleDuNiveauTrois::Term {
                lemma: "shem".into()
            })
        );
        // Même forme, autre numéro — *Shem fils de Noach*. On ne joint pas.
        assert_eq!(liaison.cible("שֵׁ֖ם", Some("8035")), None);

        // `el` ne déclare rien : le veto doit venir du témoin.
        let mut liaison = LiaisonDesMots::nouvelle([FichePourLaJointure {
            lemme: "el",
            hebreu: Some("אֵל"),
            strong: None,
        }]);
        // Sans apprentissage, le squelette confond — et c'est le code d'avant.
        assert_eq!(
            liaison.cible("אֶל", Some("413")),
            Some(CibleDuNiveauTrois::Term { lemma: "el".into() })
        );
        // Le témoin dit que `אֵל` porte 410, et rien d'autre.
        liaison.apprendre_du_temoin([
            ("אֵ֣ל".to_string(), "410".to_string()),
            ("אֵל".to_string(), "410".to_string()),
        ]);
        assert_eq!(liaison.cible("אֶל", Some("413")), None);
        assert_eq!(
            liaison.cible("אֵ֣ל", Some("410")),
            Some(CibleDuNiveauTrois::Term { lemma: "el".into() })
        );
    }

    /// Le numéro du témoin porte le préfixe de segmentation ; le lemme non.
    #[test]
    fn le_prefixe_du_temoin_ne_fait_pas_partie_du_lemme() {
        assert_eq!(numero_nu("c/559"), "559");
        assert_eq!(numero_nu("c/d/776"), "776");
        assert_eq!(numero_nu("1254 a"), "1254 a");
        assert_eq!(numero_nu("430"), "430");
    }

    /// **L'estampille des sources suit celle du corpus, ou reste vide.**
    ///
    /// Le manifeste des sources est né sans date, et personne ne l'a vu tant
    /// que personne n'a eu à comparer deux générations. Cette épreuve garde la
    /// forme : vingt signes, UTC, secondes obligatoires — et **vide** dès que
    /// ce n'est pas exactement ça.
    ///
    /// Une date mal formée est pire qu'aucune : les liseuses comparent ces
    /// chaînes, et une forme voisine s'ordonne n'importe comment.
    #[test]
    fn l_estampille_des_sources_est_vide_ou_bien_formee() {
        let genere = crate::config::genere();
        assert!(
            genere.is_empty() || crate::config::bien_formee(&genere),
            "estampille ni vide ni bien formée : « {genere} »"
        );
    }

    fn verset(n: u32) -> VersetPublie {
        VersetPublie {
            n,
            t: String::new(),
            mots: Vec::new(),
        }
    }

    #[test]
    fn une_divergence_tombe_sur_sa_position() {
        let plage = vec![(3, 1), (3, 2), (3, 3)];
        let versets: Vec<_> = (1..=3).map(verset).collect();
        let mut par_ref = BTreeMap::new();
        par_ref.insert((3, 2), vec![entree(3, 2, "δεύτερον")]);

        let out = attacher(&plage, &versets, &par_ref);
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].i, 1, "la deuxième position, non la deuxième clé");
        assert_eq!(out[0].n, 2);
    }

    /// Le cas qui justifie tout le dispositif : une unité qui couvre deux
    /// chapitres bibliques porte deux fois un verset « 1 ». Accrochées par
    /// numéro, les deux divergences se confondraient ; accrochées par
    /// position, elles restent distinctes.
    #[test]
    fn deux_versets_numero_un_ne_se_confondent_pas() {
        // Gn 7:1-2 puis Gn 8:1-2 — la numérotation ONT repart à ¹.
        let plage = vec![(7, 1), (7, 2), (8, 1), (8, 2)];
        let versets = vec![verset(1), verset(2), verset(1), verset(2)];
        let mut par_ref = BTreeMap::new();
        par_ref.insert((7, 1), vec![entree(7, 1, "premier")]);
        par_ref.insert((8, 1), vec![entree(8, 1, "second")]);

        let out = attacher(&plage, &versets, &par_ref);
        assert_eq!(out.len(), 2);
        assert_eq!((out[0].i, out[0].n), (0, 1));
        assert_eq!((out[1].i, out[1].n), (2, 1), "même numéro, autre position");
        assert_ne!(out[0].lecon, out[1].lecon);
    }

    #[test]
    fn plusieurs_divergences_sur_un_meme_verset_sont_gardees() {
        let plage = vec![(1, 1)];
        let versets = vec![verset(1)];
        let mut par_ref = BTreeMap::new();
        par_ref.insert(
            (1, 1),
            vec![entree(1, 1, "première"), entree(1, 1, "seconde")],
        );

        let out = attacher(&plage, &versets, &par_ref);
        assert_eq!(out.len(), 2, "un verset porte souvent plusieurs entrées");
        assert!(out.iter().all(|d| d.i == 0));
    }

    /// ⟦WH⟧ dit « imprimé mais tenu pour douteux ». Aplati, il ferait dire à
    /// Westcott-Hort le contraire de ce qu'ils ont voulu dire — et il tombe
    /// sur la sueur de sang de Luc 22 et la finale longue de Marc.
    #[test]
    fn le_doute_de_westcott_hort_survit_a_la_jointure() {
        let plage = vec![(22, 43)];
        let versets = vec![verset(1)];
        let mut e = entree(22, 43, "καὶ ἐγένετο");
        e.crochets = vec!["WH".into()];
        let mut par_ref = BTreeMap::new();
        par_ref.insert((22, 43), vec![e]);

        let out = attacher(&plage, &versets, &par_ref);
        assert_eq!(out[0].crochets, vec!["WH".to_string()]);
        assert!(
            !out[0].editions.contains(&"WH".to_string()) || !out[0].crochets.is_empty(),
            "le doute ne doit pas se confondre avec l'appui"
        );
    }

    /// Une unité sans divergence n'émet rien — et surtout pas un fichier vide,
    /// qui ferait croire à une couche présente et muette.
    #[test]
    fn une_unite_sans_divergence_ne_rend_rien() {
        let plage = vec![(1, 1), (1, 2)];
        let versets = vec![verset(1), verset(2)];
        let out = attacher(&plage, &versets, &BTreeMap::new());
        assert!(out.is_empty());
    }
}
