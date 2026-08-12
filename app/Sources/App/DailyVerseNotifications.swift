import Foundation
import ONTKit
import UserNotifications

/// Le rappel quotidien du verset du jour.
///
/// ## Local, et pas « push »
///
/// Aucun serveur, aucun jeton d'appareil, aucun APNs. Le verset du jour est
/// une **fonction de la date** (`DailySelection`) : l'appareil sait donc à
/// l'avance ce qu'il aura à afficher, et n'a besoin de personne pour le lui
/// dire.
///
/// Ce n'est pas une économie de moyens, c'est une décision de conception.
/// Une notification distante exigerait d'enregistrer un jeton par appareil,
/// donc de tenir une liste de qui lit une Bible et à quelle heure — une donnée
/// qui révèle des convictions religieuses, catégorie particulière au sens de
/// l'article 9 du RGPD. Ici il n'y a rien à protéger parce qu'il n'y a rien
/// qui sorte : le rappel fonctionne en avion.
///
/// ## Les soixante-quatre
///
/// iOS ne garde que **64 notifications programmées** par app, et refuse
/// silencieusement les suivantes. Un `UNCalendarNotificationTrigger` répétitif
/// n'en coûte qu'une, mais son contenu est figé — le même texte chaque jour.
/// On programme donc les prochains jours un par un, avec leur verset, et on
/// recomplète à chaque ouverture de l'app.
enum DailyVerseNotifications {
    /// Combien de jours d'avance. Deux semaines : assez pour qu'un lecteur qui
    /// n'ouvre pas l'app continue de recevoir son verset, loin sous la limite
    /// des 64, et assez court pour qu'un changement d'horaire se voie vite.
    static let horizon = 14

    private static let prefix = "verset-du-jour"

    /// Demande l'autorisation. Rend `false` si le lecteur refuse.
    ///
    /// Appelée seulement quand il **active** le rappel : demander au premier
    /// lancement, avant d'avoir rien montré, c'est la meilleure façon de se
    /// faire répondre non une fois pour toutes.
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            // Refusé une fois : seul un tour par Réglages peut le défaire, et
            // redemander ici ne montrerait aucune alerte.
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    /// Reprogramme tout : annule les rappels en attente et repose l'horizon.
    ///
    /// Idempotente, et appelée à chaque changement de réglage comme à chaque
    /// passage au premier plan. C'est ce qui fait qu'on n'a jamais à raisonner
    /// sur « ce qui est déjà programmé ».
    static func reschedule(
        _ schedule: DailyVerseSchedule,
        pool: [DailyVerse],
        from date: Date = Date(),
        calendar: Calendar = .current
    ) async {
        let center = UNUserNotificationCenter.current()
        let identifiants = (0..<horizon).map { "\(prefix)-\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: identifiants)

        guard schedule.enabled, !pool.isEmpty else { return }

        for offset in 0..<horizon {
            guard
                let jour = calendar.date(byAdding: .day, value: offset, to: date),
                let quand = calendar.date(
                    bySettingHour: schedule.hour,
                    minute: schedule.minute,
                    second: 0,
                    of: jour
                ),
                // Le premier jour est déjà passé si l'heure choisie est
                // derrière nous : on ne programme pas dans le vide.
                quand > date,
                let verse = DailySelection.verse(for: jour, in: pool, calendar: calendar)
            else { continue }

            let contenu = UNMutableNotificationContent()
            // Titre et **sous-titre**, plutôt qu'un titre à deux lignes : iOS
            // tronque un titre trop long sur une seule ligne, alors qu'il
            // rend le sous-titre en dessous, à sa propre ligne. On obtient
            // ainsi « Verset du jour » puis le renvoi, sans bricolage.
            // L'espace fine insécable avant les deux-points : c'est la règle
            // française, et c'est celle que le pipeline applique déjà au
            // corps du texte. Une app qui restitue l'hébreu avec ce soin ne
            // peut pas coller sa ponctuation dans ses propres alertes.
            contenu.title = "Verset du Jour\u{202F}:"
            contenu.subtitle = verse.reference
            contenu.body = verse.text
            contenu.sound = .default
            // De quoi ouvrir le passage au bon endroit quand on touche l'alerte.
            contenu.userInfo = [
                "book": verse.bookId,
                "chapter": verse.chapterId,
                "verse": verse.verse,
            ]

            let composants = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: quand
            )
            let requete = UNNotificationRequest(
                identifier: "\(prefix)-\(offset)",
                content: contenu,
                // Non répétitif : chaque jour a son verset, donc son contenu.
                trigger: UNCalendarNotificationTrigger(dateMatching: composants, repeats: false)
            )
            try? await center.add(requete)
        }
    }
}
