//! Engendre les liaisons des liseuses depuis `schema.rs`.
//!
//!     cargo run --bin engendrer
//!
//! Lancé par `scripts/corpus.sh` à chaque build, avant `xcodegen`. Le fichier
//! produit n'est pas dans le dépôt : il ne peut donc pas être périmé.

use std::fs;
use std::path::PathBuf;

use ont::codegen;

fn main() {
    let racine = PathBuf::from(env!("CARGO_MANIFEST_DIR"));

    let source = racine.join("src/schema.rs");
    let contenu = match fs::read_to_string(&source) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("échec : {} illisible — {e}", source.display());
            std::process::exit(1);
        }
    };

    let modele = match codegen::lire(&contenu) {
        Ok(m) => m,
        Err(message) => {
            eprintln!("échec : {message}");
            std::process::exit(1);
        }
    };

    let contrat = codegen::atteignables(&modele, codegen::RACINES);

    // Chez `ONTData`, jamais chez `ONTKit`.
    //
    // Ce sont des DTO : ils décrivent un format de fichier, donc ils
    // appartiennent à la couche qui parle au monde extérieur. Les poser dans
    // `ONTKit` remettrait le domaine face au JSON du pipeline — ce que ce
    // chantier vient précisément de défaire.
    let cible = racine.join("../app/Packages/ONTData/Sources/ONTData/Bundle/Schema.swift");
    let swift = codegen::swift::emettre(&contrat);

    if let Some(parent) = cible.parent() {
        if let Err(e) = fs::create_dir_all(parent) {
            eprintln!("échec : {} — {e}", parent.display());
            std::process::exit(1);
        }
    }
    if let Err(e) = fs::write(&cible, &swift) {
        eprintln!("échec : {} — {e}", cible.display());
        std::process::exit(1);
    }

    println!(
        "Swift      {} types, {} lignes → {}",
        contrat.types.len(),
        swift.lines().count(),
        cible.file_name().unwrap_or_default().to_string_lossy()
    );
}
