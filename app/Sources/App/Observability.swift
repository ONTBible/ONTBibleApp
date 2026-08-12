import Foundation
import ONTKit
import Sentry

/// Le branchement de Sentry.
///
/// Vit dans la cible d'app, et nulle part ailleurs : c'est le seul endroit
/// qui a le droit de connaître Sentry. Les modules passent par le port
/// `Reporter` d'`ONTKit`.
///
/// ## Ce que cette configuration refuse, et pourquoi
///
/// Les réglages recommandés par défaut pour une app iOS — capture d'écran à
/// l'erreur, hiérarchie des vues, `sendDefaultPii`, session replay — sont de
/// bons réglages **pour une app ordinaire**. Ici ils seraient une fuite de
/// données de catégorie particulière.
///
/// Une capture d'écran prise au moment d'une erreur montrerait le passage en
/// cours de lecture et les versets surlignés. Un session replay montrerait
/// tout le parcours de lecture. Ces images révèlent des **convictions
/// religieuses** — article 9 du RGPD, traitement interdit sauf consentement
/// explicite. Aucun consentement n'a été demandé pour de la télémétrie, et
/// on n'en demandera pas : on ne collecte simplement pas.
///
/// Ce qu'on garde : la pile d'appels, le type d'erreur, la version, l'appareil.
/// De quoi corriger un bug, sans rien apprendre du lecteur.
enum Observability {
    /// Démarre Sentry. Ne fait rien si le DSN manque, ou sous XCTest.
    static func start() {
        guard !isRunningUnderXCTest else { return }

        let dsn = Bundle.main.object(forInfoDictionaryKey: "ONTSentryDSN") as? String ?? ""
        guard !dsn.isEmpty, !dsn.contains("à-remplir") else {
            #if DEBUG
            print("[Observability] Sentry désactivé — DSN absent.")
            #endif
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = isDebugBuild ? "debug" : "release"
            options.debug = isDebugBuild
            options.attachStacktrace = true

            // ── Ce qu'on capture ─────────────────────────────────────────

            // Une terminaison par le watchdog ne produit aucun signal : ni
            // crash, ni exception. Elle ne se détecte qu'au lancement
            // suivant, par élimination. Sans ça, une app qui « se ferme
            // toute seule » ne laisse aucune trace.
            options.enableWatchdogTerminationTracking = true

            // Un blocage assez long pour être tué commence par un blocage
            // plus court. Le capturer donne la pile AVANT la mort — ce que
            // la terminaison seule ne donne jamais.
            options.enableAppHangTracking = true
            options.appHangTimeoutInterval = 2

            options.enableAutoPerformanceTracing = true
            options.tracesSampleRate = isDebugBuild ? 1.0 : 0.2

            // ── Ce qu'on refuse ──────────────────────────────────────────

            // Une capture d'écran à l'erreur montrerait le passage lu et les
            // surlignages. C'est précisément la donnée que l'app s'engage à
            // ne pas faire sortir sans consentement.
            options.attachScreenshot = false
            options.attachViewHierarchy = false

            // Pas d'adresse IP ni d'identifiants d'utilisateur.
            options.sendDefaultPii = false

            // Pas de session replay : un film du parcours de lecture est la
            // forme la plus complète de la donnée qu'on protège.
            options.sessionReplay.sessionSampleRate = 0
            options.sessionReplay.onErrorSampleRate = 0

            // Pas de span par requête réseau. Le traçage distribué vers la
            // Lambda n'en dépend pas : l'en-tête `sentry-trace` est injecté
            // indépendamment de ce drapeau.
            options.enableNetworkTracking = false
            options.enableCaptureFailedRequests = false

            // Les en-têtes de traçage ne partent que vers notre backend —
            // jamais vers Apple, Google ou GitHub pendant une connexion.
            options.tracePropagationTargets = ["execute-api.eu-west-3.amazonaws.com"]

            // ── Dernier filet ────────────────────────────────────────────

            // Même en refusant tout ce qui précède, un message d'erreur peut
            // charrier un chemin de fichier (donc l'UUID du conteneur) ou le
            // texte d'une note. On expurge avant l'envoi.
            options.beforeSend = { event in
                if let formatted = event.message?.formatted {
                    event.message = SentryMessage(formatted: redact(formatted))
                }
                event.exceptions?.forEach { exception in
                    exception.value = exception.value.map(redact)
                }
                event.breadcrumbs?.forEach { crumb in
                    if let message = crumb.message { crumb.message = redact(message) }
                }
                return event
            }
        }
    }

    /// Expurge ce qui ne doit pas sortir de l'appareil.
    ///
    /// Volontairement grossier : sur-expurger une chaîne de diagnostic ne
    /// coûte rien, laisser fuir le titre d'une note en coûte beaucoup.
    static func redact(_ text: String) -> String {
        var out = text

        // Les chemins **absolus** — eux seuls portent l'UUID du conteneur et
        // les noms de fichiers choisis par le lecteur.
        //
        // Un chemin relatif comme `data/corpus.json` est un nom de ressource
        // de notre propre bundle : il ne révèle rien, et c'est souvent la
        // seule information utile du message. L'expurger transformait
        // « ressource introuvable : data/corpus.json » en
        // « ressource introuvable : <chemin> » — un diagnostic sans diagnostic.
        out = out
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { token -> String in
                let value = String(token)
                let absolu = value.contains("/Users/") || value.contains("/var/")
                    || value.contains("/private/") || value.hasPrefix("/")
                    || value.hasPrefix("file://")
                // Un segment de 32 caractères hexadécimaux ou un UUID : c'est
                // un identifiant de conteneur, jamais un nom de ressource.
                let identifiant = value.range(
                    of: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-",
                    options: .regularExpression
                ) != nil
                return absolu || identifiant ? "<chemin>" : value
            }
            .joined(separator: " ")

        // Le texte cité — la forme sous laquelle une note de lecteur ou un
        // extrait de verset se retrouverait dans un message d'erreur.
        //
        // Le critère n'est pas la longueur seule, mais la **prose** : douze
        // caractères ou plus **et au moins une espace**. Une note en contient
        // toujours ; un identifiant de ressource (`data/corpus.json`), un
        // lemme ou une clé, jamais.
        //
        // Sans cette nuance, Sentry recevait `missing(<texte>)` là où le
        // message utile était `missing("data/corpus.json")` — la description
        // Swift d'une énumération met sa valeur associée entre guillemets, et
        // la règle avalait le diagnostic entier.
        out = out.replacingOccurrences(
            of: "[«\"'](?=[^«»\"']{12,}[»\"'])[^«»\"']*\\s[^«»\"']*[»\"']",
            with: "<texte>",
            options: .regularExpression
        )

        return out
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// Sous XCTest, on ne remonte rien : la cible de test est hébergée par
    /// l'app, donc `Bundle.main` porte le vrai DSN — chaque test qui lève
    /// une erreur polluerait le tableau de bord.
    private static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

/// L'implémentation du port `Reporter` d'`ONTKit`.
struct SentryReporter: Reporter {
    func report(_ error: any Error, context: String) {
        SentrySDK.capture(error: error) { scope in
            scope.setTag(value: context, key: "contexte")
        }
    }

    func breadcrumb(_ message: String) {
        let crumb = Breadcrumb(level: .info, category: "app")
        crumb.message = Observability.redact(message)
        SentrySDK.addBreadcrumb(crumb)
    }
}
