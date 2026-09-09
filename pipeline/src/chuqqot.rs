//! Les chuqqot — les énoncés permanents, et ce qui décide qu'ils sortent.
//!
//! ## Ce qu'une chuqqah est, et pourquoi elle ne se distribue pas comme un
//! chapitre
//!
//! De *chaqaq* (חָקַק), graver dans la pierre. Une chuqqah énonce ce que
//! l'ontologie hébraïque tient pour **établi**, opposable partout — ni une
//! opinion qu'on défend, ni un commentaire qui accompagne un texte.
//!
//! Un chapitre de traduction en cours voyage avec sa mention « Brouillon — en
//! attente de validation », et c'est honnête : le lecteur sait où il met les
//! pieds, et le texte s'améliore sous ses yeux.
//!
//! **Un énoncé permanent « en attente de validation » se contredit
//! lui-même.** C'est la raison de la règle ci-dessous, et elle vient de
//! l'auteur — arbitrée le 9 septembre 2026 : *« encore pour une traduction,
//! mais pour une chuqqah je suis moins chaud »*.
//!
//! ## La garde est ici, dans la lecture, et pas ailleurs
//!
//! Elle aurait pu s'écrire comme un filtre au moment d'écrire `dist/`. Ç'aurait
//! été une garde **ajoutée**, donc une garde qu'un chemin d'émission futur peut
//! contourner sans le savoir : il suffirait d'écrire les chuqqot depuis un
//! second endroit et d'oublier le filtre.
//!
//! Ici, le brouillon **n'entre jamais dans la valeur publiée**. Il n'y a rien à
//! contourner : ce que ce module rend est déjà ce qui sort. Le reste — le
//! compte de ce qui attend — part au rapport, qui est fait pour ça.
//!
//! ## Ce que le rapport reçoit, et pourquoi il le reçoit
//!
//! Une chuqqah retenue n'est pas une anomalie, c'est du travail en cours. Mais
//! si rien ne le dit, six textes écrits restent invisibles à qui décide quoi
//! valider — et c'est exactement ce qui s'est passé : le pipeline ne lisait
//! même pas leur dossier, et l'onglet de l'app annonçait « ils ne sont pas
//! encore écrits » alors qu'ils l'étaient.

use std::path::Path;

use crate::schema::{Block, Chuqqah};

/// Ce que la lecture rend : ce qui sort, et ce qui attend.
#[derive(Debug, Default)]
pub struct Lecture {
    /// Les chuqqot **validées**, dans l'ordre de lecture. C'est ce qui part.
    pub publiees: Vec<Chuqqah>,
    /// Les titres de celles qui attendent leur validation, pour le rapport.
    ///
    /// Des titres et non des textes : le rapport dit qu'elles existent et
    /// lesquelles, il ne les recopie pas. Y verser la prose ferait passer par
    /// un fichier de diagnostic ce qu'on vient de décider de ne pas publier.
    pub en_attente: Vec<String>,
}

/// Lit les deux arbres, et ne rend publiable que ce qui est verrouillé.
///
/// `racine` est le vault ; `arbres` la table de `config::TREES`, dont l'ordre
/// n'importe pas ici — c'est le nom de l'état qui décide, jamais la position.
pub fn lire(racine: &Path, arbres: &[(&str, &str)]) -> Lecture {
    let mut lecture = Lecture::default();

    for (etat, dossier) in arbres {
        let chemin = racine.join(dossier).join(crate::config::CHUQQOT);
        let Ok(entrees) = std::fs::read_dir(&chemin) else {
            continue;
        };

        let mut fichiers: Vec<_> = entrees
            .flatten()
            .map(|e| e.path())
            .filter(|p| p.extension().is_some_and(|x| x == "md"))
            .collect();
        // Trié : l'ordre d'un `read_dir` n'est pas un ordre, et deux builds du
        // même vault doivent rendre le même fichier.
        fichiers.sort();

        for fichier in fichiers {
            let Ok(texte) = std::fs::read_to_string(&fichier) else {
                continue;
            };
            let nom = fichier
                .file_stem()
                .map(|s| s.to_string_lossy().into_owned())
                .unwrap_or_default();
            let titre = titre_de(&texte).unwrap_or_else(|| nom.clone());

            // **Le brouillon s'arrête ici.** Il ne devient jamais un `Chuqqah`,
            // donc aucun chemin d'écriture ne peut le reprendre par mégarde.
            if *etat != "locked" {
                lecture.en_attente.push(titre);
                continue;
            }

            lecture.publiees.push(Chuqqah {
                id: crate::inline::slugify(&nom),
                rank: rang_de(&nom),
                title: titre,
                blocks: blocs_de(&texte),
            });
        }
    }

    lecture
        .publiees
        .sort_by(|a, b| a.rank.cmp(&b.rank).then(a.id.cmp(&b.id)));
    lecture.en_attente.sort();
    lecture
}

/// Le titre, lu de la première ligne `# `.
///
/// Et non du nom de fichier : `les-quatre-modes-de-presence` n'est pas « Les
/// quatre modes de présence d'ʾAdonai dans l'ʿolam ». Le même défaut a été
/// corrigé pour la feuille de prononciation, dont le titre venait du stem.
fn titre_de(texte: &str) -> Option<String> {
    texte
        .lines()
        .find_map(|l| l.trim().strip_prefix("# "))
        .map(|t| t.trim().to_string())
}

/// L'ordre de lecture, tiré du nom quand il le porte.
///
/// `chuqqot-0-intro` ouvre la série — c'est la feuille d'introduction du §2.7.
/// Les autres n'ont pas de rang déclaré et se rangent après, alphabétiquement.
///
/// **Un défaut assumé et écrit** : l'ordre des six n'est pas une donnée du
/// vault aujourd'hui. L'alphabet n'est pas un ordre de lecture, et le jour où
/// l'auteur en voudra un, il se déclarera — ici, pas dans un nom de fichier.
fn rang_de(nom: &str) -> u32 {
    nom.strip_prefix("chuqqot-")
        .and_then(|reste| reste.split('-').next())
        .and_then(|n| n.parse().ok())
        .unwrap_or(u32::MAX)
}

/// Le corps, découpé en blocs comme une fiche de lexique.
///
/// Les chuqqot emploient exactement le même vocabulaire que le reste du
/// corpus — titres, `**intraduisibles**`, `==accentuations==`, niveau 3. Leur
/// écrire un analyseur à elles donnerait deux grammaires pour une seule langue,
/// et elles divergeraient à la première correction.
fn blocs_de(texte: &str) -> Vec<Block> {
    crate::reference::blocs_de_prose(texte)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Un dossier temporaire qui se range tout seul.
    ///
    /// **Sans dépendance neuve.** Ce dépôt n'a aucune `dev-dependency`, et
    /// l'espace disque y est un sujet qui a déjà coûté une journée — un
    /// `tempfile` de plus dans l'arbre des paquets pour six épreuves ne se
    /// paie pas. Le `Drop` fait le ménage ; si l'épreuve panique, il passe
    /// quand même.
    struct Dossier(std::path::PathBuf);

    impl Dossier {
        fn neuf() -> Self {
            use std::sync::atomic::{AtomicU32, Ordering};
            static SUIVANT: AtomicU32 = AtomicU32::new(0);
            let chemin = std::env::temp_dir().join(format!(
                "ont-chuqqot-{}-{}",
                std::process::id(),
                SUIVANT.fetch_add(1, Ordering::Relaxed)
            ));
            let _ = std::fs::remove_dir_all(&chemin);
            std::fs::create_dir_all(&chemin).expect("le dossier temporaire");
            Self(chemin)
        }

        fn path(&self) -> &std::path::Path {
            &self.0
        }
    }

    impl Drop for Dossier {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    /// Un vault de papier : deux arbres, et ce qu'on veut y mettre.
    fn vault(locked: &[(&str, &str)], brouillons: &[(&str, &str)]) -> Dossier {
        let racine = Dossier::neuf();
        for (arbre, fichiers) in [("locked", locked), ("brouillons", brouillons)] {
            let dossier = racine.path().join(arbre).join("chuqqot");
            std::fs::create_dir_all(&dossier).expect("le dossier");
            for (nom, contenu) in fichiers {
                std::fs::write(dossier.join(format!("{nom}.md")), contenu).expect("le fichier");
            }
        }
        racine
    }

    const ARBRES: [(&str, &str); 2] = [("locked", "locked"), ("brouillon", "brouillons")];

    /// **Le cœur de la garde.** Une chuqqah en brouillon ne devient jamais un
    /// `Chuqqah` : il n'y a rien à filtrer plus loin, donc rien à oublier de
    /// filtrer.
    #[test]
    fn une_chuqqah_en_brouillon_ne_sort_pas() {
        let v = vault(
            &[],
            &[("les-quatre-modes", "# Les quatre modes\n\nL'énoncé.\n")],
        );
        let lu = lire(v.path(), &ARBRES);

        assert!(lu.publiees.is_empty(), "{:?}", lu.publiees);
        assert_eq!(lu.en_attente, ["Les quatre modes"]);
    }

    /// Et l'épreuve qui rend la précédente utile : validée, elle sort. Sans
    /// celle-ci, un lecteur qui ne rendrait **jamais** rien passerait aussi.
    #[test]
    fn une_chuqqah_validee_sort() {
        let v = vault(&[("yhwh-ha-maqom", "# YHWH ha-Maqom\n\nLe lieu.\n")], &[]);
        let lu = lire(v.path(), &ARBRES);

        assert_eq!(lu.publiees.len(), 1);
        assert_eq!(lu.publiees[0].id, "yhwh-ha-maqom");
        assert_eq!(lu.publiees[0].title, "YHWH ha-Maqom");
        assert!(lu.en_attente.is_empty());
    }

    /// **Le même nom des deux côtés.** Le vault miroite ses arbres : une
    /// chuqqah en cours de validation existe aux deux endroits le temps du
    /// passage. C'est la validée qui sort, et une seule fois.
    #[test]
    fn le_meme_nom_des_deux_cotes_ne_sort_qu_une_fois() {
        let v = vault(
            &[("yhwh-ha-maqom", "# La version validée\n\nA.\n")],
            &[("yhwh-ha-maqom", "# La version en cours\n\nB.\n")],
        );
        let lu = lire(v.path(), &ARBRES);

        assert_eq!(lu.publiees.len(), 1);
        assert_eq!(lu.publiees[0].title, "La version validée");
        assert_eq!(lu.en_attente, ["La version en cours"]);
    }

    /// Le titre vient de la ligne `# `, jamais du nom de fichier.
    ///
    /// `les-quatre-modes-de-presence` n'est pas « Les quatre modes de présence
    /// d'ʾAdonai dans l'ʿolam ». Le même défaut a été corrigé pour la feuille
    /// de prononciation, dont le titre venait du stem.
    #[test]
    fn le_titre_vient_du_texte() {
        let v = vault(
            &[(
                "les-quatre-modes-de-presence",
                "# Les quatre modes de présence d'**ʾAdonai**\n\nL'énoncé.\n",
            )],
            &[],
        );
        let lu = lire(v.path(), &ARBRES);

        assert_eq!(
            lu.publiees[0].title,
            "Les quatre modes de présence d'**ʾAdonai**"
        );
    }

    /// L'introduction ouvre la série, les autres suivent.
    #[test]
    fn l_introduction_passe_devant() {
        let v = vault(
            &[
                ("aaa-premiere-alphabetiquement", "# A\n\nx\n"),
                ("chuqqot-0-intro", "# L'introduction\n\nx\n"),
            ],
            &[],
        );
        let lu = lire(v.path(), &ARBRES);

        assert_eq!(lu.publiees[0].title, "L'introduction");
    }

    /// Un dossier absent n'est pas une panne : un vault sans chuqqot est un
    /// vault, pas une erreur.
    #[test]
    fn un_vault_sans_chuqqot_se_lit() {
        let racine = Dossier::neuf();
        let lu = lire(racine.path(), &ARBRES);

        assert!(lu.publiees.is_empty());
        assert!(lu.en_attente.is_empty());
    }
}
