//! Présente les mots hébreux que deux fiches se disputent, et que le pipeline
//! a laissés inertes faute de pouvoir les départager.
//!
//!     cargo run --bin departager
//!
//! ## Pourquoi un outil, et pas une règle de plus
//!
//! Quand deux fiches déclarent le même numéro de Strong — `raah` et `roeh`,
//! `elohim` et `yhwh-elohim` —, le pipeline tranche par ce que **les deux
//! côtés déclarent** : si une seule des candidates porte la forme hébraïque du
//! mot, c'est elle. Rien n'est deviné.
//!
//! Le reste est fléchi. `וַיַּרְא` ne ressemble ni à `רָאָה` ni à `רֹאֶה`, et les
//! départager demanderait de savoir laquelle des deux fiches est un verbe et
//! laquelle est un nom. **Rien ne le déclare.** Une règle inventée là rendrait
//! le mot touchable vers la mauvaise fiche, sans que le lecteur puisse le voir
//! — c'est exactement le défaut que la garde vient de fermer.
//!
//! Donc : le pipeline ne devine pas, et cet outil montre au vault ce qu'il lui
//! reste à déclarer. **Une fois**, dans le corpus, plutôt qu'à chaque build.
//!
//! ## Ce qu'il ne fait pas, et pourquoi
//!
//! Il ne propose pas de réponse. Il pourrait — un modèle local lirait ces cas
//! et rédigerait des propositions —, et ce serait utile le jour où les paires
//! se compteront par centaines. Mais **jamais dans le pipeline** : la CI
//! construit le corpus sans ce modèle, et deux machines rendraient alors deux
//! corpus pour le même vault. Ce qui entre dans `dist/` doit être
//! reproductible par quiconque a le vault et le dépôt.
//!
//! La sortie est donc structurée pour deux lecteurs : l'auteur aujourd'hui, un
//! outil demain.

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

use ont::schema::GlossaryFile;
use ont::sources::{FichePourLaJointure, LiaisonDesMots, LivreSources};

/// Un mot resté inerte, avec de quoi trancher.
struct Cas {
    unite: String,
    verset: u32,
    forme: String,
    morphologie: String,
    strong: String,
    verset_entier: String,
}

fn main() {
    let racine = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("le pipeline a un parent")
        .to_path_buf();
    let dist = racine.join("dist");

    let liaison = match charger(&dist) {
        Ok(l) => l,
        Err(message) => {
            eprintln!("échec : {message}");
            std::process::exit(1);
        }
    };

    let mut par_paire: BTreeMap<Vec<String>, Vec<Cas>> = BTreeMap::new();
    let mut lus = 0_u32;

    let sources = dist.join("sources");
    for temoin in dossiers(&sources) {
        for fichier in fichiers_json(&temoin) {
            let Ok(brut) = fs::read_to_string(&fichier) else {
                continue;
            };
            let Ok(livre) = serde_json::from_str::<LivreSources>(&brut) else {
                eprintln!("illisible, ignoré : {}", fichier.display());
                continue;
            };
            for (unite, versets) in &livre.unites {
                for v in versets {
                    for m in &v.mots {
                        lus += 1;
                        // **Seuls les inertes.** Un mot que la garde a tranché
                        // n'a rien à faire ici : il ouvre déjà la bonne fiche.
                        if m.cible.is_some() {
                            continue;
                        }
                        let pretendants = liaison.pretendants(&m.t, m.lem.as_deref());
                        if pretendants.is_empty() {
                            continue;
                        }
                        par_paire
                            .entry(pretendants.to_vec())
                            .or_default()
                            .push(Cas {
                                unite: unite.clone(),
                                verset: v.n,
                                forme: m.t.clone(),
                                morphologie: m.morph.clone().unwrap_or_default(),
                                strong: m.lem.clone().unwrap_or_default(),
                                verset_entier: v.t.clone(),
                            });
                    }
                }
            }
        }
    }

    ecrire(&liaison, &par_paire, lus);
}

fn charger(dist: &Path) -> Result<LiaisonDesMots, String> {
    let chemin = dist.join("glossary.json");
    let brut = fs::read_to_string(&chemin).map_err(|e| {
        format!(
            "{} illisible — {e}. Lancez `scripts/corpus.sh`.",
            chemin.display()
        )
    })?;
    let fichier: GlossaryFile =
        serde_json::from_str(&brut).map_err(|e| format!("{} mal formé — {e}", chemin.display()))?;
    Ok(LiaisonDesMots::nouvelle(fichier.entries.iter().map(|e| {
        FichePourLaJointure {
            lemme: e.lemma.as_str(),
            hebreu: e.hebrew.as_deref(),
            strong: e.strong.as_deref(),
        }
    })))
}

fn dossiers(sous: &Path) -> Vec<PathBuf> {
    let Ok(entrees) = fs::read_dir(sous) else {
        return Vec::new();
    };
    let mut out: Vec<PathBuf> = entrees
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.is_dir())
        .collect();
    out.sort();
    out
}

fn fichiers_json(dans: &Path) -> Vec<PathBuf> {
    let Ok(entrees) = fs::read_dir(dans) else {
        return Vec::new();
    };
    let mut out: Vec<PathBuf> = entrees
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.extension().is_some_and(|x| x == "json"))
        .collect();
    out.sort();
    out
}

/// **Le compte voyage avec son dénominateur.**
///
/// « 144 mots » ne dit rien seul : il faut savoir sur combien, et combien de
/// paires. Sans ça, un outil qui n'a rien regardé rend la même sortie qu'un
/// outil qui a tout vu.
fn ecrire(liaison: &LiaisonDesMots, par_paire: &BTreeMap<Vec<String>, Vec<Cas>>, lus: u32) {
    let total: usize = par_paire.values().map(Vec::len).sum();
    println!("# Mots que deux fiches se disputent\n");
    println!(
        "{total} mots inertes sur {lus} étiquetés, répartis sur {} paire(s).\n",
        par_paire.len()
    );
    if par_paire.is_empty() {
        println!("Rien à départager.");
        return;
    }

    // Les paires les plus fréquentes d'abord : c'est par elles que le vault
    // gagne le plus de mots par décision prise.
    let mut paires: Vec<(&Vec<String>, &Vec<Cas>)> = par_paire.iter().collect();
    paires.sort_by_key(|(_, cas)| std::cmp::Reverse(cas.len()));

    for (pretendants, cas) in paires {
        println!("## {} — {} mot(s)\n", pretendants.join(" / "), cas.len());
        for lemme in pretendants {
            match liaison.hebreu_declare(lemme) {
                Some(h) => println!("- `{lemme}` déclare **{h}**"),
                None => println!("- `{lemme}` ne déclare aucune forme hébraïque"),
            }
        }
        println!();

        // Groupées par forme : un même mot revient souvent, et une décision le
        // couvre en entier. C'est la vraie unité de travail — sur Bereshit,
        // 144 mots se ramènent à une douzaine de décisions.
        let mut par_forme: BTreeMap<(&str, &str), Vec<&Cas>> = BTreeMap::new();
        for c in cas {
            par_forme
                .entry((c.forme.as_str(), c.morphologie.as_str()))
                .or_default()
                .push(c);
        }
        let mut formes: Vec<((&str, &str), Vec<&Cas>)> = par_forme.into_iter().collect();
        formes.sort_by_key(|(_, v)| std::cmp::Reverse(v.len()));

        for ((forme, morph), occurrences) in formes {
            let premier = occurrences.first().expect("un groupe n'est jamais vide");
            println!(
                "### {forme} · `{morph}` · Strong {} — {} fois",
                premier.strong,
                occurrences.len()
            );
            println!(
                "\n> {} {}:{}\n> {}\n",
                premier.unite, premier.unite, premier.verset, premier.verset_entier
            );
        }
    }

    println!("---\n");
    println!(
        "Ce que le vault déclare ici se lit à chaque build. Ce que cet outil \
         devine ne se lit nulle part — c'est pourquoi il ne devine pas."
    );
}
