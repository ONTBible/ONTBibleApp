import ChuqqotFeature
import ONTData
import ONTDesignSystem
import LexiconFeature
import ONTKit
import QahalFeature
import ReadingFeature
import SearchFeature
import SwiftUI
import YouFeature
import os

/// Le seul rôle de ce délégué : recevoir le jeton d'appareil.
///
/// SwiftUI n'expose pas `didRegisterForRemoteNotificationsWithDeviceToken` —
/// c'est une méthode d'`UIApplicationDelegate`, et iOS n'a pas d'autre voie
/// pour rendre le jeton. Il faut donc en poser un, même vide par ailleurs.
final class PushDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken jeton: Data
    ) {
        Task { await PushDistant.enregistrer(jeton) }
    }

    /// L'échec est **silencieux pour le lecteur**, et tracé pour nous.
    ///
    /// Il arrive pour des raisons qui ne le concernent pas — pas de réseau au
    /// lancement, capacité Push absente du profil, simulateur sans compte
    /// Apple. Lui montrer une alerte reviendrait à lui reprocher notre
    /// configuration.
    /// **La scène reçoit les raccourcis, pas l'application.**
    ///
    /// ==`application(_:performActionFor:completionHandler:)` n'est jamais
    /// appelé dans une app à scènes== — et toute app SwiftUI en est une. Apple
    /// le documente, et rien ne le signale à l'exécution : la méthode existe,
    /// elle compile, elle porte le bon nom, et personne ne l'invoque.
    ///
    /// C'est pourquoi les trois raccourcis paraissaient et n'ouvraient rien.
    /// Relevé par l'auteur le 29 septembre 2026, deux fois — « ça fonctionne
    /// mal », puis « toujours pas » après un premier correctif qui visait un
    /// autre défaut, réel mais pas celui-là.
    ///
    /// On fournit donc une classe de délégué de scène, que le système
    /// instancie lui-même. `UISceneConfiguration` est le seul endroit où on
    /// puisse le faire sans `Info.plist`.
    func application(
        _ application: UIApplication,
        configurationForConnecting session: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(
            name: nil, sessionRole: session.role)
        config.delegateClass = SceneDesRaccourcis.self
        return config
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Logger(subsystem: "com.labibleont.ONT", category: "push")
            .error("APNs a refusé l'enregistrement : \(error.localizedDescription)")
    }
}

/// **Le délégué de scène — il n'existe que pour les raccourcis de l'icône.**
///
/// Deux entrées, et il faut les deux :
///
/// - `windowScene(_:performActionFor:)` — l'app tournait déjà, ou dormait en
///   arrière-plan ;
/// - `scene(_:willConnectTo:options:)` — ==l'app était fermée==, et le
///   raccourci arrive dans les options de connexion. Sans ce second cas, un
///   raccourci touché sur une app tuée n'ouvrirait que l'app, à l'endroit où
///   elle s'était arrêtée. C'est le cas le plus fréquent, et le plus facile à
///   manquer parce qu'il ne se teste pas en repassant de l'arrière-plan.
final class SceneDesRaccourcis: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options: UIScene.ConnectionOptions
    ) {
        if let item = options.shortcutItem { honorer(item) }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor item: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(honorer(item))
    }

    @discardableResult
    private func honorer(_ item: UIApplicationShortcutItem) -> Bool {
        guard let url = RaccourcisDeLIcone.url(de: item) else { return false }
        Task { @MainActor in RaccourciEnAttente.partage.deposer(url) }
        return true
    }
}

@main
struct ONTApp: App {
    @UIApplicationDelegateAdaptor(PushDelegate.self) private var pushDelegate

    /// L'unique endroit où les types concrets sont nommés.
    ///
    /// Partout ailleurs, le code ne connaît que les protocoles d'`ONTKit`.
    /// C'est ici, et seulement ici, qu'on décide que le corpus vient du
    /// bundle et que les surlignages vont sur le disque — remplacer l'un ou
    /// l'autre ne demande de toucher qu'à ces lignes.
    @Environment(\.scenePhase) private var phase
    @State private var composition = Composition()
    @State private var loadError: String?

    var body: some Scene {
        WindowGroup {
            // L'ouverture par-dessus l'app, et **seulement au démarrage à
            // froid**.
            //
            // Rien n'est enregistré pour l'obtenir : la scène n'est construite
            // qu'une fois par lancement de processus. Revenir de l'arrière-plan
            // ne la reconstruit pas, donc l'animation ne rejoue pas. C'est
            // exactement le comportement demandé — « seulement quand l'app a
            // été nettoyée de la RAM » —, et le système le donne sans qu'on
            // ait à le tenir.
            //
            // Un drapeau persistant aurait au contraire menti : il aurait
            // compté les *ouvertures*, pas les *lancements*.
            AvecOuverture(theme: composition.reading.preferences.theme) {
                RootView()
                    // **Les raccourcis se posent quand l'app s'efface.**
                    //
                    // iOS lit la liste au moment où l'écran d'accueil la
                    // montre, donc après le départ du premier plan. La poser
                    // au lancement la rendrait vraie une fois, puis périmée à
                    // chaque lecture — « Reprendre » nommerait le passage
                    // d'avant.
                    //
                    // `.inactive` et non `.background` : c'est la phase qui
                    // arrive **avant** que la vignette soit capturée, donc
                    // celle qui laisse le temps d'écrire.
                    .onChange(of: phase) { _, nouvelle in
                        guard nouvelle != .active else { return }
                        RaccourcisDeLIcone.poser(
                            position: composition.reading.position,
                            versetDuJour: DailySelection.verse(
                                for: Date(), in: composition.dailyPool)
                        )
                    }
            }
                .environment(composition.router)
                .environment(composition.reading)
                .environment(composition.lexicon)
                .environment(composition.search)
                .environment(composition.chuqqot)
                .environment(composition.qahal)
                .environment(composition.you)
                .environment(composition.account)
                .environment(composition)
                .task { openLaunchArgumentURL() }
                // Les rappels sont reposés à chaque ouverture : l'horizon de
                // quatorze jours se recomplète, et un changement d'heure du
                // système est pris en compte sans que le lecteur ait à
                // retoucher son réglage.
                .task {
                    await DailyVerseNotifications.reschedule(
                        composition.reading.preferences.daily,
                        pool: composition.dailyPool
                    )
                }
        }
    }

    /// Ouvre l'URL passée en argument de lancement.
    ///
    ///     xcrun simctl launch <sim> com.labibleont.ONT -ouvrir ont://read/bereshit/bereshit-18
    ///
    /// Sert à conduire l'app depuis la ligne de commande — captures et
    /// vérifications — sans passer par la confirmation système que déclenche
    /// un lien ouvert de l'extérieur.
    private func openLaunchArgumentURL() {
        #if DEBUG
        guard
            let raw = UserDefaults.standard.string(forKey: "ouvrir"),
            let url = URL(string: raw)
        else { return }
        composition.router.open(url)
        #endif
    }
}
