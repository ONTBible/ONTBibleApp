//! Point d'entrée.
//!
//! Le même binaire tourne en Lambda et en local : `lambda_http` prend la main
//! quand `AWS_LAMBDA_FUNCTION_NAME` est présent, sinon on sert en HTTP sur le
//! port 3000 — ce qui permet de développer sans déployer.

use std::sync::Arc;

use ont_backend::application::App;
use ont_backend::domain::diffusion::Environnement;
use ont_backend::domain::ports::{AppareilRepository, Notificateur, SystemClock};
use ont_backend::domain::token::TokenIssuer;
use ont_backend::infrastructure::apns::Apns;
use ont_backend::infrastructure::config::Config;
use ont_backend::infrastructure::dynamo::Dynamo;
use ont_backend::infrastructure::providers::HttpIdentityProvider;
use ont_backend::interface::router;

/// Vide la file d'envoi de Sentry avant que la réponse ne parte.
///
/// **Sans ça, rien n'arrive jamais.** Sentry envoie ses événements depuis un
/// fil d'arrière-plan ; Lambda gèle l'environnement d'exécution dès que la
/// réponse est rendue, et ce fil ne reprend plus la main. L'événement reste
/// dans la file, gelé, jusqu'à ce qu'un prochain appel dégèle la machine —
/// ou jamais, si l'environnement est recyclé.
///
/// Le vidage est borné à deux secondes : mieux vaut perdre un événement
/// qu'ajouter deux secondes à la latence d'un lecteur.
async fn vider_sentry(
    request: axum::extract::Request,
    next: axum::middleware::Next,
) -> axum::response::Response {
    let response = next.run(request).await;

    // Le client est capturé ici, sur le fil de la requête : `Hub::current()`
    // est local au fil, et ne rendrait rien depuis le fil bloquant.
    if let Some(client) = sentry::Hub::current().client() {
        let _ = tokio::task::spawn_blocking(move || {
            client.flush(Some(std::time::Duration::from_secs(2)));
        })
        .await;
    }
    response
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    // `sentry_tracing` transforme les événements `tracing::error!` en
    // événements Sentry. Sans cette couche, les couches HTTP de sentry-tower
    // créent bien des transactions, mais **aucune erreur ne remonte** : nos
    // `tracing::error!` finiraient uniquement dans CloudWatch.
    use tracing_subscriber::layer::SubscriberExt;
    use tracing_subscriber::util::SubscriberInitExt;

    let format = tracing_subscriber::fmt::layer()
        .json()
        // CloudWatch horodate déjà chaque ligne ; le répéter double le volume
        // ingéré, qui est facturé au gigaoctet.
        .without_time();

    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,ont_backend=debug".into()),
        )
        .with(format)
        .with(sentry_tracing::layer())
        .init();

    let config = Config::from_env().map_err(|_| "configuration incomplète")?;

    // Sentry avant tout le reste : une panique pendant la construction du
    // client AWS doit déjà être remontée.
    //
    // Le garde doit vivre jusqu'à la fin du processus — le lâcher vide la
    // file d'envoi, et les événements en attente sont perdus.
    let _sentry = (!config.sentry_dsn.is_empty()).then(|| {
        sentry::init((
            config.sentry_dsn.clone(),
            sentry::ClientOptions {
                release: sentry::release_name!(),
                environment: Some("production".into()),
                traces_sample_rate: 0.2,
                // Aucune donnée personnelle par défaut : ni adresse IP, ni
                // en-tête d'autorisation. Ce backend transporte des
                // annotations qui révèlent des convictions religieuses
                // (RGPD, article 9) — la télémétrie n'a pas à les voir.
                send_default_pii: false,
                ..Default::default()
            },
        ))
    });

    let aws = aws_config::load_defaults(aws_config::BehaviorVersion::latest()).await;
    let dynamo = Arc::new(Dynamo::new(
        aws_sdk_dynamodb::Client::new(&aws),
        config.table.clone(),
    ));

    // La diffusion s'allume seulement si la clé est là. Sans elle, les routes
    // d'appareils répondent `503` et tout le reste fonctionne : ne pas savoir
    // notifier n'est pas une raison d'empêcher de lire.
    let notificateur: Option<Arc<dyn Notificateur>> = config.apns.as_ref().map(|a| {
        let mut cles = std::collections::HashMap::new();
        cles.insert(
            Environnement::Production,
            (a.key_id.clone(), a.private_key.clone().into_bytes()),
        );
        // La sandbox n'est pas exigée : sans elle, les builds de debug ne sont
        // pas joints, et c'est un état acceptable en développement. On le dit
        // au démarrage plutôt que de le laisser découvrir.
        match (&a.sandbox_key_id, &a.sandbox_private_key) {
            (Some(id), Some(pem)) => {
                cles.insert(
                    Environnement::Sandbox,
                    (id.clone(), pem.clone().into_bytes()),
                );
            }
            _ => tracing::info!(
                "aucune clé APNs de sandbox — les builds de debug ne seront pas joints"
            ),
        }
        Arc::new(Apns::new(a.team_id.clone(), cles, a.topic.clone())) as Arc<dyn Notificateur>
    });

    let app = App {
        identity: Arc::new(HttpIdentityProvider::new(config.clone())),
        users: dynamo.clone(),
        sync: dynamo.clone(),
        appareils: notificateur
            .as_ref()
            .map(|_| dynamo.clone() as Arc<dyn AppareilRepository>),
        notificateur,
        secret_diffusion: config.secret_diffusion.clone(),
        tokens: TokenIssuer::new(&config.jwt_secret),
        clock: Arc::new(SystemClock),
        // Dérivée de la configuration, jamais écrite en dur : une capacité
        // disparaît de la liste dès que ce qui la sert disparaît.
        capacites: ont_backend::domain::capacites::offertes(&config),
    };

    // Les couches Sentry enveloppent chaque requête : une transaction par
    // appel, et un scope isolé pour que le contexte d'une requête ne fuite
    // pas dans la suivante.
    //
    // La couche de vidage vient **en dernier**, donc s'exécute en premier à
    // l'aller et en dernier au retour : elle doit voir la réponse une fois
    // que les couches Sentry ont fini d'enregistrer.
    let router = router(app)
        .layer(sentry_tower::SentryHttpLayer::new().enable_transaction())
        .layer(sentry_tower::NewSentryLayer::new_from_top())
        .layer(axum::middleware::from_fn(vider_sentry));

    if std::env::var("AWS_LAMBDA_FUNCTION_NAME").is_ok() {
        lambda_http::run(router).await?;
    } else {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:3000").await?;
        tracing::info!("http://127.0.0.1:3000");
        axum::serve(listener, router).await?;
    }
    Ok(())
}
