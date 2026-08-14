//! L'émetteur Swift.
//!
//! ## Ce qu'il produit, et ce qu'il ne produit pas
//!
//! Des **DTO** — la forme exacte du JSON, et rien d'autre. Pas de méthode, pas
//! de confort, aucune décision. Ils vivent dans `ONTData`, la couche
//! d'adaptation, et le domaine d'`ONTKit` ne les voit jamais.
//!
//! C'est la règle des ports et adaptateurs, et elle est ici dans le bon sens
//! pour la première fois : `ONTKit` portait ses propres `Decodable`, donc le
//! domaine connaissait la forme du JSON du pipeline. Un champ renommé dans le
//! vault se propageait jusqu'au cœur de l'app.
//!
//! ## Tout est dans un espace de noms
//!
//! `enum ONTSchema` sans cas — l'idiome Swift pour un espace de noms. Sans lui,
//! `Chapter`, `Book` et `Occurrence` engendrés heurteraient les types du
//! domaine qui portent les mêmes noms, et il faudrait préfixer chaque usage.
//!
//! ## Pourquoi `Decodable` seul
//!
//! Une liseuse lit. Ajouter `Encodable` engendrerait du code que personne
//! n'appelle, et laisserait croire qu'une app peut réécrire le corpus — elle ne
//! le peut pas, c'est le pipeline qui l'écrit.

use std::fmt::Write;

use super::{Decl, Enumeration, Modele, Structure, Type};

/// Les mots que Swift se réserve et qui paraissent dans ce schéma.
///
/// Liste courte et **volontairement incomplète** : elle couvre ce que le schéma
/// produit réellement. `Inline::Break` en est l'unique cas aujourd'hui, et le
/// jour où un autre arrive, le Swift engendré ne compile pas — ce qui est
/// exactement le bon moment pour l'apprendre.
const RESERVES: &[&str] = &[
    "break",
    "case",
    "class",
    "continue",
    "default",
    "enum",
    "extension",
    "for",
    "func",
    "guard",
    "import",
    "in",
    "init",
    "internal",
    "let",
    "operator",
    "private",
    "protocol",
    "public",
    "repeat",
    "return",
    "self",
    "static",
    "struct",
    "switch",
    "throw",
    "true",
    "false",
    "var",
    "where",
    "while",
];

fn echapper(nom: &str) -> String {
    if RESERVES.contains(&nom) {
        format!("`{nom}`")
    } else {
        nom.to_string()
    }
}

fn swift_type(t: &Type) -> String {
    match t {
        Type::Chaine => "String".into(),
        Type::Entier => "Int".into(),
        Type::Booleen => "Bool".into(),
        Type::Optionnel(inner) => format!("{}?", swift_type(inner)),
        Type::Liste(inner) => format!("[{}]", swift_type(inner)),
        Type::Table(inner) => format!("[String: {}]", swift_type(inner)),
        Type::Nomme(n) => n.clone(),
    }
}

fn doc(sortie: &mut String, lignes: &[String], retrait: &str) {
    for ligne in lignes {
        if ligne.trim().is_empty() {
            let _ = writeln!(sortie, "{retrait}///");
        } else {
            let _ = writeln!(sortie, "{retrait}///{ligne}");
        }
    }
}

/// Écrit le fichier Swift complet.
pub fn emettre(modele: &Modele) -> String {
    let mut sortie = String::new();

    sortie.push_str(
        "// ENGENDRÉ PAR LE PIPELINE — NE PAS MODIFIER À LA MAIN.\n\
         //\n\
         // Source : pipeline/src/schema.rs\n\
         // Producteur : cargo run --bin engendrer\n\
         //\n\
         // Ce fichier n'est pas dans le dépôt. Il est réécrit à chaque build par\n\
         // `scripts/corpus.sh`, comme `dist/` et comme `ONT.xcodeproj` — donc il ne\n\
         // peut pas être périmé, et il n'y a rien à penser à relancer.\n\
         //\n\
         // Une modification faite ici disparaîtra au prochain build, sans un mot.\n\
         // Ce qu'il faut changer est `schema.rs`.\n\
         //\n\
         // Ce sont des **DTO** : la forme du JSON, et rien d'autre. Le domaine vit\n\
         // dans ONTKit et ne les connaît pas ; la traduction est dans SchemaMapping.swift.\n\n\
         import Foundation\n\n\
         public enum ONTSchema {\n",
    );

    for decl in &modele.types {
        sortie.push('\n');
        match decl {
            Decl::Structure(s) => structure(&mut sortie, s),
            Decl::Enumeration(e) => enumeration(&mut sortie, e),
        }
    }

    sortie.push_str("}\n");
    sortie
}

fn structure(sortie: &mut String, s: &Structure) {
    doc(sortie, &s.doc, "    ");
    let _ = writeln!(
        sortie,
        "    public struct {}: Decodable, Hashable, Sendable {{",
        s.nom
    );

    for champ in &s.champs {
        doc(sortie, &champ.doc, "        ");
        let _ = writeln!(
            sortie,
            "        public let {}: {}",
            echapper(&champ.cle),
            swift_type(&champ.type_)
        );
    }

    // Le `Decodable` synthétisé suffit tant que les noms Swift **sont** les
    // clés JSON. C'est le cas par construction : on nomme les propriétés
    // d'après la clé, jamais d'après le nom Rust. Un `CodingKeys` de plus ne
    // servirait qu'à répéter la même liste une seconde fois.
    let _ = writeln!(sortie, "    }}");
}

fn enumeration(sortie: &mut String, e: &Enumeration) {
    match &e.etiquette {
        None => enumeration_chaine(sortie, e),
        Some(etiquette) => enumeration_etiquetee(sortie, e, etiquette),
    }
}

fn enumeration_chaine(sortie: &mut String, e: &Enumeration) {
    doc(sortie, &e.doc, "    ");
    let _ = writeln!(
        sortie,
        "    public enum {}: String, Decodable, Hashable, Sendable {{",
        e.nom
    );
    for variante in &e.variantes {
        doc(sortie, &variante.doc, "        ");
        let nom = echapper(&variante.cle);
        // `case locked` suffit quand le nom Swift et la valeur JSON coïncident.
        // Ils coïncident toujours ici : on nomme d'après la clé.
        let _ = writeln!(sortie, "        case {nom}");
    }
    let _ = writeln!(sortie, "    }}");
}

fn enumeration_etiquetee(sortie: &mut String, e: &Enumeration, etiquette: &str) {
    doc(sortie, &e.doc, "    ");
    let _ = writeln!(
        sortie,
        "    public enum {}: Decodable, Hashable, Sendable {{",
        e.nom
    );

    for variante in &e.variantes {
        doc(sortie, &variante.doc, "        ");
        let _ = writeln!(sortie, "        case {}{}", echapper(&variante.cle), {
            if variante.champs.is_empty() {
                String::new()
            } else {
                let parametres: Vec<String> = variante
                    .champs
                    .iter()
                    .map(|c| format!("{}: {}", echapper(&c.cle), swift_type(&c.type_)))
                    .collect();
                format!("({})", parametres.join(", "))
            }
        });
    }

    // Les clés de décodage : l'étiquette, plus l'union de tous les champs de
    // toutes les variantes. Swift n'a pas d'union étiquetée native — c'est ce
    // qui oblige à écrire ce `init(from:)` à la main, et donc à l'engendrer.
    let mut cles: Vec<String> = vec![etiquette.to_string()];
    for variante in &e.variantes {
        for champ in &variante.champs {
            if !cles.contains(&champ.cle) {
                cles.push(champ.cle.clone());
            }
        }
    }
    let _ = writeln!(
        sortie,
        "\n        private enum CodingKeys: String, CodingKey {{"
    );
    let _ = writeln!(
        sortie,
        "            case {}",
        cles.iter()
            .map(|c| echapper(c))
            .collect::<Vec<_>>()
            .join(", ")
    );
    let _ = writeln!(sortie, "        }}");

    let _ = writeln!(
        sortie,
        "\n        public init(from decoder: any Decoder) throws {{"
    );
    let _ = writeln!(
        sortie,
        "            let container = try decoder.container(keyedBy: CodingKeys.self)"
    );
    let _ = writeln!(
        sortie,
        "            let kind = try container.decode(String.self, forKey: .{})",
        echapper(etiquette)
    );
    let _ = writeln!(sortie, "\n            switch kind {{");

    for variante in &e.variantes {
        let _ = writeln!(sortie, "            case \"{}\":", variante.cle);
        if variante.champs.is_empty() {
            let _ = writeln!(
                sortie,
                "                self = .{}",
                echapper(&variante.cle)
            );
        } else {
            let arguments: Vec<String> = variante
                .champs
                .iter()
                .map(|c| {
                    format!(
                        "                    {}: try container.decode({}.self, forKey: .{})",
                        echapper(&c.cle),
                        swift_type(&c.type_),
                        echapper(&c.cle)
                    )
                })
                .collect();
            let _ = writeln!(
                sortie,
                "                self = .{}(",
                echapper(&variante.cle)
            );
            let _ = writeln!(sortie, "{}", arguments.join(",\n"));
            let _ = writeln!(sortie, "                )");
        }
    }

    // Un type inconnu **lève**, il n'est pas ignoré.
    //
    // C'est la seule défense possible du côté de l'app : elle télécharge son
    // corpus, donc une version installée peut rencontrer un fichier plus récent
    // que le code qui la lit. Mieux vaut un livre qui refuse de s'ouvrir, avec
    // un message, qu'un livre auquel il manque des mots sans que personne ne le
    // sache.
    let _ = writeln!(sortie, "            default:");
    let _ = writeln!(
        sortie,
        "                throw DecodingError.dataCorruptedError("
    );
    let _ = writeln!(
        sortie,
        "                    forKey: .{}, in: container,",
        echapper(etiquette)
    );
    let _ = writeln!(
        sortie,
        "                    debugDescription: \"{} inconnu : « \\(kind) ». Le corpus est plus récent que l'app.\"",
        e.nom
    );
    let _ = writeln!(sortie, "                )");
    let _ = writeln!(sortie, "            }}");
    let _ = writeln!(sortie, "        }}");
    let _ = writeln!(sortie, "    }}");
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::codegen::lire;

    fn rendu(source: &str) -> String {
        emettre(&lire(source).expect("source analysable"))
    }

    #[test]
    fn une_structure_prend_les_cles_json_pour_noms() {
        let s = rendu(
            r#"
            #[serde(rename_all = "camelCase")]
            pub struct Stub { pub id: String, pub verse_count: u32, pub reference: Option<String> }
        "#,
        );
        assert!(s.contains("public let id: String"), "{s}");
        assert!(s.contains("public let verseCount: Int"), "{s}");
        assert!(s.contains("public let reference: String?"), "{s}");
        // Aucun `CodingKeys` : les noms Swift **sont** les clés.
        assert!(!s.contains("CodingKeys"), "{s}");
    }

    #[test]
    fn un_mot_reserve_est_echappe() {
        // `break` est un mot-clé Swift. Sans les accents graves, le fichier
        // engendré ne compile pas — et c'est le genre de défaut qu'on ne
        // découvre qu'en engendrant pour de vrai.
        let s = rendu(
            r#"
            #[serde(tag = "t", rename_all = "lowercase")]
            pub enum Inline { Text { v: String }, Break }
        "#,
        );
        assert!(s.contains("case `break`"), "{s}");
        assert!(s.contains("self = .`break`"), "{s}");
    }

    #[test]
    fn une_union_etiquetee_leve_sur_un_type_inconnu() {
        let s = rendu(
            r#"
            #[serde(tag = "t", rename_all = "lowercase")]
            pub enum Block { Rule, Para { nodes: Vec<Inline> } }
        "#,
        );
        assert!(s.contains("case rule"), "{s}");
        assert!(s.contains("case para(nodes: [Inline])"), "{s}");
        assert!(s.contains("throw DecodingError.dataCorruptedError"), "{s}");
        assert!(s.contains("plus récent que l'app"), "{s}");
    }

    #[test]
    fn une_enumeration_simple_reste_une_chaine() {
        let s = rendu(r#"#[serde(rename_all = "lowercase")] pub enum Status { Locked }"#);
        assert!(s.contains("public enum Status: String, Decodable"), "{s}");
        assert!(!s.contains("init(from decoder"), "{s}");
    }

    #[test]
    fn les_tables_et_listes_imbriquees_se_rendent() {
        let s = rendu(
            r#"
            #[serde(rename_all = "camelCase")]
            pub struct F {
                pub by_lemma: BTreeMap<String, Vec<Occurrence>>,
                pub rows: Vec<Vec<Vec<Inline>>>,
            }
        "#,
        );
        assert!(
            s.contains("public let byLemma: [String: [Occurrence]]"),
            "{s}"
        );
        assert!(s.contains("public let rows: [[[Inline]]]"), "{s}");
    }

    #[test]
    fn la_documentation_du_rust_suit() {
        let s = rendu(
            r#"
            /// Le sous-titre de référence.
            pub struct Subtitle {
                /// Nul sur une introduction.
                pub reference: Option<String>,
            }
        "#,
        );
        assert!(s.contains("/// Le sous-titre de référence."), "{s}");
        assert!(s.contains("/// Nul sur une introduction."), "{s}");
    }

    #[test]
    fn le_bandeau_dit_de_ne_pas_modifier() {
        let s = rendu("pub struct A { pub x: String }");
        assert!(s.starts_with("// ENGENDRÉ"), "{s}");
        assert!(s.contains("NE PAS MODIFIER"), "{s}");
        assert!(s.contains("schema.rs"), "{s}");
    }
}
