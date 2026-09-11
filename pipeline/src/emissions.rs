//! Le contrôle des **fichiers émis** — rapprocher `dist/` de ce que les
//! liseuses lisent vraiment.
//!
//! ## Le défaut que ce module mesure
//!
//! Le pipeline écrit `dist/`. Trois liseuses le lisent — iOS/macOS en Swift,
//! Android en Kotlin, `ontbible.com` en Rust. **Rien ne rapprochait les deux
//! listes**, et l'écart ne se voit d'aucun des quatre endroits :
//!
//! - un fichier émis que personne ne lit part quand même dans le paquet, chez
//!   le lecteur, et n'ouvre rien. `shemot.json` a vécu dix jours ainsi côté
//!   site : les fiches étaient publiées, la page `/fr/lexique/<nom>` répondait
//!   **200** avec « Fiche introuvable ». Ce n'est pas un 404 — aucune
//!   supervision ne le voit ;
//! - une liseuse qui attend un fichier que le pipeline n'écrit pas ne le
//!   découvre qu'à l'exécution, sur l'appareil. Une session voisine a cru
//!   `prononciation.json` disparu ; son `dist/` était périmé, et rien ne
//!   permettait de trancher mécaniquement.
//!
//! Android portait déjà la garde — `connusDuCorpus` et `verifierLeCorpus` dans
//! `android/app/build.gradle.kts` —, et elle a arrêté un cas réel. Mais elle
//! ne protège qu'Android, ne regarde que la racine du dossier copié, et
//! surveille la **copie** iOS plutôt que la sortie. Or c'est le pipeline qui
//! émet : la garde a sa place ici. Elle reste là-bas, en second rideau, sur le
//! chemin de l'appareil.
//!
//! ## Comment une liseuse « déclare » ce qu'elle lit
//!
//! Deux réponses possibles, et le choix n'est pas cosmétique.
//!
//! **Une liste déclarée** — un tableau, ici, disant quel fichier va à quelle
//! liseuse — est exacte, hermétique, et ne dépend d'aucun dépôt voisin. Elle a
//! un défaut rédhibitoire : *elle se périme sans bruit*. Face au défaut n°1,
//! elle aurait dit « `shemot.json` → site », et elle aurait menti. **Une table
//! seule n'aurait pas attrapé le défaut qui a motivé ce module** : c'est ce qui
//! tranche.
//!
//! **Un `grep` du source de la liseuse** est fragile — un nom construit par
//! interpolation lui échappe, une mention en commentaire le trompe — mais c'est
//! la seule chose qui constitue une **preuve** : quelqu'un a bien écrit ce nom
//! quelque part chez le consommateur.
//!
//! D'où la forme retenue, qui est un **hybride** : la table dit ce qui *doit*
//! être lu et par qui ; le `grep` dit ce qui *est* mentionné. Les deux
//! s'auditent l'un l'autre, dans les deux sens :
//!
//! > un `Lit` sans trace rougit — la table promet un lecteur qui n'existe pas.
//! > Une `Lacune` avec trace rougit aussi — quelqu'un a écrit le lecteur, et la
//! > table ne le sait pas encore. C'est cette seconde moitié qui empêche le
//! > tableau de pourrir.
//!
//! Les noms interpolés sont traités par le champ `jetons` : on ne cherche pas
//! le nom du fichier mais **le fragment le plus discriminant qui survit à
//! l'interpolation** — `books/` plutôt que `bereshit.json`.
//!
//! ## Ce que le contrôle ne mesure pas, et il faut le dire
//!
//! - **Une mention n'est pas une lecture.** Un commentaire, un test, une
//!   constante morte comptent comme une trace. Le contrôle prouve qu'un dépôt
//!   *connaît* le fichier, jamais qu'il l'ouvre à l'exécution — c'est
//!   exactement le trou par lequel `shemot.json` était passé côté site, qui
//!   l'*incluait* sans le servir. On mesure la connaissance, pas l'usage.
//! - **Le site n'est pas toujours mesurable.** `ONTBibleWebapp` est un dépôt
//!   voisin : présent sur le poste de l'auteur, absent de la CI de ce dépôt-ci,
//!   qui ne le récupère jamais. Sa colonne est alors rendue « non mesurée »
//!   plutôt que verte — un contrôle qui rend vert faute d'avoir regardé est
//!   pire qu'un contrôle absent. C'est, précisément, la liseuse du défaut n°1.
//! - **Le contenu n'est pas relu.** Les planchers comptent des entrées ; ils ne
//!   disent rien de leur justesse.
//!
//! ## Les comptes, et pourquoi la présence ne suffit pas
//!
//! Une session voisine a vu `book_names` tomber de 67 à **0** sans que rien ne
//! rougisse. Un fichier vide et un fichier absent ne se distinguent pas côté
//! liseuse, et l'un des deux est une panne. Chaque artefact peut donc porter un
//! **plancher** : le nom de sa collection de tête — *tel qu'il est sérialisé*,
//! `byLemma` et non `by_lemma` — et le nombre minimal d'entrées qu'elle doit
//! porter. On relit le JSON écrit, on compte, on compare.
//!
//! Le plancher est **opt-in**, et c'est délibéré : `chuqqot.json` est écrit
//! même vide, par contrat explicite de l'émission — « un fichier absent et un
//! fichier sans entrée ne se distinguent pas côté liseuse, et l'un des deux
//! voudrait dire *le réseau a échoué* ». Un plancher global le casserait pour
//! la raison exactement inverse de celle qui l'a fait naître.

use std::collections::BTreeMap;
use std::fmt;
use std::path::{Path, PathBuf};

// ─────────────────────────────────────────────────────────────────────────────
// Les liseuses
// ─────────────────────────────────────────────────────────────────────────────

/// Un consommateur de `dist/`.
///
/// Elles sont nommées ici en dur, et non découvertes : une liseuse qu'on
/// oublie d'ajouter est une liseuse que personne ne protège, et un tableau qui
/// se découvre tout seul ne rougit jamais d'être incomplet.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug)]
pub enum Liseuse {
    Ios,
    Android,
    Site,
}

impl Liseuse {
    pub const TOUTES: [Liseuse; 3] = [Liseuse::Ios, Liseuse::Android, Liseuse::Site];

    pub fn nom(self) -> &'static str {
        match self {
            Liseuse::Ios => "iOS/macOS",
            Liseuse::Android => "Android",
            Liseuse::Site => "ontbible.com",
        }
    }

    /// Les extensions du source à fouiller.
    ///
    /// L'extension est comparée **en entier**, par `Path::extension` — un
    /// `chemin.contains(".kt")` laisserait entrer les `.kts`, et c'est
    /// précisément ce que le paragraphe suivant refuse.
    ///
    /// Le filtre ne suffit pourtant pas à lui seul : un fichier peut porter la
    /// bonne extension et n'être quand même pas un lecteur, parce que c'est le
    /// pipeline qui l'a écrit. `aspirer` s'en charge, par la marque d'en-tête.
    ///
    /// **Android ne donne que `.kt`, jamais `.kts`.** Les fichiers Gradle sont
    /// de la configuration de build, pas des lecteurs : `build.gradle.kts`
    /// porte `connusDuCorpus`, qui nomme tous les fichiers du corpus, et
    /// `exclude("prononciation.json")`, qui nomme précisément celui qu'Android
    /// **ne** lit **pas**. Les compter comme traces rendrait le contrôle vert
    /// partout, y compris là où la vérité est l'inverse.
    fn extensions(self) -> &'static [&'static str] {
        match self {
            Liseuse::Ios => &["swift"],
            Liseuse::Android => &["kt"],
            Liseuse::Site => &["rs"],
        }
    }

    /// Les dossiers de son source, depuis la racine du dépôt `ONTBibleApp`.
    ///
    /// Le site vit dans un dépôt voisin ; son chemin est relatif à la racine de
    /// celui-ci, ce qui est vrai en local et faux en CI — d'où l'état « non
    /// mesurée » plus bas plutôt qu'un échec.
    fn racines(self, depot: &Path) -> Vec<PathBuf> {
        match self {
            Liseuse::Ios => vec![depot.join("app")],
            Liseuse::Android => vec![depot.join("android")],
            Liseuse::Site => {
                let site = depot.join("..").join("ONTBibleWebapp");
                vec![site.join("src"), site.join("build.rs")]
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Le tableau des artefacts
// ─────────────────────────────────────────────────────────────────────────────

/// Ce qu'un artefact désigne dans `dist/`.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Cible {
    /// Un chemin exact, relatif à `dist/` — `corpus.json`.
    Exact(&'static str),
    /// Tout ce qui vit sous un préfixe — `books/`, `sources/`.
    ///
    /// Nécessaire parce que le nom du fichier vient de la donnée :
    /// `books/<id>.json` en compte cinq aujourd'hui et soixante-dix demain. Un
    /// artefact par livre serait un tableau à réécrire à chaque livre traduit.
    Sous(&'static str),
}

impl Cible {
    fn dit(self) -> &'static str {
        match self {
            Cible::Exact(c) | Cible::Sous(c) => c,
        }
    }

    fn couvre(self, chemin: &str) -> bool {
        match self {
            Cible::Exact(c) => chemin == c,
            Cible::Sous(p) => chemin.starts_with(p),
        }
    }
}

/// Ce que le pipeline promet d'écrire.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Emission {
    /// Écrit à tous les coups. Son absence est un défaut.
    Toujours,
    /// Écrit seulement si le vault porte de quoi. Son absence ne dit rien.
    ///
    /// La raison est stockée pour être **lue dans le rapport** : « facultatif »
    /// sans le pourquoi devient, six mois plus tard, « on ne sait plus ».
    Facultative(&'static str),
    /// Écrit **après** ce relevé — il ne peut pas figurer dans l'inventaire.
    ///
    /// `report.md` est ce cas unique, et il n'est pas anecdotique : le rapport
    /// porte le relevé, donc le relevé le précède. Sans cet état, le contrôle
    /// se signalerait lui-même comme fichier attendu et manquant, à chaque
    /// build, pour toujours.
    ApresLeReleve(&'static str),
}

/// Ce qu'une liseuse fait de l'artefact.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Lecture {
    /// Elle le lit, et le contrôle exige d'en trouver la trace.
    Lit,
    /// Elle ne le lit pas, **par décision**, et la raison est ici.
    Ignore(&'static str),
    /// Elle ne le lit pas, et **c'est un défaut connu**, pas une décision.
    ///
    /// La distinction est tout l'intérêt du module. `Ignore` clôt un sujet ;
    /// `Lacune` l'ouvre — le rapport la nomme à chaque build sans casser la
    /// construction, jusqu'à ce que quelqu'un écrive le lecteur. Le jour où il
    /// l'écrit, la trace paraît et le contrôle rougit pour réclamer la mise à
    /// jour du tableau : la dette est bornée des deux côtés.
    Lacune(&'static str),
}

/// Le nombre minimal d'entrées d'une collection émise.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Plancher {
    /// Le nom **sérialisé** du champ — `byLemma`, pas `by_lemma`.
    pub champ: &'static str,
    pub minimum: usize,
}

pub struct Artefact {
    pub cible: Cible,
    pub emission: Emission,
    pub plancher: Option<Plancher>,
    /// Les fragments à chercher dans le source des liseuses.
    ///
    /// Une seule occurrence de l'un d'eux suffit. Ils sont choisis pour
    /// **survivre à l'interpolation** — Swift écrit `books/\(id).json`, Kotlin
    /// `data/books/$id.json`, et le site engendre ses `include_str!` depuis un
    /// `read_dir` de `dist/books` : aucun ne contient `bereshit.json`, tous
    /// contiennent l'un des deux jetons déclarés.
    ///
    /// Vide, la preuve est sautée — c'est le cas de `report.md`, que personne
    /// n'embarque et que le tableau n'a pas à interroger.
    pub jetons: &'static [&'static str],
    pub lectures: &'static [(Liseuse, Lecture)],
}

/// Le tableau, et il fait foi.
///
/// Tout fichier de `dist/` qu'aucune ligne ne couvre fait rougir : c'est la
/// garde d'Android remontée d'un cran, et c'est ce qui rend le tableau
/// obligatoire au lieu de facultatif. Ajouter une émission, c'est ajouter sa
/// ligne — et donc répondre, ligne écrite, à la question « qui va le lire ? ».
pub const ARTEFACTS: &[Artefact] = &[
    Artefact {
        cible: Cible::Exact("corpus.json"),
        emission: Emission::Toujours,
        plancher: Some(Plancher {
            champ: "corpora",
            minimum: 1,
        }),
        jetons: &["corpus.json"],
        lectures: &[
            (Liseuse::Ios, Lecture::Lit),
            (Liseuse::Android, Lecture::Lit),
            (Liseuse::Site, Lecture::Lit),
        ],
    },
    Artefact {
        cible: Cible::Sous("books/"),
        emission: Emission::Toujours,
        // Pas de plancher par fichier : un livre peut légitimement n'avoir
        // qu'une introduction et aucun chapitre. Le compte qui protège ici est
        // celui des fichiers — `Toujours` exige qu'il en existe au moins un,
        // donc un `books/` vidé rougit.
        plancher: None,
        jetons: &["books/", "dist/books"],
        lectures: &[
            (Liseuse::Ios, Lecture::Lit),
            (Liseuse::Android, Lecture::Lit),
            (Liseuse::Site, Lecture::Lit),
        ],
    },
    Artefact {
        cible: Cible::Exact("glossary.json"),
        emission: Emission::Toujours,
        plancher: Some(Plancher {
            champ: "entries",
            minimum: 1,
        }),
        jetons: &["glossary.json"],
        lectures: &[
            (Liseuse::Ios, Lecture::Lit),
            (Liseuse::Android, Lecture::Lit),
            (Liseuse::Site, Lecture::Lit),
        ],
    },
    Artefact {
        cible: Cible::Exact("shemot.json"),
        emission: Emission::Toujours,
        plancher: Some(Plancher {
            champ: "entries",
            minimum: 1,
        }),
        jetons: &["shemot.json"],
        lectures: &[
            (Liseuse::Ios, Lecture::Lit),
            (Liseuse::Android, Lecture::Lit),
            // Vert depuis le 10 septembre 2026 seulement. Le site incluait ce
            // fichier sans le servir : `/fr/lexique/noach` rendait 200 et
            // « Fiche introuvable », pour ~2 878 liens de Shem. C'est le défaut
            // qui a fait écrire ce module.
            (Liseuse::Site, Lecture::Lit),
        ],
    },
    Artefact {
        cible: Cible::Exact("occurrences.json"),
        emission: Emission::Toujours,
        plancher: Some(Plancher {
            champ: "byLemma",
            minimum: 1,
        }),
        jetons: &["occurrences.json"],
        lectures: &[
            (Liseuse::Ios, Lecture::Lit),
            (Liseuse::Android, Lecture::Lit),
            (Liseuse::Site, Lecture::Lit),
        ],
    },
    Artefact {
        cible: Cible::Exact("search.json"),
        emission: Emission::Toujours,
        plancher: Some(Plancher {
            champ: "records",
            minimum: 1,
        }),
        jetons: &["search.json"],
        lectures: &[
            (Liseuse::Ios, Lecture::Lit),
            (Liseuse::Android, Lecture::Lit),
            (Liseuse::Site, Lecture::Lit),
        ],
    },
    Artefact {
        cible: Cible::Exact("daily.json"),
        emission: Emission::Toujours,
        plancher: Some(Plancher {
            champ: "verses",
            minimum: 1,
        }),
        jetons: &["daily.json"],
        lectures: &[
            (Liseuse::Ios, Lecture::Lit),
            (Liseuse::Android, Lecture::Lit),
            (Liseuse::Site, Lecture::Lit),
        ],
    },
    Artefact {
        cible: Cible::Exact("manifest.json"),
        emission: Emission::Toujours,
        // `stats` est un objet, pas un tableau : son plancher vaut « il porte
        // des champs ». Maigre, mais un `manifest.json` réduit à `{}` est
        // exactement la panne que le compte doit voir.
        plancher: Some(Plancher {
            champ: "stats",
            minimum: 1,
        }),
        jetons: &["manifest.json"],
        lectures: &[
            (Liseuse::Ios, Lecture::Lit),
            (Liseuse::Android, Lecture::Lit),
            (Liseuse::Site, Lecture::Lit),
        ],
    },
    Artefact {
        cible: Cible::Exact("chuqqot.json"),
        emission: Emission::Toujours,
        // Aucun plancher : l'émission écrit ce fichier **même vide**, et le dit
        // en toutes lettres. Voir l'en-tête du module.
        plancher: None,
        jetons: &["chuqqot.json"],
        lectures: &[
            (
                Liseuse::Ios,
                Lecture::Lacune(
                    "`ChuqqotTab` affiche « Ils ne sont pas encore écrits » alors que le \
                     pipeline émet le fichier — l'onglet ne l'ouvre pas",
                ),
            ),
            (
                Liseuse::Android,
                Lecture::Lacune("l'onglet Chuqqot n'a pas encore d'écran (MainActivity)"),
            ),
            (
                Liseuse::Site,
                Lecture::Lacune(
                    "le site n'a pas d'espace d'adresses `/fr/chuqqot/…` ; les renvois y \
                     sont colorés et délibérément inertes",
                ),
            ),
        ],
    },
    Artefact {
        cible: Cible::Exact("prononciation.json"),
        emission: Emission::Facultative(
            "écrit seulement si le vault porte `lexique/prononciation.md`",
        ),
        plancher: Some(Plancher {
            champ: "blocks",
            minimum: 1,
        }),
        jetons: &["prononciation.json"],
        lectures: &[
            (Liseuse::Ios, Lecture::Lit),
            (
                Liseuse::Android,
                Lecture::Ignore(
                    "exclu de `copierLesDonnees` en connaissance de cause — voir la raison \
                     écrite dans `android/app/build.gradle.kts`",
                ),
            ),
            (
                Liseuse::Site,
                Lecture::Lacune("la feuille de prononciation n'a pas de page sur le site"),
            ),
        ],
    },
    Artefact {
        cible: Cible::Exact("sources/manifeste.json"),
        emission: Emission::Facultative("la couche des langues sources est facultative"),
        plancher: None,
        // **`manifeste.json` seul serait un faux positif.** iOS porte ce nom
        // pour un tout autre fichier — le manifeste du corpus publié, servi par
        // `corpus-publie.py`. Le jeton doit donc porter son dossier.
        jetons: &["sources/manifeste.json"],
        lectures: &[
            (
                Liseuse::Ios,
                Lecture::Lacune("`SourcesUpdater` est spécifié, pas encore écrit"),
            ),
            (
                Liseuse::Android,
                Lecture::Lacune("Android suit iOS sur ce chantier"),
            ),
            (
                Liseuse::Site,
                Lecture::Lacune("le site n'expose pas encore les langues sources"),
            ),
        ],
    },
    Artefact {
        cible: Cible::Sous("sources/"),
        emission: Emission::Facultative("la couche des langues sources est facultative"),
        plancher: None,
        jetons: &["dist/sources", "sources/he-", "sources/gr-"],
        lectures: &[
            (
                Liseuse::Ios,
                Lecture::Lacune("`SourcesUpdater` est spécifié, pas encore écrit"),
            ),
            (
                Liseuse::Android,
                Lecture::Lacune("Android suit iOS sur ce chantier"),
            ),
            (
                Liseuse::Site,
                Lecture::Lacune("le site n'expose pas encore les langues sources"),
            ),
        ],
    },
    Artefact {
        cible: Cible::Exact("report.md"),
        emission: Emission::ApresLeReleve("il porte ce relevé, donc il s'écrit après lui"),
        plancher: None,
        // Aucun jeton : ce fichier ne s'embarque nulle part, il se lit par
        // un humain dans `dist/`. Rien à prouver chez les liseuses.
        jetons: &[],
        lectures: &[
            (
                Liseuse::Ios,
                Lecture::Ignore("rapport de build, destiné à l'auteur"),
            ),
            (
                Liseuse::Android,
                Lecture::Ignore("rapport de build, destiné à l'auteur"),
            ),
            (
                Liseuse::Site,
                Lecture::Ignore("rapport de build, destiné à l'auteur"),
            ),
        ],
    },
];

// ─────────────────────────────────────────────────────────────────────────────
// Ce que le relevé rend
// ─────────────────────────────────────────────────────────────────────────────

/// Un fichier trouvé dans `dist/`, avec le compte de ses collections de tête.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Emis {
    /// Le chemin **relatif à `dist/`**, en séparateurs `/`.
    pub chemin: String,
    /// Pour chaque champ de tête qui est un tableau ou un objet, sa taille.
    pub comptes: BTreeMap<String, usize>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Ecart {
    /// Un fichier est là, et aucune ligne du tableau ne le couvre.
    EmisEtIgnore { chemin: String },
    /// Le tableau promet ce fichier, `dist/` ne le porte pas.
    AttenduNonEmis { cible: String },
    /// Le tableau dit qu'une liseuse le lit ; son source ne le nomme jamais.
    SansTrace { cible: String, liseuse: Liseuse },
    /// Le tableau dit qu'une liseuse ne le lit pas ; son source le nomme.
    ///
    /// Rouge malgré les apparences : le tableau est devenu faux. C'est la
    /// moitié du contrôle qui l'empêche de se périmer.
    TraceInattendue {
        cible: String,
        liseuse: Liseuse,
        etat: &'static str,
    },
    /// Le fichier est là, sa collection est sous le plancher.
    Vide {
        chemin: String,
        champ: String,
        compte: Option<usize>,
        minimum: usize,
    },
    /// Un défaut connu, nommé, qui ne casse pas la construction.
    Lacune {
        cible: String,
        liseuse: Liseuse,
        raison: &'static str,
    },
    /// Le source d'une liseuse n'est pas là : sa colonne n'a pas été mesurée.
    NonMesuree { liseuse: Liseuse },
}

impl Ecart {
    /// Est-ce que cet écart doit casser la construction ?
    ///
    /// `Lacune` non : elle est déjà connue, écrite et datée — la faire casser
    /// arrêterait le build de tout le monde pour une dette déjà inscrite.
    /// `NonMesuree` non plus : on ne condamne pas sur ce qu'on n'a pas regardé.
    /// Tout le reste, oui.
    pub fn rouge(&self) -> bool {
        !matches!(self, Ecart::Lacune { .. } | Ecart::NonMesuree { .. })
    }
}

impl fmt::Display for Ecart {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Ecart::EmisEtIgnore { chemin } => write!(
                f,
                "`{chemin}` est écrit dans `dist/` et **aucune ligne du tableau ne le couvre** — \
                 personne ne sait qui doit le lire"
            ),
            Ecart::AttenduNonEmis { cible } => write!(
                f,
                "`{cible}` est déclaré émis à tous les coups, et **`dist/` ne le porte pas**"
            ),
            Ecart::SansTrace { cible, liseuse } => write!(
                f,
                "`{cible}` : {} est déclarée le lire, et **son source ne le nomme nulle part**",
                liseuse.nom()
            ),
            Ecart::TraceInattendue {
                cible,
                liseuse,
                etat,
            } => write!(
                f,
                "`{cible}` : le tableau dit « {etat} » pour {}, mais son source le nomme — \
                 le tableau est à corriger, pas le code",
                liseuse.nom()
            ),
            Ecart::Vide {
                chemin,
                champ,
                compte,
                minimum,
            } => match compte {
                Some(n) => write!(
                    f,
                    "`{chemin}` : `{champ}` porte **{n}** entrée(s), le plancher est à {minimum}"
                ),
                None => write!(
                    f,
                    "`{chemin}` : le champ `{champ}` est **absent** — la forme du fichier a changé"
                ),
            },
            Ecart::Lacune {
                cible,
                liseuse,
                raison,
            } => write!(f, "`{cible}` — {} : {raison}", liseuse.nom()),
            Ecart::NonMesuree { liseuse } => write!(
                f,
                "{} : son source n'est pas là, sa colonne n'a pas été mesurée",
                liseuse.nom()
            ),
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Le cœur, et il est pur
// ─────────────────────────────────────────────────────────────────────────────

/// Rapproche l'inventaire de `dist/` du tableau et des sources des liseuses.
///
/// **Pure, et c'est ce qui la rend éprouvable.** Les deux entrées — ce qui est
/// écrit, ce que les liseuses disent — sont injectées. Un test fabrique un
/// `dist/` d'une ligne et un source d'une chaîne, et fait rougir chacun des sept
/// écarts sans jamais bâtir le corpus ni neutraliser quoi que ce soit. Le
/// mémo du projet le demande : *un contrôle qui ne peut pas rougir ne mesure
/// rien*, et il faut pouvoir le lui faire faire à volonté.
///
/// `sources` : `None` pour une liseuse absente du disque, `Some(source)` sinon
/// — tout son source concaténé, l'ordre n'important pas puisqu'on n'y cherche
/// que des sous-chaînes.
pub fn rapprocher(emis: &[Emis], sources: &BTreeMap<Liseuse, Option<String>>) -> Vec<Ecart> {
    let mut ecarts = Vec::new();

    for liseuse in Liseuse::TOUTES {
        if !matches!(sources.get(&liseuse), Some(Some(_))) {
            ecarts.push(Ecart::NonMesuree { liseuse });
        }
    }

    // ── Sens 1 : émis que le tableau ne connaît pas ──────────────────────
    //
    // C'est la garde d'Android, remontée. La différence : elle descend dans
    // les sous-dossiers, là où `listFiles()` s'arrêtait à la racine — un livre
    // de trop dans `books/` lui échappait.
    for fichier in emis {
        if !ARTEFACTS.iter().any(|a| a.cible.couvre(&fichier.chemin)) {
            ecarts.push(Ecart::EmisEtIgnore {
                chemin: fichier.chemin.clone(),
            });
        }
    }

    for artefact in ARTEFACTS {
        let couverts: Vec<&Emis> = emis
            .iter()
            .filter(|e| artefact.cible.couvre(&e.chemin))
            .collect();

        // ── Sens 2 : attendu et non écrit ────────────────────────────────
        match artefact.emission {
            Emission::Toujours if couverts.is_empty() => {
                ecarts.push(Ecart::AttenduNonEmis {
                    cible: artefact.cible.dit().to_string(),
                });
                // Rien n'est écrit : ni plancher ni preuve de lecture à
                // vérifier. Le dire deux fois noierait la vraie cause.
                continue;
            }
            // Une couche facultative absente est un vault sans cette couche,
            // pas une panne. On ne dit rien plutôt que d'inventer un défaut.
            Emission::Facultative(_) if couverts.is_empty() => continue,
            // Il ne peut pas être là, il s'écrit après. S'il y est, c'est un
            // reste d'un build précédent — mais `dist/` est effacé au début,
            // donc le cas n'existe pas ; on ne le traite pas comme un défaut.
            Emission::ApresLeReleve(_) => continue,
            _ => {}
        }

        // ── Les comptes ──────────────────────────────────────────────────
        if let Some(plancher) = artefact.plancher {
            for fichier in &couverts {
                let compte = fichier.comptes.get(plancher.champ).copied();
                if compte.is_none_or(|n| n < plancher.minimum) {
                    ecarts.push(Ecart::Vide {
                        chemin: fichier.chemin.clone(),
                        champ: plancher.champ.to_string(),
                        compte,
                        minimum: plancher.minimum,
                    });
                }
            }
        }

        // ── Sens 3 : la preuve chez les liseuses ─────────────────────────
        if artefact.jetons.is_empty() {
            continue;
        }
        for (liseuse, lecture) in artefact.lectures {
            let Some(Some(source)) = sources.get(liseuse) else {
                // Colonne non mesurée : déjà signalée une fois plus haut. La
                // redire par artefact rendrait treize lignes pour une cause.
                continue;
            };
            let trace = artefact.jetons.iter().any(|j| source.contains(j));
            let cible = artefact.cible.dit().to_string();
            match (lecture, trace) {
                (Lecture::Lit, false) => ecarts.push(Ecart::SansTrace {
                    cible,
                    liseuse: *liseuse,
                }),
                (Lecture::Ignore(_), true) => ecarts.push(Ecart::TraceInattendue {
                    cible,
                    liseuse: *liseuse,
                    etat: "ne le lit pas, par décision",
                }),
                (Lecture::Lacune(_), true) => ecarts.push(Ecart::TraceInattendue {
                    cible,
                    liseuse: *liseuse,
                    etat: "lacune connue",
                }),
                (Lecture::Lacune(raison), false) => ecarts.push(Ecart::Lacune {
                    cible,
                    liseuse: *liseuse,
                    raison,
                }),
                (Lecture::Lit, true) | (Lecture::Ignore(_), false) => {}
            }
        }
    }

    ecarts
}

// ─────────────────────────────────────────────────────────────────────────────
// Les deux relevés, qui touchent au disque
// ─────────────────────────────────────────────────────────────────────────────

/// Inventorie `dist/` — récursivement — et compte les collections de tête.
///
/// **On marche le dossier plutôt que d'instrumenter `write_json`.** Deux
/// raisons, et la seconde est la vraie :
///
/// - le helper d'écriture est partagé, et le toucher pour l'observer met un
///   effet de bord dans une fonction qui n'en avait pas ;
/// - surtout, un registre tenu par l'émetteur ne mesure que ce que l'émetteur
///   croit avoir fait. Le dossier, lui, dit ce qui est. C'est la règle que tout
///   `controles.rs` applique déjà : *on ne mesure pas la source, on mesure
///   `dist/`*. Le dossier est effacé au début du build, donc ce qu'on y trouve
///   vient de ce build et d'aucun autre.
pub fn relever_dist(dist: &Path) -> std::io::Result<Vec<Emis>> {
    let mut trouves = Vec::new();
    descendre(dist, dist, &mut trouves)?;
    trouves.sort_by(|a, b| a.chemin.cmp(&b.chemin));
    Ok(trouves)
}

fn descendre(racine: &Path, dossier: &Path, out: &mut Vec<Emis>) -> std::io::Result<()> {
    if !dossier.exists() {
        return Ok(());
    }
    for entree in std::fs::read_dir(dossier)? {
        let chemin = entree?.path();
        if chemin.is_dir() {
            descendre(racine, &chemin, out)?;
            continue;
        }
        let Ok(relatif) = chemin.strip_prefix(racine) else {
            continue;
        };
        let relatif = relatif.to_string_lossy().replace('\\', "/");
        // Les fichiers cachés du système — `.DS_Store` sur un Mac — ne sont
        // pas des émissions du pipeline. Les compter ferait rougir un build
        // parce que le Finder est passé dans le dossier.
        if relatif.starts_with('.') || relatif.contains("/.") {
            continue;
        }
        out.push(Emis {
            comptes: compter(&chemin),
            chemin: relatif,
        });
    }
    Ok(())
}

/// Compte les collections de tête d'un JSON écrit.
///
/// Générique à dessein : lire le fichier en `Value` plutôt que dans son type
/// permet au contrôle de rester ignorant du schéma. Sinon chaque nouvelle
/// émission demanderait une ligne ici *et* une ligne dans `schema.rs` — le
/// module partagé que deux autres sessions retouchent en ce moment.
///
/// Un fichier illisible ou non-JSON rend une table vide : le plancher le verra
/// comme un champ absent, ce qui est le bon message.
fn compter(chemin: &Path) -> BTreeMap<String, usize> {
    let mut comptes = BTreeMap::new();
    let Ok(texte) = std::fs::read_to_string(chemin) else {
        return comptes;
    };
    let Ok(serde_json::Value::Object(tete)) = serde_json::from_str::<serde_json::Value>(&texte)
    else {
        return comptes;
    };
    for (cle, valeur) in tete {
        let taille = match valeur {
            serde_json::Value::Array(v) => v.len(),
            serde_json::Value::Object(m) => m.len(),
            // Une chaîne ou un nombre n'est pas une collection : lui donner un
            // compte laisserait poser un plancher sur `schema: 1`, qui ne
            // mesurerait rien.
            _ => continue,
        };
        comptes.insert(cle, taille);
    }
    comptes
}

/// Lit le source de chaque liseuse, ou déclare qu'elle n'est pas là.
///
/// Tout est concaténé en une chaîne par liseuse : on n'y cherche que des
/// sous-chaînes, et garder la structure de fichiers n'apporterait qu'un numéro
/// de ligne qu'on n'affiche pas.
pub fn lire_les_sources(depot: &Path) -> BTreeMap<Liseuse, Option<String>> {
    Liseuse::TOUTES
        .into_iter()
        .map(|liseuse| {
            let mut vu = false;
            let mut tout = String::new();
            for racine in liseuse.racines(depot) {
                if racine.exists() {
                    vu = true;
                    aspirer(&racine, liseuse.extensions(), &mut tout);
                }
            }
            (liseuse, if vu { Some(tout) } else { None })
        })
        .collect()
}

/// Les dossiers qu'on ne traverse jamais.
///
/// Des artefacts de compilation, pas du source. Y descendre coûterait des
/// gigaoctets et, pire, y trouverait des traces : un `.build` de Swift porte
/// les chaînes du binaire, ce qui rendrait toute liseuse « lectrice » de tout.
const IGNORES: &[&str] = &[
    ".git",
    ".build",
    ".gradle",
    "build",
    "target",
    "dist",
    "node_modules",
    "DerivedData",
    "Pods",
];

fn aspirer(chemin: &Path, extensions: &[&str], dans: &mut String) {
    if chemin.is_file() {
        if let Some(ext) = chemin.extension().and_then(|e| e.to_str()) {
            if extensions.contains(&ext) {
                if let Ok(t) = std::fs::read_to_string(chemin) {
                    // ## Un fichier engendré par le pipeline n'est pas un lecteur
                    //
                    // `Schema.swift` et `Schema.kt` portent la bonne extension
                    // et vivent au milieu du source de la liseuse, mais c'est
                    // **le pipeline** qui les écrit, depuis `schema.rs`, et
                    // leurs commentaires de documentation nomment les fichiers
                    // de `dist/` qu'ils décrivent. Les aspirer revient à
                    // demander au contrôle s'il connaît ses propres écrits.
                    //
                    // Les deux conséquences n'ont pas la même gravité, et la
                    // pire est la muette :
                    //
                    // - un faux rouge — `prononciation.json` est en
                    //   `Ignore` pour Android, et `Schema.kt` le nomme : le
                    //   tableau se fait accuser d'avoir tort alors qu'il a
                    //   raison ;
                    // - **un faux vert** — `Schema.swift` nomme sept des neuf
                    //   jetons du tableau. Chaque `Lit` d'iOS serait satisfait
                    //   par lui seul, donc satisfait même le jour où le vrai
                    //   lecteur disparaît. Un contrôle qui ne peut plus rougir
                    //   ne mesure plus rien.
                    //
                    // Le défaut était en plus **intermittent**, ce qui l'a
                    // laissé passer : ces fichiers sont engendrés *après* ce
                    // relevé, et ne sont pas committés. Sur un arbre neuf —
                    // donc dans les deux jobs de la CI — ils n'existent pas
                    // encore, et le premier passage est vert. C'est le second
                    // `corpus.sh` qui rougissait, en local seulement.
                    //
                    // On reconnaît la marque plutôt qu'une liste de noms : un
                    // fichier engendré demain sera écarté sans que personne
                    // n'ait à y penser.
                    if t.starts_with(crate::schema::MARQUE_ENGENDRE) {
                        return;
                    }
                    dans.push_str(&t);
                    dans.push('\n');
                }
            }
        }
        return;
    }
    let nom = chemin
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_default();
    if IGNORES.contains(&nom.as_str()) {
        return;
    }
    let Ok(entrees) = std::fs::read_dir(chemin) else {
        return;
    };
    for entree in entrees.flatten() {
        aspirer(&entree.path(), extensions, dans);
    }
}

/// La racine du dépôt `ONTBibleApp`, d'où l'on trouve `app/`, `android/` et le
/// dépôt voisin du site.
///
/// `ONT_DEPOT` la surcharge — c'est ce qui rend le contrôle utilisable depuis
/// une CI qui range les dépôts autrement, et c'est aussi ce qui permet de le
/// faire rougir à la main : le pointer sur un dossier vide rend les trois
/// colonnes « non mesurées ».
pub fn racine_du_depot() -> PathBuf {
    match std::env::var("ONT_DEPOT") {
        Ok(v) => PathBuf::from(v),
        Err(_) => PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(".."),
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// La section du rapport
// ─────────────────────────────────────────────────────────────────────────────

/// Rend les lignes markdown de la section « Fichiers émis et fichiers lus ».
///
/// Elle vit ici plutôt que dans `format_report` pour une raison de voisinage :
/// deux sessions travaillent dans `build.rs` en ce moment, et l'y écrire ferait
/// un conflit de fusion pour trente lignes qui n'ont besoin de rien de ce
/// fichier.
pub fn lignes_du_rapport(ecarts: &[Ecart]) -> Vec<String> {
    let mut l = vec![
        "## Fichiers émis et fichiers lus".into(),
        String::new(),
        "Ce que `dist/` porte, rapproché de ce que le source de chaque liseuse nomme. \
         Une mention prouve qu'un dépôt **connaît** le fichier, jamais qu'il l'ouvre."
            .into(),
        String::new(),
    ];

    let rouges: Vec<&Ecart> = ecarts.iter().filter(|e| e.rouge()).collect();
    if rouges.is_empty() {
        l.push("Aucun écart bloquant.".into());
    } else {
        l.push(format!("**{} écart(s) bloquant(s) :**", rouges.len()));
        l.push(String::new());
        for e in rouges {
            l.push(format!("- {e}"));
        }
    }
    l.push(String::new());

    let lacunes: Vec<&Ecart> = ecarts
        .iter()
        .filter(|e| matches!(e, Ecart::Lacune { .. }))
        .collect();
    if !lacunes.is_empty() {
        l.push(format!(
            "**{} lacune(s) connue(s)** — émis, personne ne le lit encore. Elles ne \
             cassent pas la construction ; elles sont nommées pour qu'on les ferme.",
            lacunes.len()
        ));
        l.push(String::new());
        for e in lacunes {
            l.push(format!("- {e}"));
        }
        l.push(String::new());
    }

    let non_mesurees: Vec<&Ecart> = ecarts
        .iter()
        .filter(|e| matches!(e, Ecart::NonMesuree { .. }))
        .collect();
    if !non_mesurees.is_empty() {
        l.push("**Colonnes non mesurées** — ni vertes ni rouges, regardées par personne :".into());
        l.push(String::new());
        for e in non_mesurees {
            l.push(format!("- {e}"));
        }
        l.push(String::new());
    }

    l
}

/// Le message d'échec, écrit pour celui qui le recevra sans contexte.
pub fn dire_l_echec(ecarts: &[Ecart]) -> String {
    let rouges: Vec<String> = ecarts
        .iter()
        .filter(|e| e.rouge())
        .map(|e| format!("  · {e}"))
        .collect();
    format!(
        "{} écart(s) entre ce que `dist/` porte et ce que les liseuses lisent :\n{}\n\n\
         `dist/report.md` vient d'être écrit et redit lesquels, section « Fichiers émis\n\
         et fichiers lus ».\n\n\
         Trois sorties, et une seule est bonne selon le cas :\n\
         — écrire le lecteur qui manque, puis passer sa ligne à `Lecture::Lit` ;\n\
         — assumer qu'une liseuse ne lit pas ce fichier, et l'écrire en\n\
         `Lecture::Ignore(\"pourquoi\")` — la raison est le seul prix ;\n\
         — cesser d'émettre le fichier, et retirer sa ligne du tableau.\n\n\
         Une quatrième existe et n'en est pas une : `Lecture::Lacune` porte une dette\n\
         déjà nommée. L'inventer pour taire un écart neuf, c'est éteindre le contrôle.",
        rouges.len(),
        rouges.join("\n")
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Un `dist/` complet et trois liseuses qui nomment tout : l'état vert.
    fn tout_va_bien() -> (Vec<Emis>, BTreeMap<Liseuse, Option<String>>) {
        let mut emis = Vec::new();
        for artefact in ARTEFACTS {
            if matches!(artefact.emission, Emission::ApresLeReleve(_)) {
                continue;
            }
            let chemin = match artefact.cible {
                Cible::Exact(c) => c.to_string(),
                Cible::Sous(p) => format!("{p}exemple.json"),
            };
            let mut comptes = BTreeMap::new();
            if let Some(p) = artefact.plancher {
                comptes.insert(p.champ.to_string(), p.minimum);
            }
            emis.push(Emis { chemin, comptes });
        }

        // Chaque liseuse nomme tout ce qu'elle est censée lire, et rien de ce
        // qu'elle est censée ignorer : c'est ce que « vert » veut dire.
        let sources = Liseuse::TOUTES
            .into_iter()
            .map(|liseuse| {
                let mut source = String::new();
                for artefact in ARTEFACTS {
                    let lit = artefact
                        .lectures
                        .iter()
                        .any(|(l, lecture)| *l == liseuse && matches!(lecture, Lecture::Lit));
                    if lit {
                        if let Some(jeton) = artefact.jetons.first() {
                            source.push_str(jeton);
                            source.push('\n');
                        }
                    }
                }
                (liseuse, Some(source))
            })
            .collect();
        (emis, sources)
    }

    #[test]
    fn le_tableau_est_complet_et_sans_doublon() {
        // Chaque artefact nomme les trois liseuses, exactement une fois. Sans
        // ça, une liseuse ajoutée demain hériterait d'un tableau muet sur elle
        // — et un tableau muet est vert.
        for artefact in ARTEFACTS {
            for liseuse in Liseuse::TOUTES {
                let dits = artefact
                    .lectures
                    .iter()
                    .filter(|(l, _)| *l == liseuse)
                    .count();
                assert_eq!(
                    dits,
                    1,
                    "`{}` doit dire exactement une fois ce que fait {}",
                    artefact.cible.dit(),
                    liseuse.nom()
                );
            }
        }
    }

    #[test]
    fn vert_quand_tout_concorde() {
        let (emis, sources) = tout_va_bien();
        let ecarts = rapprocher(&emis, &sources);
        let rouges: Vec<&Ecart> = ecarts.iter().filter(|e| e.rouge()).collect();
        assert!(rouges.is_empty(), "devait être vert, obtenu : {rouges:?}");
    }

    /// **La preuve que le contrôle peut rougir**, cas par cas.
    ///
    /// Chacun de ces tests retire une chose au monde vert et vérifie que
    /// l'écart correspondant paraît. Un contrôle dont on n'a pas vu chacun des
    /// bras échouer n'a de contrôle que le nom : c'est la règle du projet.
    #[test]
    fn rougit_sur_un_fichier_que_personne_ne_lit() {
        let (mut emis, sources) = tout_va_bien();
        emis.push(Emis {
            chemin: "invente.json".into(),
            comptes: BTreeMap::new(),
        });
        let ecarts = rapprocher(&emis, &sources);
        assert!(ecarts.iter().any(|e| matches!(
            e,
            Ecart::EmisEtIgnore { chemin } if chemin == "invente.json"
        )));
    }

    #[test]
    fn rougit_sur_un_fichier_attendu_et_absent() {
        let (mut emis, sources) = tout_va_bien();
        emis.retain(|e| e.chemin != "glossary.json");
        let ecarts = rapprocher(&emis, &sources);
        assert!(ecarts.iter().any(|e| matches!(
            e,
            Ecart::AttenduNonEmis { cible } if cible == "glossary.json"
        )));
    }

    #[test]
    fn rougit_quand_on_retire_un_lecteur() {
        // Le geste demandé noir sur blanc : retirer un lecteur, et voir.
        let (emis, mut sources) = tout_va_bien();
        let source = sources.get_mut(&Liseuse::Site).unwrap().as_mut().unwrap();
        *source = source.replace("shemot.json", "");
        let ecarts = rapprocher(&emis, &sources);
        assert!(ecarts.iter().any(|e| matches!(
            e,
            Ecart::SansTrace { cible, liseuse } if cible == "shemot.json" && *liseuse == Liseuse::Site
        )));
    }

    #[test]
    fn rougit_quand_le_tableau_se_perime() {
        // Quelqu'un écrit le lecteur des chuqqot côté iOS : la lacune n'en est
        // plus une, et le tableau doit l'apprendre.
        let (emis, mut sources) = tout_va_bien();
        sources
            .get_mut(&Liseuse::Ios)
            .unwrap()
            .as_mut()
            .unwrap()
            .push_str("chuqqot.json\n");
        let ecarts = rapprocher(&emis, &sources);
        assert!(ecarts.iter().any(|e| matches!(
            e,
            Ecart::TraceInattendue { cible, liseuse, .. }
                if cible == "chuqqot.json" && *liseuse == Liseuse::Ios
        )));
    }

    #[test]
    fn rougit_sur_une_collection_videe() {
        // Le cas `book_names`, 67 → 0, build resté vert.
        let (mut emis, sources) = tout_va_bien();
        for e in emis.iter_mut() {
            if e.chemin == "glossary.json" {
                e.comptes.insert("entries".into(), 0);
            }
        }
        let ecarts = rapprocher(&emis, &sources);
        assert!(ecarts.iter().any(|e| matches!(
            e,
            Ecart::Vide { chemin, compte, .. } if chemin == "glossary.json" && *compte == Some(0)
        )));
    }

    #[test]
    fn rougit_sur_une_collection_renommee() {
        // Un `rename` posé dans `schema.rs` change le nom du champ livré : le
        // fichier reste plein, le site ne le lit plus. Le plancher le voit,
        // parce qu'il cherche le nom **sérialisé**.
        let (mut emis, sources) = tout_va_bien();
        for e in emis.iter_mut() {
            if e.chemin == "occurrences.json" {
                e.comptes.remove("byLemma");
                e.comptes.insert("by_lemma".into(), 42);
            }
        }
        let ecarts = rapprocher(&emis, &sources);
        assert!(ecarts.iter().any(|e| matches!(
            e,
            Ecart::Vide { chemin, compte: None, .. } if chemin == "occurrences.json"
        )));
    }

    #[test]
    fn une_liseuse_absente_n_est_pas_verte() {
        let (emis, mut sources) = tout_va_bien();
        sources.insert(Liseuse::Site, None);
        let ecarts = rapprocher(&emis, &sources);
        assert!(ecarts
            .iter()
            .any(|e| matches!(e, Ecart::NonMesuree { liseuse } if *liseuse == Liseuse::Site)));
        // Et surtout : elle ne produit aucun `SansTrace`, qui accuserait une
        // liseuse qu'on n'a pas regardée.
        assert!(!ecarts
            .iter()
            .any(|e| matches!(e, Ecart::SansTrace { liseuse, .. } if *liseuse == Liseuse::Site)));
    }

    #[test]
    fn une_couche_facultative_absente_ne_dit_rien() {
        let (mut emis, sources) = tout_va_bien();
        emis.retain(|e| !e.chemin.starts_with("sources/") && e.chemin != "prononciation.json");
        let ecarts = rapprocher(&emis, &sources);
        assert!(!ecarts.iter().any(|e| matches!(
            e,
            Ecart::AttenduNonEmis { cible } if cible.starts_with("sources/") || cible == "prononciation.json"
        )));
    }

    #[test]
    fn le_rapport_ne_ment_pas_quand_tout_va_bien() {
        let (emis, sources) = tout_va_bien();
        let lignes = lignes_du_rapport(&rapprocher(&emis, &sources)).join("\n");
        assert!(lignes.contains("Aucun écart bloquant"));
    }

    // ─────────────────────────────────────────────────────────────────────
    // Ce qui compte comme source d'une liseuse
    // ─────────────────────────────────────────────────────────────────────

    /// Un dossier jetable, sans dépendance de développement.
    ///
    /// `tempfile` ferait le travail, mais la caisse n'a aucune
    /// `dev-dependencies` aujourd'hui et le site la compile en
    /// `--no-default-features` : une dépendance de plus pour trois tests se
    /// paierait chez lui aussi.
    fn dossier_jetable(nom: &str) -> PathBuf {
        let unique = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or_default();
        let chemin = std::env::temp_dir().join(format!("ont-aspirer-{nom}-{unique}"));
        std::fs::create_dir_all(&chemin).expect("créer le dossier jetable");
        chemin
    }

    /// Ce qu'`aspirer` retient d'un unique fichier posé dans un dossier neuf.
    fn aspire(nom_du_test: &str, nom_du_fichier: &str, contenu: &str) -> String {
        let dossier = dossier_jetable(nom_du_test);
        std::fs::write(dossier.join(nom_du_fichier), contenu).expect("écrire le fichier");
        let mut vu = String::new();
        aspirer(&dossier, Liseuse::Android.extensions(), &mut vu);
        let _ = std::fs::remove_dir_all(&dossier);
        vu
    }

    /// L'en-tête exact des fichiers engendrés, tel que `codegen` l'écrit.
    ///
    /// Reconstitué depuis la constante partagée, et non recopié : un test qui
    /// recopierait la marque continuerait de passer le jour où elle change,
    /// alors même que le code réel aurait cessé de la reconnaître.
    fn schema_engendre(jeton: &str) -> String {
        format!(
            "{}\n//\n// Source : pipeline/src/schema.rs\n//\n/** `dist/{jeton}` — la feuille. */\n",
            crate::schema::MARQUE_ENGENDRE
        )
    }

    #[test]
    fn un_schema_engendre_ne_prouve_aucune_lecture() {
        // Le défaut réel du 11 septembre 2026 : `Schema.kt` est engendré par le
        // pipeline **après** ce relevé, n'est pas committé, et son commentaire
        // de documentation nomme `dist/prononciation.json`. Au deuxième
        // `corpus.sh` d'affilée il était là, et le tableau — qui dit avec
        // raison qu'Android ignore ce fichier — se faisait accuser d'avoir
        // tort.
        //
        // Ce test rougit sur le code d'avant : sans la reconnaissance de la
        // marque, le jeton se retrouve dans le source d'Android.
        let vu = aspire("engendre", "Schema.kt", &schema_engendre("prononciation.json"));
        assert!(
            !vu.contains("prononciation.json"),
            "un fichier engendré par le pipeline ne doit pas compter comme source : {vu}"
        );
    }

    #[test]
    fn un_vrai_lecteur_kotlin_compte_toujours() {
        // L'autre moitié de la paire : sans la marque, le même contenu est du
        // source écrit à la main, et il prouve bien que le dépôt connaît le
        // fichier. Sans ce test, écarter *tous* les `.kt` passerait aussi.
        let vu = aspire(
            "lecteur",
            "PrononciationStore.kt",
            "package com.labibleont.ont\n// lit dist/prononciation.json\n",
        );
        assert!(
            vu.contains("prononciation.json"),
            "un lecteur écrit à la main doit compter : {vu}"
        );
    }

    #[test]
    fn un_gradle_kts_n_est_pas_du_source_kotlin() {
        // `android/app/build.gradle.kts` porte `exclude("prononciation.json")`
        // — il nomme précisément ce qu'Android **ne** lit **pas**. Le compter
        // rendrait le contrôle vert là où la vérité est l'inverse.
        //
        // Le filtre compare l'extension entière ; un `chemin.contains(".kt")`
        // laisserait passer `.kts`. Le test fige la différence, qui ne se voit
        // pas à la relecture.
        let vu = aspire(
            "gradle",
            "build.gradle.kts",
            "android { exclude(\"prononciation.json\") }\n",
        );
        assert!(
            !vu.contains("prononciation.json"),
            "la configuration de build n'est pas un lecteur : {vu}"
        );
    }
}
