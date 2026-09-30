//! Ce que voit un navigateur — et ce que voit iOS.
//!
//! ```text
//! GET /.well-known/apple-app-site-association   l'association app ↔ domaine
//! GET /fr/lire/{livre}/{unité}                  la page de repli d'un passage
//! ```
//!
//! Ces deux routes existent pour une seule raison : qu'un passage partagé soit
//! un lien qu'on peut cliquer. Sur un iPhone où l'app est installée, iOS
//! l'ouvre directement — c'est le fichier d'association qui l'y autorise.
//! Partout ailleurs, on rend une page qui montre le renvoi et propose l'app.

use axum::extract::Path;
use axum::http::{header, StatusCode};
use axum::response::{IntoResponse, Response};

/// L'identifiant d'équipe et le bundle, tels qu'Apple les attend.
///
/// Le bundle porte le nom français (`labibleont`) alors que le domaine nomme
/// le projet (`ontbible.com`) : c'est délibéré. Un identifiant d'app est gelé
/// à la première publication, il est invisible du lecteur, et le changer
/// coûterait de refaire toute la configuration Sign in with Apple.
const APP_ID: &str = "N49VNC2G57.com.labibleont.ONT";

/// Le fichier que iOS va chercher pour savoir si l'app a le droit d'ouvrir
/// nos liens.
///
/// Trois pièges, tous silencieux :
///
/// * il doit être servi en `application/json` — un `text/plain` et iOS
///   l'ignore sans rien dire ;
/// * **aucune redirection** n'est tolérée sur ce chemin ;
/// * il n'est lu qu'à l'installation ou à la mise à jour de l'app, et Apple
///   le met en cache via son propre CDN. Le modifier ne se voit pas tout de
///   suite.
///
/// **Trois âges, et aucun ne part jamais.**
///
/// ```text
/// /fr/liseuse/*   la forme d'aujourd'hui   1er octobre 2026
/// /fr/webapp/*    la forme intermédiaire   29 septembre 2026
/// /fr/lire/*      l'originale
/// ```
///
/// Le serveur du site redirige les anciennes vers la neuve, chaîne de requête
/// comprise — mais ==une redirection ne sauve que le navigateur==. Pour qu'un
/// lien ouvre l'**app**, il faut que son chemin soit déclaré ici :
/// ==l'app intercepte sur le chemin déclaré, pas sur sa cible==, et iOS ne suit
/// aucune redirection pour décider.
///
/// **Et la liste ne se raccourcira jamais**, pour une raison qui est chez
/// Apple : ==iOS ne relit ce fichier qu'à l'installation, et Apple le met en
/// cache sur son propre CDN.== Un appareil installé avant un retrait porterait
/// l'ancienne liste pendant des semaines. Retirer un chemin ferait ouvrir ses
/// liens dans le navigateur au lieu de l'app — en silence des deux côtés.
///
/// ## ⚠︎ Cette route n'est plus celle qui sert `ontbible.com`
///
/// **Mesuré le 29 septembre 2026, pas déduit :**
///
/// ```text
/// GET ontbible.com/.well-known/apple-app-site-association   200, via CloudFront
/// GET ontbible.com/llms.txt                                 200  ← le site seul le porte
/// GET ontbible.com/health                                   404  ← ce backend le porte
/// ```
///
/// Le 404 tranche : ==ce backend n'est pas sur ce domaine==. Depuis la bascule
/// des domaines du 13 août, `ontbible.com` est servi par la distribution du
/// site, et c'est **lui** qui rend ce fichier. Cette route date de l'époque où
/// le domaine pointait l'API.
///
/// **Elle est donc tenue d'accord par principe, pas par nécessité.** Le jour
/// où quelqu'un remet l'API sur la racine — ou monte un second domaine —, une
/// copie périmée casserait tous les liens universels sans qu'aucune erreur ne
/// le dise. C'est le genre de panne qu'on met des jours à trouver parce que
/// « le fichier existe et il est juste ».
///
/// ## Le constructeur de liens de l'app ne bascule pas, et c'est réglé
///
/// Ce commentaire portait une consigne d'ordonnancement : faire basculer
/// `Router` sur `/fr/webapp` une fois le fichier du site en ligne. ==Elle est
/// caduque, et c'est la liste ci-dessus qui la périme.==
///
/// `Router.swift:482` construit `fr/lire/<livre>/<unité>`, et il peut y rester
/// indéfiniment : le chemin est déclaré pour toujours, le site le redirige vers
/// la forme du jour, et l'app l'intercepte avant. Basculer ne gagnerait rien et
/// périmerait les liens déjà partagés en circulation.
///
/// ==Une consigne d'ordonnancement n'a de sens que tant que l'un des deux états
/// est transitoire.== Ici les trois le sont devenus permanents, et la question
/// de l'ordre a disparu avec.
///
/// J'avais écrit ici que la dette attendait une revue Apple —
/// `deployer-backend.yml` se déclenchant sur `app-store`. C'était juste sur le
/// chemin du déploiement et faux sur la prémisse : ==ce fichier ne passe pas
/// par ce déploiement.== La session du site l'a mesuré et corrigé.
///
/// Le reste du domaine — page d'accueil, mentions — doit rester consultable
/// dans un navigateur, d'où l'absence de `{"/": "*"}`.
pub async fn apple_app_site_association() -> Response {
    let corps = format!(
        r#"{{"applinks":{{"details":[{{"appIDs":["{APP_ID}"],"components":[{{"/":"/fr/liseuse/*"}},{{"/":"/fr/webapp/*"}},{{"/":"/fr/lire/*"}}]}}]}}}}"#
    );
    (
        StatusCode::OK,
        [(header::CONTENT_TYPE, "application/json")],
        corps,
    )
        .into_response()
}

/// La page de repli d'un passage.
///
/// Elle ne montre pas le texte. Le corpus vit dans le bundle de l'app, pas
/// dans la Lambda, et l'y dupliquer créerait une seconde source de vérité que
/// personne ne penserait à mettre à jour. Elle montre le renvoi, dit d'où il
/// vient, et propose l'app — ce qui suffit à ce qu'on attend d'un lien.
///
/// Les balises Open Graph, elles, ne sont pas décoratives : ce sont elles qui
/// produisent l'aperçu quand le lien est collé dans une conversation.
pub async fn passage(Path((livre, unite)): Path<(String, String)>) -> Response {
    let renvoi = format!("{} · {}", echapper(&livre), echapper(&unite));
    let html = format!(
        r#"<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{renvoi} — La Bible ONT</title>
<meta property="og:site_name" content="La Bible ONT">
<meta property="og:title" content="{renvoi}">
<meta property="og:description" content="Un passage de la Bible ONT — Ontologie Nouvelle Traduction.">
<meta property="og:type" content="article">
<meta name="twitter:card" content="summary">
<style>
:root {{ color-scheme: light dark; }}
body {{
  margin: 0; min-height: 100vh;
  display: grid; place-items: center;
  background: #FAF5EB; color: #29211C;
  font: 17px/1.5 ui-serif, Georgia, serif;
  padding: 32px;
}}
@media (prefers-color-scheme: dark) {{
  body {{ background: #171417; color: #E0DBD4; }}
}}
main {{ max-width: 34rem; text-align: center; }}
h1 {{ font-size: 1.6rem; font-weight: 500; margin: 0 0 8px; }}
hr {{ border: 0; border-top: 2px solid #CDBE83; margin: 28px auto; width: 4rem; }}
p {{ opacity: .75; }}
a {{ color: #A6874F; }}
</style>
</head>
<body>
<main>
  <h1>{renvoi}</h1>
  <hr>
  <p>Ce passage se lit dans <strong>La Bible ONT</strong>, une restitution
     française du corpus hébreu fondée sur l'ontologie fonctionnelle.</p>
  <p>Ouvrez ce lien depuis un iPhone où l'app est installée pour aller
     directement au passage.</p>
</main>
</body>
</html>"#
    );
    (
        StatusCode::OK,
        [(header::CONTENT_TYPE, "text/html; charset=utf-8")],
        html,
    )
        .into_response()
}

/// Échappe ce qui vient de l'URL avant de le remettre dans du HTML.
///
/// Le livre et l'unité arrivent du chemin, donc de l'extérieur. Les recoller
/// tels quels dans la page ouvrirait une injection de script à qui forge un
/// lien — et ce lien serait servi depuis notre domaine, donc de confiance.
fn echapper(brut: &str) -> String {
    brut.chars()
        .flat_map(|c| match c {
            '&' => "&amp;".chars().collect::<Vec<_>>(),
            '<' => "&lt;".chars().collect(),
            '>' => "&gt;".chars().collect(),
            '"' => "&quot;".chars().collect(),
            '\'' => "&#39;".chars().collect(),
            autre => vec![autre],
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn echappe_les_chevrons() {
        assert_eq!(
            echapper("<script>alert('x')</script>"),
            "&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt;"
        );
    }

    #[test]
    fn laisse_un_identifiant_ordinaire_intact() {
        assert_eq!(echapper("bereshit-1"), "bereshit-1");
    }

    #[tokio::test]
    async fn l_association_est_du_json() {
        let reponse = apple_app_site_association().await;
        let type_contenu = reponse.headers().get(header::CONTENT_TYPE).unwrap();
        // Un `text/plain` et iOS ignore le fichier sans rien dire.
        assert_eq!(type_contenu, "application/json");
    }

    #[tokio::test]
    async fn l_association_nomme_l_app_et_le_chemin() {
        let reponse = apple_app_site_association().await;
        let corps = axum::body::to_bytes(reponse.into_body(), 4096)
            .await
            .unwrap();
        let texte = String::from_utf8(corps.to_vec()).unwrap();
        assert!(texte.contains(APP_ID));
        // **Les trois âges, chacun nommément.**
        //
        // Vérifier seulement le plus neuf laisserait passer le retrait d'un
        // ancien — c'est-à-dire la seule régression qui casse des liens déjà
        // partagés, et elle est silencieuse des deux côtés : le lien s'ouvre,
        // simplement dans le navigateur.
        //
        // Nommer les trois plutôt que compter : un test qui compterait « trois
        // composants » resterait vert si l'on en remplaçait un par un autre.
        for chemin in ["/fr/liseuse/*", "/fr/webapp/*", "/fr/lire/*"] {
            assert!(
                texte.contains(chemin),
                "le chemin {chemin} a disparu de l'association : {texte}"
            );
        }
        // Et rien d'autre : ouvrir tout le domaine empêcherait de consulter
        // une page dans un navigateur.
        assert!(!texte.contains(r#""/":"*""#));
    }
}
