//! Ce que la télémétrie n'a pas à voir.
//!
//! Le SDK filtre lui-même les en-têtes qu'il connaît — `Authorization`,
//! `Cookie` — mais un en-tête maison lui est invisible, et une query string
//! d'URL traverse `scrub_pii_from_url` intacte. L'audit du 8 septembre 2026
//! (C02) l'a reproduit : un événement portait `x-secret-diffusion`, un autre
//! le `?code=` d'un retour OAuth.
//!
//! La parade a deux étages, et celui-ci est le second : le premier est de ne
//! plus rien mettre dans un en-tête que le SDK ne filtre pas — le secret de
//! diffusion voyage désormais dans `Authorization: Bearer`. L'expurgation
//! qui suit est la ceinture : si un secret repasse un jour par un chemin
//! non filtré, il meurt ici plutôt que chez Sentry.
//!
//! Limite connue, à lever avec le SDK : `before_send` ne voit que les
//! événements — les **transactions** de `sentry-tower` n'ont pas de crochet
//! en 0.48. Leur URL passe par `scrub_pii_from_url` (identifiants retirés,
//! query gardée) : c'est la raison de l'étage un, qui ne dépend d'aucun
//! crochet.

use sentry::protocol::Event;

/// L'en-tête maison qui a transporté le secret de diffusion. Retiré de tout
/// événement tant que la transition vers `Authorization` n'est pas close.
const EN_TETE_SECRET: &str = "x-secret-diffusion";

/// Expurge un événement avant envoi : l'en-tête du secret et toute query
/// string d'URL — un retour OAuth y transporte son code.
pub fn expurger(mut event: Event<'static>) -> Option<Event<'static>> {
    if let Some(req) = event.request.as_mut() {
        req.headers
            .retain(|nom, _| !nom.eq_ignore_ascii_case(EN_TETE_SECRET));
        req.query_string = None;
        if let Some(url) = req.url.as_mut() {
            url.set_query(None);
        }
    }
    Some(event)
}

#[cfg(test)]
mod tests {
    use super::*;
    use sentry::protocol::Request;

    #[test]
    fn le_secret_et_la_query_meurent_avant_l_envoi() {
        let mut req = Request {
            url: Some(
                "https://api.exemple/auth/github/callback?code=abc&state=x"
                    .parse()
                    .unwrap(),
            ),
            query_string: Some("code=abc&state=x".into()),
            ..Default::default()
        };
        req.headers
            .insert("X-Secret-Diffusion".into(), "s3cret".into());
        req.headers.insert("user-agent".into(), "curl".into());
        let event = Event {
            request: Some(req),
            ..Default::default()
        };

        let sorti = expurger(event).expect("l'événement survit, expurgé");
        let req = sorti.request.expect("la requête survit");
        assert!(
            !req.headers
                .keys()
                .any(|k| k.eq_ignore_ascii_case("x-secret-diffusion")),
            "l'en-tête du secret doit mourir, quelle que soit sa casse"
        );
        assert_eq!(
            req.headers.get("user-agent").map(String::as_str),
            Some("curl")
        );
        assert_eq!(req.query_string, None);
        assert_eq!(
            req.url.unwrap().as_str(),
            "https://api.exemple/auth/github/callback",
            "la query de l'URL doit tomber, le chemin rester"
        );
    }
}
