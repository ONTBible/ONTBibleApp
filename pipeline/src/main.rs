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
            // Les deux suivants ne sont pas des fautes : ce sont des listes de
            // travail. Un Shem sans fiche est un porteur pas encore écrit ; un
            // terme balisé sans définition est une entrée du §3 à rédiger.
            println!(
                "À écrire   {} Shemot sans fiche, {} termes balisés sans définition",
                r.shemot_sans_fiche, r.sans_definition
            );
            // **Le contrôle qui mesure ce qui est livré.** Les lignes
            // au-dessus disent que la source est propre ; celle-ci dit si le
            // lecteur, lui, tombera sur un lien qui n'ouvre rien.
            println!(
                "Liens      {} occurrences mortes sur {} lemmes — mesuré sur dist/",
                r.liens_morts, r.liens_morts_lemmes
            );
            // §4.1 : compter avant de clore. Une commande qu'il faut penser à
            // lancer est une commande qu'on oublie.
            // **Le nom, pas seulement le nombre.** Un compteur qui ne bouge
            // pas d'un build à l'autre devient un décor qu'on cesse de lire ;
            // la moins glosée change dès qu'on travaille, et c'est par elle
            // qu'on commencerait.
            match &r.moins_glosee {
                Some((unite, pm)) => println!(
                    "Densité    {}/{} chapitres sous la moitié de la référence — le plus bas : {unite} ({pm:.0}/1000)",
                    r.sous_glosees, r.chapitres_mesures
                ),
                None => println!("Densité    aucun chapitre mesuré"),
            }
            // **L'épreuve des plages à cheval, avec son dénominateur.**
            //
            // `renvois::interne` déduit la longueur du premier chapitre d'une
            // plage « 1:1 — 2:3 » au lieu de la lire, et cette déduction ne
            // peut pas voir qu'une unité a réuni deux versets. Cette ligne dit
            // combien de ces déductions ont été confrontées au témoin — et
            // surtout combien ne l'ont pas été, faute de source : sans ce
            // second chiffre, un contrôle qui n'a rien regardé rend la même
            // sortie qu'un contrôle qui a tout vérifié.
            println!(
                "Plages     {} à cheval confrontées au témoin, {} non mesurées",
                r.plages_mesurees, r.plages_non_mesurees
            );
            println!("Sortie     {} Ko", r.bytes / 1024);
        }
        Err(message) => {
            eprintln!("échec : {message}");
            std::process::exit(1);
        }
    }
}
