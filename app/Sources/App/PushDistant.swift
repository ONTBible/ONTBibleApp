import CryptoKit
import Foundation
import UIKit
import UserNotifications
import os

/// L'enregistrement auprès d'Apple, pour être prévenu **à l'instant**.
///
/// ## Pourquoi les deux coexistent
///
/// [`NouveautesNotifications`] prévient déjà, sans rien faire sortir de
/// l'appareil — mais au réveil d'arrière-plan, dont iOS décide seul. Quelqu'un
/// qui n'ouvre pas l'app n'est presque jamais réveillé.
///
/// Le push distant lève cette limite, et il coûte ce que la note de
/// [`DailyVerseNotifications`] annonçait : un jeton par appareil, donc un
/// registre. Ce jeton révèle qu'un appareil lit une Bible, et c'est
/// irréductible — sans lui, aucune notification n'est possible. Ce qui reste
/// décidable, et que le backend tient, c'est de **ne rien y attacher** : pas de
/// compte, pas d'horaire, pas de lecture.
///
/// D'où le consentement **explicite** : rien n'est envoyé tant que le lecteur
/// n'a pas activé le réglage, et couper le réglage efface le jeton du serveur.
///
/// ## Ce que l'app envoie, et ce qu'elle n'envoie pas
///
/// Elle envoie le jeton et l'environnement. Elle n'envoie ni identifiant
/// d'appareil, ni compte, ni version, ni langue — rien qui permette de
/// distinguer deux lecteurs autrement que par le jeton lui-même.
@MainActor
enum PushDistant {
    /// Le consentement du lecteur. Faux par défaut, et il le reste tant que
    /// personne n'a rien demandé.
    static let cleConsentement = "push-distant-consenti"
    /// L'empreinte du dernier jeton enregistré, pour savoir quoi retirer quand
    /// le lecteur coupe — le jeton lui-même n'a pas à traîner sur le disque.
    private static let cleEmpreinte = "push-distant-empreinte"
    private static let log = Logger(subsystem: "com.labibleont.ONT", category: "push")

    private static var base: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "ONTAPIBaseURL") as? String)
            .flatMap(URL.init(string:))
    }

    /// Demande l'autorisation, puis s'enregistre auprès d'Apple.
    ///
    /// Rend `false` si le lecteur refuse la notification : le réglage doit
    /// alors se remettre seul en position fermée, sans quoi il annoncerait un
    /// service qui ne fonctionne pas.
    static func activer() async -> Bool {
        let centre = UNUserNotificationCenter.current()
        let etat = await centre.notificationSettings().authorizationStatus
        let accorde: Bool
        switch etat {
        case .authorized, .provisional, .ephemeral:
            accorde = true
        case .denied:
            // Refusé une fois : seul un tour par Réglages peut le défaire, et
            // redemander ici ne montrerait aucune alerte.
            return false
        default:
            accorde = (try? await centre.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        guard accorde else { return false }

        UserDefaults.standard.set(true, forKey: cleConsentement)
        // C'est iOS qui rend le jeton, de façon asynchrone, au délégué. On ne
        // fait ici que le demander.
        UIApplication.shared.registerForRemoteNotifications()
        return true
    }

    /// Le lecteur a coupé : on retire le jeton du serveur, puis d'Apple.
    ///
    /// **Dans cet ordre.** Se désabonner d'Apple d'abord laisserait un jeton
    /// mort dans la table jusqu'à ce qu'une diffusion le heurte — et ce jeton
    /// resterait, lui, une donnée conservée sans usage.
    static func desactiver() async {
        UserDefaults.standard.set(false, forKey: cleConsentement)
        if let empreinte = UserDefaults.standard.string(forKey: cleEmpreinte) {
            await retirer(empreinte)
            UserDefaults.standard.removeObject(forKey: cleEmpreinte)
        }
        UIApplication.shared.unregisterForRemoteNotifications()
    }

    /// Appelé par le délégué quand iOS a rendu le jeton.
    ///
    /// Ré-enregistre à chaque lancement, et c'est voulu : un jeton APNs change
    /// — restauration d'une sauvegarde, réinstallation, migration d'appareil —
    /// et rien ne prévient. L'enregistrement est idempotent côté serveur, la
    /// répétition ne coûte donc qu'une requête.
    static func enregistrer(_ jetonBrut: Data) async {
        guard UserDefaults.standard.bool(forKey: cleConsentement) else {
            // Le jeton est arrivé alors que le lecteur a coupé entre-temps.
            log.info("jeton reçu sans consentement — ignoré")
            return
        }
        let jeton = jetonBrut.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(empreinte(de: jeton), forKey: cleEmpreinte)

        guard let base else { return }
        var requete = URLRequest(url: base.appendingPathComponent("appareils"))
        requete.httpMethod = "POST"
        requete.setValue("application/json", forHTTPHeaderField: "Content-Type")
        requete.httpBody = try? JSONSerialization.data(withJSONObject: [
            "jeton": jeton,
            "environnement": environnement,
        ])
        do {
            let (_, reponse) = try await URLSession.shared.data(for: requete)
            let code = (reponse as? HTTPURLResponse)?.statusCode ?? 0
            log.info("appareil enregistré, code \(code)")
        } catch {
            // Une panne de réseau n'est pas une erreur à montrer : le lecteur
            // a activé le réglage, et le prochain lancement réessaiera.
            log.info("enregistrement remis à plus tard : \(error.localizedDescription)")
        }
    }

    private static func retirer(_ empreinte: String) async {
        guard let base else { return }
        var requete = URLRequest(
            url: base.appendingPathComponent("appareils").appendingPathComponent(empreinte))
        requete.httpMethod = "DELETE"
        _ = try? await URLSession.shared.data(for: requete)
        log.info("appareil retiré du serveur")
    }

    private static func empreinte(de jeton: String) -> String {
        SHA256.hash(data: Data(jeton.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// L'environnement du jeton.
    ///
    /// Un jeton de développement est refusé par le serveur de production
    /// d'Apple, et réciproquement — avec une erreur qui ne dit pas laquelle des
    /// deux causes est en jeu. Le profil d'approvisionnement le porte, et
    /// `DEBUG` en est le seul témoin fiable à l'exécution.
    private static var environnement: String {
        #if DEBUG
            "sandbox"
        #else
            "production"
        #endif
    }
}
