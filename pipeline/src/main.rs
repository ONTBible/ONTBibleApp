//! Le programme — un binaire, sans rien à installer.
//!
//! C'était neuf fichiers TypeScript exécutés par Node. C'est maintenant un
//! exécutable : la CI n'a plus besoin d'un runtime, et le site non plus.

fn main() {
    match ont::build::build() {
        Ok(r) => {
            let s = &r.stats;
            println!("Corpus     {}/{} slots rédigés", s.books_written, s.books);
            println!(
                "Unités     {} chapitres + {} intros — {} versets",
                s.chapters, s.intros, s.verses
            );
            println!(
                "Glossaire  {} entrées — {} occurrences indexées",
                s.glossary_entries, s.occurrences
            );
            println!("Recherche  {} entrées indexées", r.search_records);
            println!(
                "Anomalies  {} termes inconnus, {} marqueurs déséquilibrés, {} mots d'or sans fiche",
                s.unknown_terms.len(),
                r.issues,
                r.ors_morts
            );
            println!("Sortie     {} Ko", r.bytes / 1024);
        }
        Err(message) => {
            eprintln!("échec : {message}");
            std::process::exit(1);
        }
    }
}
