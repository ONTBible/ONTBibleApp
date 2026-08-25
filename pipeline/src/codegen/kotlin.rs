//! L'émetteur Kotlin.
//!
//! Le pendant de [`super::swift`], et il n'a rien coûté à écrire : le `Modele`
//! ne connaît aucun langage, alors ajouter Android c'est ajouter un émetteur.
//! C'est ce que `mod.rs` annonçait — ceci en est la tenue.
//!
//! ## Ce qu'il produit
//!
//! Des **DTO**, comme en Swift : la forme exacte du JSON, et rien d'autre. Ils
//! vivent dans le module `ontdata` et le domaine d'`ontkit` ne les voit jamais.
//! La même règle des ports et adaptateurs, dans le même sens.
//!
//! ## L'espace de noms est le paquet
//!
//! Swift a besoin d'un `enum ONTSchema` sans cas pour que `Chapter` engendré ne
//! heurte pas le `Chapter` du domaine. Kotlin n'en a pas besoin : le paquet
//! **est** l'espace de noms, et deux `Chapter` dans deux paquets cohabitent —
//! on lève l'ambiguïté par un `import … as` au seul endroit qui les croise,
//! c'est-à-dire la couche de traduction.
//!
//! Envelopper malgré tout dans un `object` donnerait `OntSchema.Chapter`
//! partout, soit la même gêne qu'en Swift, mais choisie sans y être forcé.
//!
//! ## Le discriminant se pose sur le `Json`, pas sur le type
//!
//! C'est la seule vraie différence de fond avec Swift. Là où `init(from:)`
//! lisait `"t"` lui-même — d'où le décodeur écrit à la main, et donc engendré —
//! `kotlinx.serialization` gère les unions étiquetées nativement, à condition
//! qu'on lui dise quel champ porte l'étiquette : `classDiscriminator = "t"`.
//!
//! Ce réglage vaut pour **toute** l'instance `Json`. Un schéma qui étiquetterait
//! deux unions différemment ne pourrait pas se lire avec un seul `Json` — alors
//! l'émetteur refuse d'engendrer plutôt que de produire un fichier qui décode
//! silencieusement de travers. Voir [`emettre`].
//!
//! ## Un type inconnu lève, il n'est pas ignoré
//!
//! Même raison qu'en Swift, et c'est le comportement par défaut ici : une
//! étiquette qu'aucune variante ne réclame fait lever `SerializationException`.
//! Une liseuse télécharge son corpus, donc une version installée peut tomber
//! sur un fichier plus récent qu'elle. Mieux vaut un livre qui refuse de
//! s'ouvrir qu'un livre auquel il manque des mots sans que personne ne le voie.
//!
//! `ignoreUnknownKeys` ne touche pas à cela — il ne concerne que les *champs*
//! inconnus, jamais l'étiquette. On peut donc l'activer pour tolérer un champ
//! ajouté, sans rien céder sur les types.

use std::collections::BTreeSet;
use std::fmt::Write;

use super::{Champ, Decl, Enumeration, Modele, Structure, Type, Variante};

/// Le paquet du fichier engendré.
const PAQUET: &str = "com.labibleont.ont.data.schema";

/// Les mots que Kotlin se réserve et qui peuvent paraître dans ce schéma.
///
/// Liste courte et **volontairement incomplète**, comme celle de l'émetteur
/// Swift : elle couvre ce que le schéma produit réellement. `Inline::Break` en
/// est encore l'unique cas — `break` est réservé des deux côtés. Le jour où un
/// autre arrive, le Kotlin engendré ne compile pas, ce qui est exactement le
/// bon moment pour l'apprendre.
const RESERVES: &[&str] = &[
    "as",
    "break",
    "class",
    "continue",
    "do",
    "else",
    "false",
    "for",
    "fun",
    "if",
    "in",
    "interface",
    "is",
    "null",
    "object",
    "package",
    "return",
    "super",
    "this",
    "throw",
    "true",
    "try",
    "typealias",
    "typeof",
    "val",
    "var",
    "when",
    "while",
];

/// Kotlin échappe par accents graves, comme Swift.
fn echapper(nom: &str) -> String {
    if RESERVES.contains(&nom) {
        format!("`{nom}`")
    } else {
        nom.to_string()
    }
}

/// Le type Kotlin, collections **pleinement qualifiées**.
///
/// ## Pourquoi `kotlin.collections.List` et non `List`
///
/// Parce qu'une variante d'union peut porter le nom d'un type standard, et que
/// `Block` le fait : sa variante `list` est la liste à puces. Imbriquée dans
/// l'interface, elle devient `Block.List` — et masque `kotlin.collections.List`
/// dans tout le corps de l'interface. `List<Inline>` y désigne alors la
/// variante, qui n'accepte aucun paramètre de type :
///
/// ```text
/// No type arguments expected for 'data class List : Block'
/// ```
///
/// Le masquage n'est pas un mot réservé : la liste des `RESERVES` ne pouvait
/// pas l'attraper, et rien ne le signale avant que le fichier engendré refuse
/// de compiler. Qualifier coûte quelques caractères dans un fichier que
/// personne ne relit, et vaut pour **tout** nom qu'une variante prendra un
/// jour — `Map`, `Set`, `Pair`, `Result`. On n'aura pas à y revenir.
fn kotlin_type(t: &Type) -> String {
    match t {
        Type::Chaine => "String".into(),
        Type::Entier => "Int".into(),
        Type::Booleen => "Boolean".into(),
        Type::Optionnel(inner) => format!("{}?", kotlin_type(inner)),
        Type::Liste(inner) => format!("kotlin.collections.List<{}>", kotlin_type(inner)),
        Type::Table(inner) => format!("kotlin.collections.Map<String, {}>", kotlin_type(inner)),
        Type::Nomme(n) => n.clone(),
    }
}

/// Le nom d'une entrée d'énumération simple — `locked` devient `LOCKED`.
///
/// La valeur JSON reste portée par `@SerialName`, donc rien ne dépend de cette
/// transformation : elle n'existe que pour que le fichier se lise comme du
/// Kotlin. C'est le seul endroit où l'on s'écarte de la clé JSON, et c'est
/// aussi le seul où l'idiome de la plateforme l'emporte sans rien coûter.
fn constante(cle: &str) -> String {
    let mut sortie = String::new();
    for (i, c) in cle.chars().enumerate() {
        if c.is_uppercase() && i > 0 {
            sortie.push('_');
        }
        if c == '-' || c == '.' {
            sortie.push('_');
        } else {
            sortie.extend(c.to_uppercase());
        }
    }
    sortie
}

/// La valeur par défaut d'un champ, quand la clé peut manquer.
///
/// ## Deux raisons distinctes d'en avoir une
///
/// Un **optionnel** en reçoit toujours. Ce n'est pas ce que serde exige — sans
/// `skip_serializing_if`, il écrit `null` et la clé est bien là — mais c'est ce
/// que fait le `Decodable` synthétisé de Swift, qui traite un `Optional` comme
/// un `decodeIfPresent`. Les deux liseuses doivent accepter exactement les
/// mêmes fichiers ; s'aligner sur la plus tolérante des deux est le seul moyen
/// qu'un corpus lisible sur iPhone le soit aussi sur Android.
///
/// Un **champ escamotable** en reçoit une parce que le pipeline omet vraiment
/// la clé. C'est le cas des `Vec` marqués `skip_serializing_if = "Vec::is_empty"`.
///
/// # Panique
///
/// Sur un scalaire escamotable — `Int`, `String`, `Boolean`, ou un type nommé.
/// Il n'existe pas de valeur par défaut évidente pour eux : `0` et `""` sont
/// des inventions, et une invention dans un décodeur est un défaut muet. Si le
/// schéma en a besoin, c'est une décision à écrire dans `schema.rs`, pas à
/// deviner ici.
fn defaut(champ: &Champ) -> String {
    match &champ.type_ {
        Type::Optionnel(_) => " = null".into(),
        _ if !champ.escamotable => String::new(),
        Type::Liste(_) => " = emptyList()".into(),
        Type::Table(_) => " = emptyMap()".into(),
        autre => panic!(
            "le champ « {} » est escamotable mais de type {}, qui n'a pas de \
             valeur par défaut évidente — la déclarer dans schema.rs",
            champ.cle,
            kotlin_type(autre)
        ),
    }
}

/// La documentation Rust devient du KDoc.
///
/// Un bloc `/** … */` plutôt que des `///` répétés : c'est la forme que les
/// outils Kotlin lisent, et Android Studio ne montre l'aide que sur celle-là.
fn doc(sortie: &mut String, lignes: &[String], retrait: &str) {
    if lignes.is_empty() {
        return;
    }
    let _ = writeln!(sortie, "{retrait}/**");
    for ligne in lignes {
        if ligne.trim().is_empty() {
            let _ = writeln!(sortie, "{retrait} *");
        } else {
            let _ = writeln!(sortie, "{retrait} *{ligne}");
        }
    }
    let _ = writeln!(sortie, "{retrait} */");
}

/// Écrit le fichier Kotlin complet.
///
/// # Panique
///
/// Si deux unions étiquetées du schéma ne portent pas la **même** étiquette.
/// `kotlinx.serialization` ne sait poser qu'un discriminant par instance
/// `Json` ; deux étiquettes différentes demanderaient deux instances, et le
/// choix de la bonne au bon endroit serait à tenir à la main — donc à oublier.
/// On préfère l'arrêt franc au moment d'engendrer : ça se répare dans
/// `schema.rs`, en une ligne, avant que quoi que ce soit ne soit livré.
pub fn emettre(modele: &Modele) -> String {
    let etiquette = discriminant(modele);

    let mut sortie = String::new();

    sortie.push_str(
        "// ENGENDRÉ PAR LE PIPELINE — NE PAS MODIFIER À LA MAIN.\n\
         //\n\
         // Source : pipeline/src/schema.rs\n\
         // Producteur : cargo run --bin engendrer\n\
         //\n\
         // Ce fichier n'est pas dans le dépôt. Il est réécrit à chaque build par\n\
         // `scripts/corpus.sh`, comme `dist/` et comme `Schema.swift` — donc il ne\n\
         // peut pas être périmé, et il n'y a rien à penser à relancer.\n\
         //\n\
         // Une modification faite ici disparaîtra au prochain build, sans un mot.\n\
         // Ce qu'il faut changer est `schema.rs`.\n\
         //\n\
         // Ce sont des **DTO** : la forme du JSON, et rien d'autre. Le domaine vit\n\
         // dans `ontkit` et ne les connaît pas ; la traduction est dans SchemaMapping.kt.\n\n",
    );

    let _ = writeln!(sortie, "package {PAQUET}\n");
    sortie.push_str(
        "import kotlinx.serialization.SerialName\n\
         import kotlinx.serialization.Serializable\n\
         import kotlinx.serialization.json.Json\n\n",
    );

    if let Some(etiquette) = &etiquette {
        let _ = writeln!(
            sortie,
            "/**\n\
             \x20* Le lecteur du corpus.\n\
             \x20*\n\
             \x20* `classDiscriminator` **doit** valoir `\"{etiquette}\"` : c'est le champ qui\n\
             \x20* porte le type des nœuds, et sans lui rien ne se décode. Il est ici plutôt\n\
             \x20* qu'au point d'appel pour qu'aucune autre instance de `Json` ne puisse être\n\
             \x20* employée par mégarde.\n\
             \x20*\n\
             \x20* `ignoreUnknownKeys` tolère un **champ** ajouté par un pipeline plus récent.\n\
             \x20* Il ne tolère pas un **type** inconnu : celui-là lève, et c'est voulu — une\n\
             \x20* liseuse qui omettrait un nœud qu'elle ne connaît pas afficherait un texte\n\
             \x20* amputé sans que personne ne s'en aperçoive.\n\
             \x20*/\n\
             public val ontJson: Json = Json {{\n\
             \x20   classDiscriminator = \"{etiquette}\"\n\
             \x20   ignoreUnknownKeys = true\n\
             }}"
        );
    }

    for decl in &modele.types {
        sortie.push('\n');
        match decl {
            Decl::Structure(s) => structure(&mut sortie, s),
            Decl::Enumeration(e) => enumeration(&mut sortie, e),
        }
    }

    sortie
}

/// L'étiquette commune des unions du modèle, s'il y en a.
fn discriminant(modele: &Modele) -> Option<String> {
    let etiquettes: BTreeSet<&str> = modele
        .types
        .iter()
        .filter_map(|d| match d {
            Decl::Enumeration(e) => e.etiquette.as_deref(),
            Decl::Structure(_) => None,
        })
        .collect();

    match etiquettes.len() {
        0 => None,
        1 => Some(etiquettes.into_iter().next().unwrap().to_string()),
        _ => panic!(
            "les unions du schéma portent des étiquettes différentes ({}) — \
             kotlinx.serialization n'en pose qu'une par instance Json. \
             Les uniformiser dans schema.rs.",
            etiquettes.into_iter().collect::<Vec<_>>().join(", ")
        ),
    }
}

fn structure(sortie: &mut String, s: &Structure) {
    doc(sortie, &s.doc, "");
    let _ = writeln!(sortie, "@Serializable");

    // Une structure sans champ ne peut pas être une `data class` — Kotlin exige
    // au moins un paramètre. Le cas ne se présente pas aujourd'hui, mais il
    // coûte une ligne à couvrir et son absence coûterait un build cassé.
    if s.champs.is_empty() {
        let _ = writeln!(sortie, "public class {}", s.nom);
        return;
    }

    let _ = writeln!(sortie, "public data class {}(", s.nom);
    for (i, champ) in s.champs.iter().enumerate() {
        doc(sortie, &champ.doc, "    ");
        // Pas de `@SerialName` : le nom Kotlin **est** la clé JSON, par
        // construction — on nomme d'après la clé, jamais d'après le nom Rust.
        // L'annoter reviendrait à répéter la même liste une seconde fois, avec
        // le risque que les deux divergent.
        //
        // Un optionnel prend `= null` pour que le champ puisse manquer :
        // `skip_serializing_if` fait que le pipeline ne l'écrit pas quand il
        // est vide, et sans valeur par défaut le décodage échouerait là-dessus.
        let defaut = defaut(champ);
        let virgule = if i + 1 < s.champs.len() { "," } else { "" };
        let _ = writeln!(
            sortie,
            "    public val {}: {}{}{}",
            echapper(&champ.cle),
            kotlin_type(&champ.type_),
            defaut,
            virgule
        );
    }
    let _ = writeln!(sortie, ")");
}

fn enumeration(sortie: &mut String, e: &Enumeration) {
    match &e.etiquette {
        None => enumeration_chaine(sortie, e),
        Some(_) => enumeration_etiquetee(sortie, e),
    }
}

fn enumeration_chaine(sortie: &mut String, e: &Enumeration) {
    doc(sortie, &e.doc, "");
    let _ = writeln!(sortie, "@Serializable");
    let _ = writeln!(sortie, "public enum class {} {{", e.nom);
    for (i, variante) in e.variantes.iter().enumerate() {
        doc(sortie, &variante.doc, "    ");
        let virgule = if i + 1 < e.variantes.len() { "," } else { ";" };
        let _ = writeln!(sortie, "    @SerialName(\"{}\")", variante.cle);
        let _ = writeln!(sortie, "    {}{}", constante(&variante.cle), virgule);
    }
    let _ = writeln!(sortie, "}}");
}

/// Une union étiquetée devient une `sealed interface` et ses variantes des
/// types imbriqués.
///
/// Imbriquer plutôt qu'éparpiller : `Inline.Text` se lit comme `.text` en
/// Swift, et surtout deux unions peuvent porter une variante de même nom sans
/// se heurter. C'est déjà presque le cas — `Block` et `Inline` se ressemblent
/// beaucoup — et ça le sera tout à fait le jour où l'une gagne un nœud que
/// l'autre a déjà.
fn enumeration_etiquetee(sortie: &mut String, e: &Enumeration) {
    doc(sortie, &e.doc, "");
    let _ = writeln!(sortie, "@Serializable");
    let _ = writeln!(sortie, "public sealed interface {} {{", e.nom);

    for variante in &e.variantes {
        sortie.push('\n');
        variante_imbriquee(sortie, &e.nom, variante);
    }

    let _ = writeln!(sortie, "}}");
}

fn variante_imbriquee(sortie: &mut String, union: &str, variante: &Variante) {
    doc(sortie, &variante.doc, "    ");
    let _ = writeln!(sortie, "    @Serializable");
    let _ = writeln!(sortie, "    @SerialName(\"{}\")", variante.cle);

    // Le nom du type garde la casse Kotlin — `Break` — tandis que `@SerialName`
    // porte la valeur JSON. Le mot réservé ne gêne donc plus : il ne reste que
    // dans l'annotation, où c'est une chaîne.
    let nom = pascal(&variante.cle);

    if variante.champs.is_empty() {
        // `data object` : une variante sans charge utile n'a qu'un habitant.
        let _ = writeln!(sortie, "    public data object {nom} : {union}");
        return;
    }

    let _ = writeln!(sortie, "    public data class {nom}(");
    for (i, champ) in variante.champs.iter().enumerate() {
        doc(sortie, &champ.doc, "        ");
        let defaut = defaut(champ);
        let virgule = if i + 1 < variante.champs.len() {
            ","
        } else {
            ""
        };
        let _ = writeln!(
            sortie,
            "        public val {}: {}{}{}",
            echapper(&champ.cle),
            kotlin_type(&champ.type_),
            defaut,
            virgule
        );
    }
    let _ = writeln!(sortie, "    ) : {union}");
}

/// `text` devient `Text`, `verse-ref` devient `VerseRef`.
fn pascal(cle: &str) -> String {
    let mut sortie = String::new();
    let mut majuscule = true;
    for c in cle.chars() {
        if c == '-' || c == '_' || c == '.' {
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
        assert!(s.contains("public data class Stub("), "{s}");
        assert!(s.contains("public val id: String,"), "{s}");
        assert!(s.contains("public val verseCount: Int,"), "{s}");
        // L'optionnel prend `= null`, sinon un champ omis par le pipeline
        // ferait échouer le décodage.
        assert!(s.contains("public val reference: String? = null"), "{s}");
        // Aucun `@SerialName` sur un champ : le nom Kotlin **est** la clé.
        assert!(!s.contains("@SerialName(\"verseCount\")"), "{s}");
    }

    #[test]
    fn une_union_etiquetee_devient_une_interface_scellee() {
        let s = rendu(
            r#"
            #[serde(tag = "t", rename_all = "lowercase")]
            pub enum Block { Rule, Para { nodes: Vec<Inline> } }
        "#,
        );
        assert!(s.contains("public sealed interface Block {"), "{s}");
        // Sans charge utile : un seul habitant.
        assert!(s.contains("public data object Rule : Block"), "{s}");
        assert!(s.contains("@SerialName(\"rule\")"), "{s}");
        // Avec charge utile : une classe imbriquée.
        assert!(s.contains("public data class Para("), "{s}");
        assert!(
            s.contains("public val nodes: kotlin.collections.List<Inline>"),
            "{s}"
        );
        assert!(s.contains(") : Block"), "{s}");
    }

    #[test]
    fn le_discriminant_est_pose_sur_le_json() {
        // C'est **la** différence avec Swift : sans cette ligne, rien ne
        // décode. Elle doit être engendrée, jamais laissée au point d'appel.
        let s = rendu(
            r#"
            #[serde(tag = "t", rename_all = "lowercase")]
            pub enum Inline { Text { v: String } }
        "#,
        );
        assert!(s.contains("classDiscriminator = \"t\""), "{s}");
        assert!(s.contains("public val ontJson: Json"), "{s}");
    }

    #[test]
    fn un_schema_sans_union_ne_declare_pas_de_json() {
        let s = rendu("pub struct A { pub x: String }");
        assert!(!s.contains("ontJson"), "{s}");
    }

    #[test]
    #[should_panic(expected = "étiquettes différentes")]
    fn deux_etiquettes_differentes_arretent_l_engendrement() {
        // Un seul `Json` ne peut porter qu'un discriminant. Plutôt que
        // d'engendrer un fichier qui décoderait de travers en silence, on
        // s'arrête — ça se répare dans `schema.rs`.
        rendu(
            r#"
            #[serde(tag = "t", rename_all = "lowercase")]
            pub enum A { X { v: String } }
            #[serde(tag = "type", rename_all = "lowercase")]
            pub enum B { Y { v: String } }
        "#,
        );
    }

    #[test]
    fn un_mot_reserve_ne_gene_plus_le_nom_du_type() {
        // `break` est réservé en Kotlin comme en Swift, mais ici il ne sert que
        // dans `@SerialName`, où c'est une chaîne : le type s'appelle `Break`.
        let s = rendu(
            r#"
            #[serde(tag = "t", rename_all = "lowercase")]
            pub enum Inline { Text { v: String }, Break }
        "#,
        );
        assert!(s.contains("@SerialName(\"break\")"), "{s}");
        assert!(s.contains("public data object Break : Inline"), "{s}");
    }

    #[test]
    fn un_champ_reserve_est_echappe() {
        let s = rendu(r#"pub struct A { pub object: String, pub val: u32 }"#);
        assert!(s.contains("public val `object`: String"), "{s}");
        assert!(s.contains("public val `val`: Int"), "{s}");
    }

    #[test]
    fn une_enumeration_simple_reste_une_chaine() {
        let s = rendu(r#"#[serde(rename_all = "lowercase")] pub enum Status { Locked, Draft }"#);
        assert!(s.contains("public enum class Status {"), "{s}");
        assert!(s.contains("@SerialName(\"locked\")"), "{s}");
        assert!(s.contains("LOCKED,"), "{s}");
        assert!(s.contains("DRAFT;"), "{s}");
        assert!(!s.contains("sealed interface Status"), "{s}");
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
            s.contains(
                "public val byLemma: kotlin.collections.Map<String, \
                 kotlin.collections.List<Occurrence>>"
            ),
            "{s}"
        );
        assert!(
            s.contains(
                "public val rows: kotlin.collections.List<kotlin.collections.List<\
                 kotlin.collections.List<Inline>>>"
            ),
            "{s}"
        );
    }

    #[test]
    fn la_documentation_du_rust_suit_en_kdoc() {
        let s = rendu(
            r#"
            /// Le sous-titre de référence.
            pub struct Subtitle {
                /// Nul sur une introduction.
                pub reference: Option<String>,
            }
        "#,
        );
        // Un bloc KDoc, pas des `///` : c'est la forme qu'Android Studio lit.
        assert!(s.contains("/**"), "{s}");
        assert!(s.contains(" * Le sous-titre de référence."), "{s}");
        assert!(s.contains(" * Nul sur une introduction."), "{s}");
        assert!(!s.contains("/// Le sous-titre"), "{s}");
    }

    #[test]
    fn une_liste_escamotable_recoit_une_valeur_par_defaut() {
        // Le cas qui a révélé le défaut : le pipeline n'écrit pas la clé quand
        // la liste est vide, donc la plupart des modes n'en ont pas. Sans
        // valeur par défaut, `MissingFieldException` sur presque tout.
        let s = rendu(
            r#"
            pub struct Mode {
                #[serde(default, skip_serializing_if = "Vec::is_empty")]
                pub groups: Vec<Group>,
            }
        "#,
        );
        assert!(
            s.contains("public val groups: kotlin.collections.List<Group> = emptyList()"),
            "{s}"
        );
    }

    #[test]
    fn une_liste_obligatoire_n_en_recoit_pas() {
        // La contre-épreuve : sans `skip_serializing_if`, la clé est toujours
        // écrite, et une valeur par défaut masquerait un fichier tronqué.
        let s = rendu("pub struct Book { pub chapters: Vec<Chapter> }");
        assert!(
            s.contains("public val chapters: kotlin.collections.List<Chapter>"),
            "{s}"
        );
        assert!(!s.contains("emptyList()"), "{s}");
    }

    #[test]
    fn une_table_escamotable_aussi() {
        let s = rendu(
            r#"
            pub struct F {
                #[serde(skip_serializing_if = "BTreeMap::is_empty")]
                pub by_lemma: BTreeMap<String, Occurrence>,
            }
        "#,
        );
        assert!(s.contains("= emptyMap()"), "{s}");
    }

    #[test]
    #[should_panic(expected = "escamotable")]
    fn un_scalaire_escamotable_arrete_l_engendrement() {
        // Inventer `0` serait un défaut muet. On le refuse ici plutôt que de
        // le découvrir dans un chapitre.
        rendu(r#"pub struct A { #[serde(default)] pub count: u32 }"#);
    }

    #[test]
    fn une_variante_nommee_comme_un_type_standard_ne_masque_rien() {
        // Le cas réel : `Block::List` est la liste à puces. Imbriquée, elle
        // masquait `kotlin.collections.List` dans tout le corps de l'interface,
        // et le fichier engendré ne compilait pas.
        let s = rendu(
            r#"
            #[serde(tag = "t", rename_all = "lowercase")]
            pub enum Block { List { items: Vec<Inline> }, Para { nodes: Vec<Inline> } }
        "#,
        );
        assert!(s.contains("public data class List("), "{s}");
        assert!(
            s.contains("public val items: kotlin.collections.List<Inline>"),
            "{s}"
        );
    }

    #[test]
    fn le_bandeau_dit_de_ne_pas_modifier() {
        let s = rendu("pub struct A { pub x: String }");
        assert!(s.starts_with("// ENGENDRÉ"), "{s}");
        assert!(s.contains("NE PAS MODIFIER"), "{s}");
        assert!(s.contains("schema.rs"), "{s}");
        assert!(s.contains(&format!("package {PAQUET}")), "{s}");
    }
}
