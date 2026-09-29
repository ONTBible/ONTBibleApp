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
    /// Démarre Sentry. Ne fait rien si le DSN manque, sous XCTest, ou dans un
    /// build de développement.
    static func start() {
        guard doitRemonter(
            debug: isDebugBuild,
            sousXCTest: isRunningUnderXCTest,
            arguments: ProcessInfo.processInfo.arguments
        ) else {
            #if DEBUG
            print("[Observability] Sentry muet — build de développement.")
            print("[Observability] `-sentry-en-debug` le rallume pour ce lancement.")
            #endif
            return
        }

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
            options.beforeSend = { expurger($0) }
        }
    }

    /// Faut-il remonter quoi que ce soit depuis ce lancement ?
    ///
    /// Pure, et prenant son monde en paramètre : c'est ce qui la rend
    /// éprouvable. `start()` lui passe l'environnement réel.
    ///
    /// ## Pourquoi un build Debug se tait
    ///
    /// Le 29 septembre 2026, `ONT-IOS-15` — *App Hang Fully Blocked, 12,2 à
    /// 13,0 secondes* — est arrivé par courriel avec `environment: debug`. Il
    /// ne venait d'aucun lecteur : d'un build posé sur l'appareil de l'auteur
    /// par `scripts/lancer-sur-*`.
    ///
    /// Trois mesures expliquent pourquoi ce n'est pas un accident isolé, et
    /// les trois viennent du SDK lu, pas supposé (`sentry-cocoa` 9.25.0) :
    ///
    /// - `SentryDependencyContainer.swift:568` — le suiveur de blocages **V2
    ///   est imposé** sur iOS ; aucune option ne le règle ;
    /// - `SentryWatchdogTerminationLogic.swift:55` — `isSimulatorBuild`
    ///   n'écarte **que** les terminaisons watchdog. Les blocages, eux, ne
    ///   sont écartés ni sur simulateur, ni sous débogueur : le mot
    ///   `IsBeingTraced` n'apparaît nulle part dans les sources du SDK ;
    /// - un build Debug n'engendre pas de dSYM (`scripts/televerser-symboles.sh`
    ///   s'arrête ligne 26), donc sa pile arrive en `?` — l'événement dit
    ///   qu'il y a eu un blocage, et rien de plus.
    ///
    /// Une pause du débogueur, un point d'arrêt, ou simplement un premier
    /// chargement non optimisé produisent donc l'alerte exacte qu'on vient de
    /// recevoir — illisible, et mêlée à celles des lecteurs.
    ///
    /// C'est la raison déjà écrite pour XCTest un cran plus bas — *« chaque
    /// test qui lève une erreur polluerait le tableau de bord »* — et elle
    /// valait pour Debug depuis le début. Elle n'y avait simplement pas été
    /// appliquée.
    ///
    /// ## Pourquoi une porte, et pas une extinction sèche
    ///
    /// `Composition.init` fait échouer le chargement du corpus pour de bon
    /// sous `-corpus-absent`, et son commentaire dit pourquoi : *« c'est ainsi
    /// qu'on vérifie que la chaîne de remontée fonctionne de bout en bout,
    /// sans fabriquer un faux événement qui contournerait le vrai chemin »*.
    ///
    /// Cet argument n'existe **qu'en Debug**. Éteindre Debug sans exception
    /// aurait donc rendu ce dispositif inerte — en silence, et sans que rien
    /// échoue : le lancement se serait déroulé normalement, l'erreur aurait
    /// bien été levée, et le tableau de bord serait resté vide. On aurait
    /// conclu que la chaîne est rompue, ou pire, qu'elle tient.
    ///
    /// > Un contrôle qui ne peut plus rougir ne mesure plus rien.
    ///
    /// D'où deux portes : `-corpus-absent`, qui rallume la remontée parce
    /// qu'il vient précisément l'éprouver, et `-sentry-en-debug`, pour
    /// regarder un vrai blocage sur l'appareil quand on le cherche.
    static func doitRemonter(
        debug: Bool,
        sousXCTest: Bool,
        arguments: [String]
    ) -> Bool {
        if sousXCTest { return false }
        guard debug else { return true }
        return arguments.contains { portesDeDebug.contains($0) }
    }

    /// Les deux arguments de lancement qui rouvrent la remontée en Debug.
    ///
    /// Volontairement **privée** : l'épreuve écrit ces chaînes à la main. Une
    /// épreuve qui lirait cette constante mesurerait la constante contre
    /// elle-même, et resterait verte si on la vidait.
    private static let portesDeDebug: Set<String> = [
        "-corpus-absent",
        "-sentry-en-debug",
    ]

    /// Expurge **l'enveloppe entière**, et non trois champs nommés.
    ///
    /// ## Le défaut, et pourquoi il ne se voyait pas
    ///
    /// Le premier jet expurgeait `event.message`, `exception.value` et
    /// `crumb.message`. Les trois sont ceux qu'on écrit soi-même — donc les
    /// trois qu'on pense à nommer, et les trois qui étaient déjà les moins
    /// exposés.
    ///
    /// Ce qui part réellement en porte bien d'autres, et ce sont **ceux que le
    /// SDK remplit tout seul** :
    ///
    /// - `crumb.data` — le SDK y range les URL réseau, les noms d'écran, les
    ///   requêtes ; c'est le champ le plus chargé de l'enveloppe, et il n'était
    ///   pas touché ;
    /// - `event.extra` et `event.tags` — tout ce qu'un appelant y attache ;
    /// - `exception.type` — un type Swift peut porter un identifiant d'unité ;
    /// - `event.transaction` et `event.fingerprint` — un nom d'écran composé
    ///   avec le titre d'une unité y arrive tel quel.
    ///
    /// Les épreuves ne l'ont pas vu, et elles ne pouvaient pas : elles
    /// nourrissaient `redact` directement. Elles mesuraient donc **la qualité
    /// de l'expurgation**, pas **son périmètre** — un instrument exact qui
    /// répond à une autre question que celle qu'on pose. La question est « que
    /// contient l'enveloppe qui part ».
    ///
    /// ## Le principe qui remplace la liste
    ///
    /// Tout ce qui est une chaîne, où qu'elle soit, passe par `redact`. La
    /// descente est récursive parce que `extra` et `data` sont des sacs à
    /// contenu libre : un dictionnaire dans un tableau dans un dictionnaire est
    /// une forme que le SDK produit, pas une hypothèse.
    ///
    /// Sur-expurger une chaîne de diagnostic ne coûte rien. Laisser sortir le
    /// titre d'une note en coûte beaucoup — et un champ oublié ne se voit
    /// jamais depuis l'appareil.
    static func expurger(_ event: Event) -> Event {
        if let formatted = event.message?.formatted {
            event.message = SentryMessage(formatted: redact(formatted))
        }
        event.exceptions?.forEach { exception in
            exception.value = exception.value.map(redact)
            // `type` n'est pas optionnel ici, au contraire de `value`. Un type
            // Swift peut porter un identifiant d'unité : il sort comme le reste.
            exception.type = exception.type.map(redact) ?? exception.type
        }
        event.breadcrumbs?.forEach { crumb in
            if let message = crumb.message { crumb.message = redact(message) }
            if let data = crumb.data { crumb.data = expurgerLeSac(data) }
        }
        if let extra = event.extra { event.extra = expurgerLeSac(extra) }
        if let tags = event.tags { event.tags = tags.mapValues(redact) }
        event.transaction = event.transaction.map(redact)
        event.fingerprint = event.fingerprint.map { $0.map(redact) }
        return event
    }

    /// Descend dans un sac à contenu libre et expurge chaque chaîne.
    ///
    /// **Les clés ne sont pas touchées.** Elles nomment le champ, elles ne le
    /// contiennent pas — et une clé expurgée rendrait le rapport illisible sans
    /// rien protéger de plus. Ce qui vient de l'appareil est toujours du côté
    /// de la valeur.
    private static func expurgerLeSac(_ sac: [String: Any]) -> [String: Any] {
        sac.mapValues(expurgerLaValeur)
    }

    private static func expurgerLaValeur(_ valeur: Any) -> Any {
        switch valeur {
        case let texte as String: redact(texte)
        case let sac as [String: Any]: expurgerLeSac(sac)
        case let liste as [Any]: liste.map(expurgerLaValeur)
        // Un nombre, un booléen, une date : rien à expurger, et les convertir
        // en chaîne pour les faire passer par `redact` les abîmerait.
        default: valeur
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
        out = expurgerLesCitations(out)

        return out
    }

    /// Les citations, décidées **une par une**.
    ///
    /// ## Pourquoi ce n'est plus une seule expression
    ///
    /// L'ancienne écriture faisait tout d'un coup — trouver, juger et remplacer
    /// dans un même motif — et deux défauts s'y cachaient, tous deux trouvés
    /// par la session Android en la portant :
    ///
    /// **L'apostrophe était un délimiteur.** `[«\"']` la comptait comme un
    /// guillemet fermant, alors qu'en français elle est dans un mot sur cinq.
    /// Sur `« ce passage m'a bouleversé hier soir »`, la citation était donc
    /// close par le `'` de `m'`, et le résultat valait :
    ///
    /// ```text
    /// <texte>a bouleversé hier soir »
    /// ```
    ///
    /// Le début partait, **la fin passait en clair** — et c'est la moitié qui
    /// porte le propos. Ce n'est pas « rien n'est filtré », c'est pire : ce qui
    /// reste est ce qu'on voulait cacher, sous une apparence de filtrage.
    ///
    /// **Et l'espace de typographie comptait comme de la prose.** Le critère
    /// « douze signes et une espace » était satisfait par les espaces
    /// insécables dont le français entoure `« … »`. Une clé qui ne révèle rien
    /// — `« bereshit-1-verset-30 »` — se faisait donc expurger, et le
    /// diagnostic disparaissait avec le risque. C'est le défaut que le
    /// commentaire ci-dessus dit avoir déjà corrigé une fois pour
    /// `data/corpus.json` : il était revenu par une autre porte.
    ///
    /// Séparer *trouver* de *juger* rend les deux lisibles, et éprouvables.
    private static func expurgerLesCitations(_ texte: String) -> String {
        guard let citations = try? NSRegularExpression(pattern: "[«\"]([^«»\"]*)[»\"]")
        else { return texte }

        let ns = texte as NSString
        var sortie = ""
        var curseur = 0
        for trouvee in citations.matches(
            in: texte, range: NSRange(location: 0, length: ns.length)
        ) {
            sortie += ns.substring(
                with: NSRange(location: curseur, length: trouvee.range.location - curseur))
            let interieur = ns.substring(with: trouvee.range(at: 1))
            sortie += estDeLaProse(interieur) ? "<texte>" : ns.substring(with: trouvee.range)
            curseur = trouvee.range.location + trouvee.range.length
        }
        sortie += ns.substring(from: curseur)
        return sortie
    }

    /// Douze signes et une espace **entre deux signes**.
    ///
    /// Le contenu est d'abord débarrassé de ce qui l'entoure : les espaces
    /// insécables de la typographie française appartiennent aux guillemets, pas
    /// à la citation. Et l'espace exigée doit séparer deux caractères — une
    /// espace de bordure ne fait pas une phrase.
    private static func estDeLaProse(_ interieur: String) -> Bool {
        let net = interieur.trimmingCharacters(in: .whitespacesAndNewlines)
        return net.count >= 12
            && net.range(of: "\\S\\s\\S", options: .regularExpression) != nil
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
