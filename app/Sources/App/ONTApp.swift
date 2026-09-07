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
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Logger(subsystem: "com.labibleont.ONT", category: "push")
            .error("APNs a refusé l'enregistrement : \(error.localizedDescription)")
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
            }
                .environment(composition.router)
                .environment(composition.reading)
                .environment(composition.lexicon)
                .environment(composition.search)
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
