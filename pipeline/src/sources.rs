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

use crate::schema::{Block, Chapter};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
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
}

// ───────────────────────────── ce qu'on émet ──────────────────────────────

#[derive(Debug, Clone, Serialize)]
pub struct ManifesteSources {
    pub schema: u32,
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
    /// Les unités écartées faute de jointure sûre. Rien de faux n'est émis.
    pub ecartees: Vec<String>,
    /// Ce qui mérite l'œil de l'auteur sans rien empêcher.
    pub releves: Vec<String>,
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
    let mut livres: BTreeMap<String, LivrePublie> = BTreeMap::new();
    let mut fichiers = Vec::new();

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

            // (chapitre, verset) → texte joint
            let mut par_ref: BTreeMap<(u32, u32), String> = BTreeMap::new();
            let mut par_chapitre: BTreeMap<u32, u32> = BTreeMap::new();
            for ligne in contenu.lines().filter(|l| !l.trim().is_empty()) {
                let v: VersetSource = serde_json::from_str(ligne)
                    .map_err(|e| format!("{} : ligne illisible — {e}", chemin.display()))?;
                let texte =
                    v.w.iter()
                        .map(|m| m.t.as_str())
                        .collect::<Vec<_>>()
                        .join(" ");
                par_ref.insert((v.c, v.v), texte);
                let e = par_chapitre.entry(v.c).or_insert(0);
                *e = (*e).max(v.v);
            }

            let mut unites_publiees: BTreeMap<String, Vec<VersetPublie>> = BTreeMap::new();
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
                    sortie.push(VersetPublie {
                        n: numeros.get(i).copied().unwrap_or((i + 1) as u32),
                        t: texte.clone(),
                    });
                }
                unites_publiees.insert(u.id.clone(), sortie);
            }

            if unites_publiees.is_empty() {
                continue; // le livre n'a pas encore d'unité écrite
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
            transmission: None,
            cause: None,
        });
        e.transmission = Some(phrase.clone());
        e.cause = Some(cause.clone());
    }

    Ok(Some(Preparation {
        manifeste: ManifesteSources {
            schema: 1,
            temoins,
            livres,
        },
        fichiers,
        ecartees: sautees,
        releves,
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
