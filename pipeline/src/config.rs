//! Les chemins et les quelques noms qui ne se déduisent pas.

use std::path::PathBuf;

/// La racine du vault — le dépôt de la traduction.
///
/// Relatif à ce dépôt : les deux sont côte à côte sous `ONTBible/`.
/// Surchargeable par `ONT_VAULT`, pour bâtir depuis un clone ailleurs — c'est
/// ce dont la CI se sert.
pub fn vault() -> PathBuf {
    match std::env::var("ONT_VAULT") {
        Ok(v) => PathBuf::from(v),
        Err(_) => PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("..")
            .join("ONTBibleTranslation"),
    }
}

/// L'estampille du corpus — la date de son **contenu**, pas de sa compilation.
///
/// ## Pourquoi elle vient de l'extérieur
///
/// Le pipeline est une fonction pure de ses entrées, et il le reste : lire
/// `.git` lui-même le rendrait dépendant de la forme du checkout — un export
/// d'archive, un `--depth 1`, un vault copié sans `.git`, et il tombe. C'est
/// l'appelant qui sait trouver la date :
///
/// ```sh
/// ONT_GENERE="$(git -C "$VAULT" log -1 --format=%cI)"
/// ```
///
/// ## Pourquoi la date du contenu et non celle du build
///
/// Deux exécutions sur le même vault doivent produire le même octet — c'est ce
/// qui garantit la même empreinte, donc aucun retéléchargement inutile chez les
/// lecteurs. Un horodatage de compilation romprait cette garantie et republierait
/// tout le corpus à chaque passage de CI.
///
/// La date du dernier commit du vault donne l'ordre qu'il faut **et** reste
/// déterministe : le même vault rend toujours la même date.
///
/// ## Ce qu'elle sert à trancher
///
/// Rien, jusqu'à ce qu'un bundle devienne plus récent que le corpus publié. Une
/// empreinte dit que deux corpus **diffèrent** ; elle ne dit jamais lequel vient
/// après. Sans cet ordre, une app neuve se fait écraser au premier lancement par
/// le corpus publié, et la fonctionnalité qu'elle apporte arrive invisible.
///
/// ## Vide plutôt que fausse
///
/// Sans `ONT_GENERE`, l'estampille reste vide, et les liseuses **refusent** un
/// manifeste qui n'en porte pas. Un corpus figé se voit et se répare ; un corpus
/// silencieusement remplacé par du plus ancien ne se voit pas.
pub fn genere() -> String {
    std::env::var("ONT_GENERE")
        .unwrap_or_default()
        .trim()
        .to_string()
}

/// Où le pipeline dépose ses données.
pub fn out() -> PathBuf {
    match std::env::var("ONT_OUT") {
        Ok(v) => PathBuf::from(v),
        Err(_) => PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("dist"),
    }
}

/// Les deux états du flux de validation (§12).
///
/// `locked/` fait référence. `brouillons/` miroite exactement son arborescence
/// et **ne voyage pas** dans la distribution — mais le pipeline le lit quand
/// même, pour que la liseuse d'atelier puisse l'afficher et que le rapport dise
/// où en est le corpus.
pub const TREES: [(&str, &str); 2] = [("locked", "locked"), ("brouillon", "brouillons")];

/// L'arborescence vide des 70 slots — elle définit le squelette du corpus.
pub const SKELETON: &str = "in-writing";

/// Le document de référence : conventions, glossaire, répertoires de noms.
pub const REFERENCE: &str = "CLAUDE.md";

/// Les fiches de lexique — un fichier par terme, `lexique/chesed.md`.
///
/// ## Pourquoi elles ne sont pas dans `CLAUDE.md`
///
/// Le document de référence est écrit **pour le traducteur** : ses entrées
/// consignent un arbitrage — pourquoi *Elohim* reste en hébreu. Le lecteur du
/// 21ᵉ siècle qui touche le mot d'or n'a pas cette question ; il en a une
/// autre, à laquelle rien ne répondait — ce que le mot voulait dire pour qui
/// l'écrivait.
///
/// Une seule source par *fait*, et non une source par champ : `CLAUDE.md`
/// garde l'hébreu, les formes, le rendu et la règle de balisage ; `lexique/`
/// ne porte que l'explication au lecteur, et remplace la définition quand elle
/// existe.
pub const LEXIQUE: &str = "lexique";

/// Les titres d'affichage des corpus et des modes.
///
/// Les dossiers portent des identifiants sans apostrophe ni majuscule —
/// `neviim`, `berit-hadashah` — parce qu'un nom de fichier doit rester sobre.
/// Ces quelques formes-là ne se déduisent pas mécaniquement de l'identifiant :
/// elles sont donc énoncées ici, et nulle part ailleurs.
const DISPLAY_NAMES: [(&str, &str); 12] = [
    ("kenesset", "Kenesset"),
    ("berit-hadashah", "Berit Hadashah"),
    ("torah", "Torah"),
    ("neviim", "Nevi'im"),
    ("ketouvim", "Ketouvim"),
    ("nistarot", "Nistarot"),
    ("besorot", "Besorot"),
    ("eduyot", "Eduyot"),
    ("trei-asar", "Trei Asar"),
    ("igerot", "Igerot"),
    ("igerot-lifnei-ha-hurban", "Igerot lifnei ha-Ḥurban"),
    ("igerot-aharei-ha-hurban", "Igerot aḥarei ha-Ḥurban"),
];

/// Le titre d'affichage d'un identifiant, à défaut une mise en capitales.
pub fn display_name(id: &str) -> String {
    if let Some((_, nom)) = DISPLAY_NAMES.iter().find(|(k, _)| *k == id) {
        return nom.to_string();
    }
    id.split('-')
        .map(|mot| {
            let mut chars = mot.chars();
            match chars.next() {
                // `to_uppercase` rend un itérateur : une lettre peut en donner
                // plusieurs — « ß » devient « SS ». Ici ce sont des latins
                // simples, mais on ne suppose pas.
                Some(premiere) => premiere.to_uppercase().collect::<String>() + chars.as_str(),
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

/// Les conteneurs intermédiaires, avec ce qu'ils disent au lecteur.
///
/// `(identifiant, français, glose, rupture)`. La glose n'est posée que
/// lorsqu'elle ajoute quelque chose au pont ; la rupture, que lorsque la
/// coupure en est une.
///
/// **Le Ḥurban est le seul à en porter une.** `corpus-order.md` le nomme
/// *pivot herméneutique* : d'un côté le monde du *Bayit* vivant, de l'autre
/// le monde d'après sa destruction. La ligne ne dit donc pas seulement la
/// date — elle dit ce que ça change pour lire : au-dessus, le Temple
/// fonctionne encore dans le texte.
///
/// *Ḥurban* et *Bayit* s'écrivent **en clair, sans or**. Ni l'un ni l'autre
/// n'a de fiche, et le §2.5 est net : l'or promet une explication et la tient.
/// Un mot doré sur du vide est le défaut que `==` a été créé pour supprimer.
pub const GROUPES: [(&str, &str, Option<&str>, Option<&str>); 4] = [
    (
        "eduyot",
        "les trois témoins",
        Some("les eduyot — trois témoins au sens de Devarim 19:15"),
        None,
    ),
    ("trei-asar", "les Douze", None, None),
    (
        "igerot-lifnei-ha-hurban",
        "Lettres d'avant la destruction",
        Some("les igerot d'avant le Ḥurban — le monde du Bayit vivant"),
        None,
    ),
    (
        "igerot-aharei-ha-hurban",
        "Lettres d'après la destruction",
        Some("les igerot d'après le Ḥurban — le monde d'après le Bayit"),
        Some("Le Second Temple est détruit en 70. Ce qui précède en parle au présent."),
    ),
];

/// Le conteneur nommé, s'il est déclaré.
pub fn groupe(id: &str) -> Option<(&'static str, Option<&'static str>, Option<&'static str>)> {
    GROUPES
        .iter()
        .find(|(k, ..)| *k == id)
        .map(|(_, fr, glose, rupture)| (*fr, *glose, *rupture))
}

/// Ce qu'une section dit au lecteur, dans les deux registres.
///
/// `(identifiant, français, glose)`.
///
/// ## Pourquoi deux colonnes et non une
///
/// Le français d'un livre est un **pont de navigation** : *Bereshit* est
/// ponté vers « Genèse », que personne ne tient pour une traduction. Le champ
/// sert d'ailleurs à la recherche — on tape le mot qu'on connaît.
///
/// Mais un pont dit où l'on est, pas ce que le nom veut dire. *Torah* se ponte
/// vers « la Loi » parce que c'est ainsi qu'on la nomme en français ; c'est
/// pourtant exactement la dégradation que l'ONT décrit — *torah*, l'instruction
/// qui vise, devenue *nomos*, le code qui contraint.
///
/// D'où la seconde colonne. **La règle qui les sépare est nette : en français
/// les intraduisibles sont rendus, en glose ils restent en hébreu.** L'écart
/// entre les deux est précisément ce que le projet cherche à faire voir.
///
/// La glose est absente quand elle redirait le français — *Ketouvim* est
/// « Écrits » dans les deux registres, et une glose qui répète n'apprend rien.
///
/// ## Pourquoi ce n'est pas déduit des dossiers du vault
///
/// Les noms de dossiers portent bien un libellé — `1. torah (la Fondation)` —
/// mais leur registre est **incohérent** : « la Fondation » et « les Réalités
/// voilées » sont des gloses ONT, « Prophètes » et « Écrits » du français
/// reçu. Les prendre tels quels mélangerait les deux colonnes. Ils restent
/// utiles pour les livres, où le libellé est bien un pont.
pub const SECTIONS: [(&str, &str, Option<&str>); 7] = [
    ("kenesset", "le Rassemblement", None),
    ("torah", "la Loi", Some("la Fondation")),
    ("neviim", "Prophètes", Some("ceux qui portent le davar")),
    ("ketouvim", "Écrits", None),
    (
        "nistarot",
        "Écrits apocalyptiques",
        Some("les Réalités voilées"),
    ),
    (
        "berit-hadashah",
        "Nouvelle Alliance",
        Some("la berith renouvelée"),
    ),
    (
        "besorot",
        "Évangiles",
        Some("les besorot — annonce royale d'un acte accompli"),
    ),
];

/// La glose d'une section, si elle en a une.
pub fn section(id: &str) -> Option<(&'static str, Option<&'static str>)> {
    SECTIONS
        .iter()
        .find(|(k, ..)| *k == id)
        .map(|(_, fr, glose)| (*fr, *glose))
}

/// Ce que le nom ONT d'un livre veut dire.
///
/// Seuls les livres dont le nom **dit quelque chose** en ont une. *Marqus* n'a
/// pas de sens à rendre — c'est un nom d'homme, et son pont vers « Marc »
/// suffit. *Machazeh Yohanan*, lui, nomme une modalité de vision que le mot
/// « Apocalypse » ne porte pas.
pub const GLOSES: [(&str, &str); 24] = [
    ("bereshit-ha-yohanan", "le Bereshit de Yohanan"),
    ("gevurot-ha-neviim", "les gevurot de YHWH par ses neviim"),
    ("el-ha-romiyim", "aux Romiyim"),
    ("el-ha-qorintiyim-alef", "aux Qorintiyim, première"),
    ("el-ha-qorintiyim-bet", "aux Qorintiyim, seconde"),
    ("el-ha-galatiyim", "aux Galatiyim"),
    ("el-ha-efesiyim", "aux Efesiyim"),
    ("el-ha-filipiyim", "aux Filipiyim"),
    ("el-ha-qolossiyim", "aux Qolossiyim"),
    ("el-ha-tessaloniqiyim-alef", "aux Tessaloniqiyim, première"),
    ("el-ha-tessaloniqiyim-bet", "aux Tessaloniqiyim, seconde"),
    ("el-filemon", "à Filemon"),
    ("igeret-yaaqov", "igeret de Ya'aqov"),
    ("igeret-kefa-alef", "première igeret de Kefa"),
    ("igeret-kefa-bet", "seconde igeret de Kefa"),
    ("igeret-ha-ivrim", "igeret aux Ivrim"),
    ("el-timotiyos-alef", "à Timotiyos, première"),
    ("el-timotiyos-bet", "à Timotiyos, seconde"),
    ("el-titos", "à Titos"),
    ("igeret-yohanan-alef", "première igeret de Yohanan"),
    ("igeret-yohanan-bet", "deuxième igeret de Yohanan"),
    ("igeret-yohanan-gimel", "troisième igeret de Yohanan"),
    ("igeret-yehudah", "igeret de Yehudah"),
    // Celui qui porte le plus. « Apocalypse » est le pont — c'est le mot que
    // le lecteur cherche — mais il traduit *apokalypsis*, que le §2 écarte
    // explicitement : « ne pas utiliser *giluy*, calque du grec ». Le nom ONT
    // dit autre chose, et la glose est le seul endroit où il peut le dire.
    (
        "machazeh-yohanan",
        "le machazeh de Yohanan — la vision intérieure",
    ),
];

/// La glose d'un livre, s'il en a une.
pub fn glose(id: &str) -> Option<&'static str> {
    GLOSES.iter().find(|(k, _)| *k == id).map(|(_, g)| *g)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn les_noms_declares_l_emportent() {
        assert_eq!(display_name("neviim"), "Nevi'im");
        assert_eq!(display_name("trei-asar"), "Trei Asar");
    }

    #[test]
    fn le_reste_se_met_en_capitales() {
        assert_eq!(display_name("bereshit"), "Bereshit");
        assert_eq!(display_name("sefar-gibbaraya"), "Sefar Gibbaraya");
    }
}
