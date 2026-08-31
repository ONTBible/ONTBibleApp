#if os(iOS)
    import BackgroundTasks
#endif
import Foundation
import ONTData
import os

/// La mise à jour du corpus **sans que l'app soit ouverte**.
///
/// ## Le problème que ça résout
///
/// [`CorpusUpdater`] ne travaille qu'au lancement. Une correction publiée un
/// mardi n'atteint donc un lecteur que le jour où il rouvre l'app — et
/// quelqu'un qui lit tous les soirs à la même heure recevrait toujours le texte
/// de la veille au moment précis où il lit.
///
/// Une tâche d'arrière-plan renverse ça : iOS réveille l'app tout seul, met le
/// corpus à jour, et l'endort. Le lecteur ouvre une app déjà à jour.
///
/// ## Ce qu'iOS garantit, et ce qu'il ne garantit pas
///
/// Il ne garantit **pas** d'horaire. `earliestBeginDate` est un plancher, pas un
/// rendez-vous : le système décide seul, d'après l'habitude d'usage, la
/// batterie, le réseau. Quelqu'un qui ouvre l'app chaque soir sera rafraîchi
/// chaque jour ; quelqu'un qui ne l'ouvre jamais ne le sera presque pas.
///
/// C'est acceptable, et c'est même juste : on ne dépense la batterie de
/// personne pour un texte qu'il ne lit pas. Ce que ça ne couvre pas — prévenir
/// quelqu'un **maintenant** qu'un livre vient de paraître — demande une
/// notification distante, donc APNs, donc un serveur qui pousse.
///
/// ## Une seule tâche, replanifiée à chaque exécution
///
/// Une tâche d'arrière-plan ne se répète pas toute seule : elle s'exécute une
/// fois et disparaît. La replanifier **en premier**, avant tout travail, est ce
/// qui fait la différence entre un rafraîchissement périodique et un
/// rafraîchissement unique — si l'app est tuée pendant le travail, la prochaine
/// est déjà inscrite.
enum CorpusRefresh {
    /// L'identifiant déclaré dans `Info.plist`. Les deux doivent coïncider au
    /// caractère près : iOS refuse silencieusement d'enregistrer une tâche dont
    /// l'identifiant n'y figure pas, et rien ne le signale au lancement.
    static let identifier = "com.labibleont.ONT.corpus"

    /// Douze heures. Deux fenêtres par jour valent mieux qu'une : iOS en
    /// refusera la plupart, et laisser deux occasions double les chances qu'il
    /// en accorde une.
    private static let interval: TimeInterval = 12 * 60 * 60

    private static let log = Logger(subsystem: "com.labibleont.ONT", category: "corpus")
    // MARK: - La mise à jour de fond, propre à iOS
    //
    // **Le Mac n'a pas de `BGTaskScheduler`, et n'en a pas besoin.** Ce
    // mécanisme existe parce qu'un téléphone dort : il faut demander au
    // système une fenêtre d'exécution et espérer qu'il l'accorde. Une machine
    // de bureau est allumée, et la mise à jour à l'ouverture suffit.
    //
    // Ce n'est donc pas un manque à combler mais une contrainte qui disparaît.
    #if os(iOS)

    /// À appeler **au lancement**, avant que l'app ne finisse de démarrer.
    ///
    /// `register` doit avoir été appelé avant la fin de
    /// `application(_:didFinishLaunchingWithOptions:)` — sinon iOS lève une
    /// exception la première fois qu'il tente de lancer la tâche, des heures
    /// plus tard, dans un processus que personne ne regarde.
    static func register(onUpdate: @escaping @Sendable () -> Void) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: nil
        ) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            handle(task, onUpdate: onUpdate)
        }
    }

    /// Inscrit la prochaine occasion.
    static func schedule() {
        let requete = BGAppRefreshTaskRequest(identifier: identifier)
        requete.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        do {
            try BGTaskScheduler.shared.submit(requete)
        } catch {
            // Refus attendus et sans gravité : rafraîchissement désactivé dans
            // les réglages, mode économie d'énergie, simulateur. L'app continue
            // de se mettre à jour au lancement — on perd la commodité, pas la
            // fonction.
            log.debug("tâche de corpus non planifiée : \(error.localizedDescription)")
        }
    }

    /// La tâche, portée jusqu'à la fermeture d'arrière-plan.
    ///
    /// `@unchecked Sendable` n'est pas une échappatoire posée pour faire taire
    /// le compilateur : c'est la formulation exacte de ce qu'iOS garantit et
    /// qu'aucun type ne peut exprimer — une seule file, une seule tâche vivante
    /// par identifiant, plus aucun accès après `setTaskCompleted`.
    private struct Confiee: @unchecked Sendable {
        let tache: BGAppRefreshTask
    }

    private static func handle(_ task: BGAppRefreshTask, onUpdate: @escaping @Sendable () -> Void) {
        // **En premier**, avant tout travail. Une tâche ne se répète pas seule ;
        // si l'app est tuée pendant le téléchargement, celle-ci est déjà
        // inscrite et la chaîne ne se rompt pas.
        schedule()

        // `BGAppRefreshTask` n'est pas `Sendable`, et la concurrence stricte
        // refuse à juste titre de le faire traverser vers une autre isolation.
        // La garantie qui rend ce passage sûr n'est pas dans le type, elle est
        // dans le système : iOS livre la tâche sur une seule file, ne la touche
        // plus après `setTaskCompleted`, et n'en donne jamais deux du même
        // identifiant en même temps.
        //
        // Un `nonisolated(unsafe)` sur la variable locale ne suffit pas, et le
        // compilateur publié le refuse : la fermeture de `Task` est un paramètre
        // `sending`, et ce qui décide de sa sûreté est ce qu'elle **capture**.
        // L'affirmation doit donc porter sur le type capturé, pas sur la
        // variable — d'où cette boîte.
        let boite = Confiee(tache: task)

        let travail = Task {
            let neufs = (try? await CorpusUpdater().synchroniser()) ?? 0
            log.info("corpus rafraîchi en arrière-plan : \(neufs) fichiers")
            if neufs > 0 { onUpdate() }
            // `true` même quand rien n'a changé : la tâche a fait ce qu'on lui
            // demandait. Rendre `false` apprendrait à iOS que cette app échoue,
            // et il lui accorderait de moins en moins de fenêtres.
            boite.tache.setTaskCompleted(success: true)
        }

        // iOS accorde une trentaine de secondes, puis tue le processus sans
        // sommation. Ce gestionnaire est la seule chance de s'arrêter proprement
        // — sans lui, une écriture pourrait être coupée en deux.
        task.expirationHandler = {
            travail.cancel()
            log.debug("fenêtre d'arrière-plan expirée")
        }
    }
    #endif
}
