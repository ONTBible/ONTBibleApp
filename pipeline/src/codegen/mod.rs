//! L'engendrement des liaisons — `schema.rs` devient du Swift et du Kotlin.
//!
//! ## Pourquoi engendrer plutôt que recopier
//!
//! Le schéma était décrit trois fois : ici, dans le site, dans l'app. Le site
//! ne le redécrit plus — il dépend de `schema` comme d'une caisse, et une
//! divergence y casse la compilation. Swift ne peut pas faire ça : il ne
//! compile pas de Rust.
//!
//! Alors on écrit le Swift **à sa place**. Le fichier produit n'est pas dans le
//! dépôt : il naît à chaque build, comme `dist/` et comme `ONT.xcodeproj`. Il
//! ne peut donc pas être périmé — il n'y a rien à déclencher, rien à penser à
//! relancer.
//!
//! ## Deux étages, et c'est ce qui rend Android gratuit
//!
//! ```text
//!   schema.rs ──[syn]──▶ Modele ──┬──▶ swift.rs  ──▶ Schema.swift
//!                                 └──▶ kotlin.rs ──▶ Schema.kt
//! ```
//!
//! Le `Modele` ne connaît ni Swift ni Rust : ce sont des types, des champs, des
//! variantes et des clés JSON. Ajouter un langage, c'est ajouter un émetteur —
//! pas retoucher la lecture.
//!
//! ## Ce qui est engendré, et ce qui ne l'est pas
//!
//! On part des **fichiers publiés** — `CorpusFile`, `Book`, `GlossaryFile`… —
//! et on suit les types qu'ils atteignent. Le reste ne sort pas.
//!
//! C'est ce qui écarte `Corpus`, `Mode` et compagnie : ce sont les formes
//! d'assemblage du pipeline, vivantes en mémoire pendant un build et jamais
//! écrites nulle part. Les émettre donnerait à une liseuse des types qui ne
//! correspondent à aucun fichier — de la surface d'API sans contrepartie.
//!
//! L'alternative aurait été une liste de types à tenir à la main, donc une
//! liste de plus à oublier de mettre à jour.

pub mod kotlin;
pub mod swift;

use std::collections::{BTreeSet, VecDeque};

/// Le schéma, dépouillé de tout ce qui est propre à Rust.
#[derive(Debug, Clone)]
pub struct Modele {
    pub types: Vec<Decl>,
}

impl Modele {
    pub fn trouver(&self, nom: &str) -> Option<&Decl> {
        self.types.iter().find(|d| d.nom() == nom)
    }
}

#[derive(Debug, Clone)]
pub enum Decl {
    Structure(Structure),
    Enumeration(Enumeration),
}

impl Decl {
    pub fn nom(&self) -> &str {
        match self {
            Decl::Structure(s) => &s.nom,
            Decl::Enumeration(e) => &e.nom,
        }
    }

    /// Les types nommés que cette déclaration atteint directement.
    fn voisins(&self) -> Vec<String> {
        let mut sortie = Vec::new();
        match self {
            Decl::Structure(s) => {
                for champ in &s.champs {
                    champ.type_.noms(&mut sortie);
                }
            }
            Decl::Enumeration(e) => {
                for variante in &e.variantes {
                    for champ in &variante.champs {
                        champ.type_.noms(&mut sortie);
                    }
                }
            }
        }
        sortie
    }
}

#[derive(Debug, Clone)]
pub struct Structure {
    pub nom: String,
    pub doc: Vec<String>,
    pub champs: Vec<Champ>,
}

#[derive(Debug, Clone)]
pub struct Champ {
    /// Le nom côté JSON, après `rename_all`. C'est lui qui fait foi : le nom
    /// Rust n'existe que dans `schema.rs`.
    pub cle: String,
    pub doc: Vec<String>,
    pub type_: Type,
    /// La clé peut **manquer** du fichier.
    ///
    /// Vrai dès que le champ porte `skip_serializing_if` ou `default` : le
    /// premier dit que le pipeline n'écrira pas la clé dans certains cas, le
    /// second que serde sait s'en passer.
    ///
    /// ## Pourquoi ça a sa place dans le modèle
    ///
    /// Ce module a longtemps ignoré ces deux attributs, au motif qu'ils ne
    /// changent pas la **forme** des données mais la façon de les produire.
    /// C'est vrai d'un producteur, et faux d'un décodeur : « cette clé peut
    /// être absente » est précisément une propriété de forme, et c'est la
    /// seule chose qu'un décodeur a besoin de savoir pour ne pas échouer.
    ///
    /// Le défaut est resté sans effet tant que `schema.rs` n'a porté aucun de
    /// ces attributs. Le premier `Vec` escamotable ajouté au schéma aurait
    /// engendré, des deux côtés, un champ obligatoire pour une clé omise — et
    /// une liseuse en production qui n'ouvre plus rien.
    pub escamotable: bool,
}

#[derive(Debug, Clone)]
pub struct Enumeration {
    pub nom: String,
    pub doc: Vec<String>,
    /// `Some("t")` pour une union étiquetée — `{"t":"text","v":"…"}`.
    ///
    /// `None` pour une énumération qui se sérialise en simple chaîne, comme
    /// `Status`. Les deux demandent un décodage très différent, et c'est la
    /// seule chose que l'émetteur a besoin de savoir pour les distinguer.
    pub etiquette: Option<String>,
    pub variantes: Vec<Variante>,
}

#[derive(Debug, Clone)]
pub struct Variante {
    /// La valeur côté JSON — `"text"`, `"para"`, `"locked"`.
    pub cle: String,
    pub doc: Vec<String>,
    /// Vide pour une variante sans charge utile.
    pub champs: Vec<Champ>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Type {
    Chaine,
    Entier,
    Booleen,
    Optionnel(Box<Type>),
    Liste(Box<Type>),
    /// Une table dont les clés sont des chaînes — `byLemma`.
    Table(Box<Type>),
    Nomme(String),
}

impl Type {
    fn noms(&self, dans: &mut Vec<String>) {
        match self {
            Type::Nomme(n) => dans.push(n.clone()),
            Type::Optionnel(t) | Type::Liste(t) | Type::Table(t) => t.noms(dans),
            _ => {}
        }
    }
}

/// Les racines : un fichier que les liseuses **lisent** par entrée.
///
/// `Manifest` n'en fait pas partie, et c'est un faux ami qu'il vaut mieux
/// nommer. `dist/manifest.json` est un rapport de build — des chiffres et des
/// anomalies, que rien n'affiche. Le manifeste dont l'app se sert pour savoir
/// si son corpus a vieilli est `manifeste.json`, produit par le **site** dans
/// `corpus-publie.py`, avec ses empreintes et ses tailles : une autre forme,
/// un autre fichier, un autre producteur.
///
/// L'engendrer donnerait à Swift un type qu'aucun appel ne toucherait — le même
/// reproche qu'on fait aux formes d'assemblage. Le jour où une liseuse en aura
/// besoin, une ligne ici suffira.
pub const RACINES: &[&str] = &[
    "CorpusFile",
    "Book",
    "GlossaryFile",
    "ShemotFile",
    "OccurrencesFile",
    "SearchFile",
    "DailyFile",
];

/// Réduit le modèle à ce que les racines atteignent, en largeur d'abord.
///
/// L'ordre de sortie est celui de `schema.rs` — un fichier engendré dont
/// l'ordre change à chaque exécution est illisible en `diff`, et on ne verrait
/// plus les vraies modifications parmi le bruit.
pub fn atteignables(modele: &Modele, racines: &[&str]) -> Modele {
    let mut vus: BTreeSet<String> = BTreeSet::new();
    let mut file: VecDeque<String> = racines.iter().map(|r| r.to_string()).collect();

    while let Some(nom) = file.pop_front() {
        if !vus.insert(nom.clone()) {
            continue;
        }
        let Some(decl) = modele.trouver(&nom) else {
            // Une racine absente est une faute de frappe dans `RACINES`, ou un
            // type retiré de `schema.rs` sans que la liste suive. On le dit
            // fort plutôt que d'engendrer un fichier incomplet.
            panic!("le type « {nom} » est attendu mais absent de schema.rs");
        };
        for voisin in decl.voisins() {
            if !vus.contains(&voisin) {
                file.push_back(voisin);
            }
        }
    }

    Modele {
        types: modele
            .types
            .iter()
            .filter(|d| vus.contains(d.nom()))
            .cloned()
            .collect(),
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// La lecture de `schema.rs`
// ─────────────────────────────────────────────────────────────────────────────

/// Analyse le fichier du schéma.
pub fn lire(source: &str) -> Result<Modele, String> {
    let fichier = syn::parse_file(source).map_err(|e| format!("schema.rs illisible : {e}"))?;

    let mut types = Vec::new();
    for item in &fichier.items {
        match item {
            syn::Item::Struct(s) => types.push(Decl::Structure(structure(s)?)),
            syn::Item::Enum(e) => types.push(Decl::Enumeration(enumeration(e)?)),
            _ => {}
        }
    }
    Ok(Modele { types })
}

fn structure(item: &syn::ItemStruct) -> Result<Structure, String> {
    let serde = attributs_serde(&item.attrs);
    let syn::Fields::Named(nommes) = &item.fields else {
        return Err(format!(
            "{} : seuls les champs nommés sont gérés",
            item.ident
        ));
    };

    let mut champs = Vec::new();
    for champ in &nommes.named {
        let nom = champ.ident.as_ref().expect("champ nommé").to_string();
        let propre = attributs_serde(&champ.attrs);
        champs.push(Champ {
            cle: propre
                .rename
                .clone()
                .unwrap_or_else(|| renommer(&nom, serde.rename_all.as_deref())),
            doc: docs(&champ.attrs),
            type_: type_de(&champ.ty)?,
            escamotable: propre.escamotable,
        });
    }

    Ok(Structure {
        nom: item.ident.to_string(),
        doc: docs(&item.attrs),
        champs,
    })
}

fn enumeration(item: &syn::ItemEnum) -> Result<Enumeration, String> {
    let serde = attributs_serde(&item.attrs);

    let mut variantes = Vec::new();
    for variante in &item.variants {
        let nom = variante.ident.to_string();
        let propre = attributs_serde(&variante.attrs);

        let champs = match &variante.fields {
            syn::Fields::Unit => Vec::new(),
            syn::Fields::Named(nommes) => {
                let mut sortie = Vec::new();
                for champ in &nommes.named {
                    let nom = champ.ident.as_ref().expect("champ nommé").to_string();
                    sortie.push(Champ {
                        // Les champs d'une variante ne suivent **pas** le
                        // `rename_all` du type : celui-ci porte sur les noms de
                        // variantes. `Inline` en est la preuve — ses variantes
                        // sont en minuscules, mais son champ `lemma` garde son
                        // nom tel quel.
                        cle: nom.clone(),
                        doc: docs(&champ.attrs),
                        type_: type_de(&champ.ty)?,
                        escamotable: attributs_serde(&champ.attrs).escamotable,
                    });
                }
                sortie
            }
            syn::Fields::Unnamed(_) => {
                return Err(format!(
                    "{}::{nom} : les variantes à champs anonymes ne sont pas gérées",
                    item.ident
                ))
            }
        };

        variantes.push(Variante {
            cle: propre
                .rename
                .clone()
                .unwrap_or_else(|| renommer(&nom, serde.rename_all.as_deref())),
            doc: docs(&variante.attrs),
            champs,
        });
    }

    Ok(Enumeration {
        nom: item.ident.to_string(),
        doc: docs(&item.attrs),
        etiquette: serde.tag.clone(),
        variantes,
    })
}

#[derive(Default)]
struct Serde {
    rename_all: Option<String>,
    rename: Option<String>,
    tag: Option<String>,
    /// `default` ou `skip_serializing_if` — voir [`Champ::escamotable`].
    escamotable: bool,
}

fn attributs_serde(attrs: &[syn::Attribute]) -> Serde {
    let mut sortie = Serde::default();
    for attr in attrs {
        if !attr.path().is_ident("serde") {
            continue;
        }
        // Les clés qu'on ne connaît pas restent ignorées : elles ne changent
        // ni la forme des données ni la façon de les lire.
        //
        // `default` et `skip_serializing_if` font exception, et c'est une
        // correction : ils disent qu'une clé peut manquer, ce qu'un décodeur
        // doit savoir. Les tenir pour de simples détails de production a
        // engendré des champs obligatoires pour des clés omises.
        let _ = attr.parse_nested_meta(|meta| {
            if meta.path.is_ident("default") || meta.path.is_ident("skip_serializing_if") {
                sortie.escamotable = true;
                // `default` s'écrit seul ou avec une valeur ; consommer celle-ci
                // quand elle est là, pour ne pas arrêter la lecture des autres.
                if let Ok(valeur) = meta.value() {
                    let _ = valeur.parse::<syn::LitStr>();
                }
                return Ok(());
            }
            let cible = if meta.path.is_ident("rename_all") {
                &mut sortie.rename_all
            } else if meta.path.is_ident("rename") {
                &mut sortie.rename
            } else if meta.path.is_ident("tag") {
                &mut sortie.tag
            } else {
                return Ok(());
            };
            if let Ok(valeur) = meta.value() {
                if let Ok(litteral) = valeur.parse::<syn::LitStr>() {
                    *cible = Some(litteral.value());
                }
            }
            Ok(())
        });
    }
    sortie
}

fn docs(attrs: &[syn::Attribute]) -> Vec<String> {
    attrs
        .iter()
        .filter(|a| a.path().is_ident("doc"))
        .filter_map(|a| match &a.meta {
            syn::Meta::NameValue(nv) => match &nv.value {
                syn::Expr::Lit(syn::ExprLit {
                    lit: syn::Lit::Str(s),
                    ..
                }) => Some(s.value().trim_end().to_string()),
                _ => None,
            },
            _ => None,
        })
        .collect()
}

fn renommer(nom: &str, regle: Option<&str>) -> String {
    match regle {
        Some("lowercase") => nom.to_lowercase(),
        Some("camelCase") => camel(nom),
        Some("snake_case") | None => nom.to_string(),
        Some(autre) => panic!("règle de renommage serde inconnue : « {autre} »"),
    }
}

/// `book_id` → `bookId`. Les noms Rust sont en serpent, jamais en Pascal, quand
/// cette règle s'applique — elle ne porte que sur des champs.
fn camel(nom: &str) -> String {
    let mut sortie = String::with_capacity(nom.len());
    let mut majuscule = false;
    for c in nom.chars() {
        if c == '_' {
            majuscule = true;
        } else if majuscule {
            sortie.extend(c.to_uppercase());
            majuscule = false;
        } else {
            sortie.push(c);
        }
    }
    sortie
}

fn type_de(ty: &syn::Type) -> Result<Type, String> {
    let syn::Type::Path(chemin) = ty else {
        return Err(format!("type non géré : {}", quote(ty)));
    };
    let segment = chemin
        .path
        .segments
        .last()
        .ok_or_else(|| "chemin de type vide".to_string())?;
    let nom = segment.ident.to_string();

    let mut arguments: Vec<&syn::Type> = Vec::new();
    if let syn::PathArguments::AngleBracketed(entre) = &segment.arguments {
        for argument in &entre.args {
            if let syn::GenericArgument::Type(t) = argument {
                arguments.push(t);
            }
        }
    }

    Ok(match nom.as_str() {
        "String" | "str" => Type::Chaine,
        "bool" => Type::Booleen,
        "u8" | "u16" | "u32" | "u64" | "usize" | "i8" | "i16" | "i32" | "i64" | "isize" => {
            Type::Entier
        }
        "Option" => Type::Optionnel(Box::new(type_de(arguments[0])?)),
        "Vec" => Type::Liste(Box::new(type_de(arguments[0])?)),
        "BTreeMap" | "HashMap" => {
            // La clé est toujours une chaîne dans ce schéma, et il vaut mieux
            // le vérifier que le supposer : une table à clés entières se
            // décoderait tout autrement côté Swift.
            if type_de(arguments[0])? != Type::Chaine {
                return Err(format!("{nom} : seules les clés chaînes sont gérées"));
            }
            Type::Table(Box::new(type_de(arguments[1])?))
        }
        _ => Type::Nomme(nom),
    })
}

fn quote(ty: &syn::Type) -> String {
    match ty {
        syn::Type::Path(p) => p
            .path
            .segments
            .iter()
            .map(|s| s.ident.to_string())
            .collect::<Vec<_>>()
            .join("::"),
        _ => "?".into(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn modele(source: &str) -> Modele {
        lire(source).expect("source analysable")
    }

    #[test]
    fn une_structure_suit_son_rename_all() {
        let m = modele(
            r#"
            #[serde(rename_all = "camelCase")]
            pub struct Chapter {
                pub id: String,
                pub book_id: String,
                pub verse_count: u32,
            }
        "#,
        );
        let Decl::Structure(s) = &m.types[0] else {
            panic!("structure attendue")
        };
        let cles: Vec<&str> = s.champs.iter().map(|c| c.cle.as_str()).collect();
        assert_eq!(cles, ["id", "bookId", "verseCount"]);
    }

    #[test]
    fn une_union_etiquetee_garde_ses_champs_tels_quels() {
        // Le piège : `rename_all` porte sur les **variantes**, pas sur leurs
        // champs. `lemma` reste `lemma` même sous `rename_all = "lowercase"`.
        let m = modele(
            r#"
            #[serde(tag = "t", rename_all = "lowercase")]
            pub enum Inline {
                Text { v: String },
                Term { v: String, lemma: String },
                Break,
            }
        "#,
        );
        let Decl::Enumeration(e) = &m.types[0] else {
            panic!("énumération attendue")
        };
        assert_eq!(e.etiquette.as_deref(), Some("t"));
        let cles: Vec<&str> = e.variantes.iter().map(|v| v.cle.as_str()).collect();
        assert_eq!(cles, ["text", "term", "break"]);
        assert_eq!(e.variantes[1].champs[1].cle, "lemma");
        assert!(e.variantes[2].champs.is_empty());
    }

    #[test]
    fn une_enumeration_sans_etiquette_se_distingue() {
        let m = modele(
            r#"
            #[serde(rename_all = "lowercase")]
            pub enum Status { Locked, Brouillon }
        "#,
        );
        let Decl::Enumeration(e) = &m.types[0] else {
            panic!("énumération attendue")
        };
        assert!(e.etiquette.is_none(), "pas d'étiquette : c'est une chaîne");
    }

    #[test]
    fn les_types_composes_se_lisent() {
        let m = modele(
            r#"
            pub struct F {
                pub a: Option<String>,
                pub b: Vec<Vec<Inline>>,
                pub c: BTreeMap<String, Vec<Occurrence>>,
                pub d: bool,
                pub e: u32,
            }
        "#,
        );
        let Decl::Structure(s) = &m.types[0] else {
            panic!()
        };
        assert_eq!(s.champs[0].type_, Type::Optionnel(Box::new(Type::Chaine)));
        assert_eq!(
            s.champs[1].type_,
            Type::Liste(Box::new(Type::Liste(Box::new(Type::Nomme(
                "Inline".into()
            )))))
        );
        assert_eq!(
            s.champs[2].type_,
            Type::Table(Box::new(Type::Liste(Box::new(Type::Nomme(
                "Occurrence".into()
            )))))
        );
        assert_eq!(s.champs[3].type_, Type::Booleen);
        assert_eq!(s.champs[4].type_, Type::Entier);
    }

    #[test]
    fn seul_ce_que_les_racines_atteignent_sort() {
        let m = modele(
            r#"
            pub struct DailyFile { pub verses: Vec<DailyVerse> }
            pub struct DailyVerse { pub b: String }
            /// Une forme d'assemblage, jamais écrite dans un fichier.
            pub struct Corpus { pub modes: Vec<Mode> }
            pub struct Mode { pub id: String }
        "#,
        );
        let reduit = atteignables(&m, &["DailyFile"]);
        let noms: Vec<&str> = reduit.types.iter().map(|d| d.nom()).collect();
        assert_eq!(noms, ["DailyFile", "DailyVerse"]);
    }

    #[test]
    fn l_ordre_de_schema_rs_est_conservé() {
        // Un fichier engendré dont l'ordre bouge d'une exécution à l'autre
        // rendrait tout `diff` illisible.
        let m = modele(
            r#"
            pub struct A { pub b: B, pub c: C }
            pub struct C { pub x: String }
            pub struct B { pub y: String }
        "#,
        );
        let reduit = atteignables(&m, &["A"]);
        let noms: Vec<&str> = reduit.types.iter().map(|d| d.nom()).collect();
        assert_eq!(noms, ["A", "C", "B"], "l'ordre du fichier, pas du parcours");
    }

    #[test]
    #[should_panic(expected = "absent de schema.rs")]
    fn une_racine_absente_se_dit() {
        atteignables(&modele("pub struct A { pub x: String }"), &["Inexistant"]);
    }
}
