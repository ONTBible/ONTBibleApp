import Foundation
import ONTKit
import UserNotifications
import os

/// Prévenir qu'un texte vient de paraître — un livre, ou un chapitre.
///
/// ## Locale, comme le rappel du jour — et pour la même raison
///
/// Aucun serveur, aucun jeton d'appareil, aucun APNs. C'est la décision que
/// [`DailyVerseNotifications`] documente déjà : une notification distante
/// exigerait d'enregistrer un jeton par appareil, donc de tenir une liste de
/// qui lit une Bible — une donnée qui révèle des convictions religieuses,
/// catégorie particulière au sens de l'article 9 du RGPD. Ici rien ne sort de
/// l'appareil, donc il n'y a rien à protéger.
///
/// Ce que ça coûte : le lecteur n'est prévenu que lorsqu'iOS réveille l'app,
/// ou à sa prochaine ouverture. Ce n'est pas l'instant de la publication.
/// Ce que ça évite : tenir un fichier de lecteurs.
///
/// ## Deux niveaux, et une seule alerte par livre
///
/// Un slot qui cesse d'être vide est une **parution de livre**. Des unités qui
/// s'ajoutent à un livre déjà ouvert sont des **chapitres**, et c'est le cas
/// courant : le corpus avance chapitre par chapitre, pas livre par livre.
///
/// Les deux sont annoncés, mais **jamais plus d'une alerte par livre**. Un
/// livre qui paraît avec ses dix-neuf chapitres en produirait dix-neuf, et
/// iOS les empilerait toutes sur l'écran verrouillé — la nouvelle deviendrait
/// une nuisance. On annonce donc le livre, et le compte de ce qu'il apporte.
///
/// ## Ce qui ne compte pas comme nouveau
///
/// Pas un fichier téléchargé : une virgule corrigée en produit un, et personne
/// ne veut être réveillé pour ça. Ce qui compte est **une unité qui n'existait
/// pas** — un identifiant de chapitre absent du relevé précédent.
///
/// Un chapitre qui passe de `brouillon` à `locked` n'est pas non plus une
/// parution : le lecteur l'avait déjà, la mention « brouillon » disparaît
/// simplement. L'annoncer serait annoncer deux fois le même texte.
///
/// ## Le premier lancement ne notifie jamais
///
/// Sans ça, une installation neuve annoncerait tout le corpus existant comme
/// une nouveauté. On enregistre alors l'état sans rien dire — et ce silence-là
/// est le comportement juste, pas un cas limite oublié.
enum NouveautesNotifications {
    private static let cle = "unites-parues"
    private static let prefixe = "texte-paru"
    private static let log = Logger(subsystem: "com.labibleont.ONT", category: "nouveautes")

    /// Compare l'état du corpus à ce qu'on en savait, et annonce l'écart.
    ///
    /// Appelée après chaque synchronisation — au lancement comme au réveil
    /// d'arrière-plan. Idempotente : deux appels de suite n'annoncent rien la
    /// seconde fois, puisque l'état a été enregistré.
    static func verifier(_ corpus: CorpusRepository, defaults: UserDefaults = .standard) async {
        let livres = corpus.writtenBooks()
        // `book:chapitre` plutôt que le seul identifiant de chapitre : rien
        // n'interdit à deux livres de numéroter leurs unités pareil, et une
        // collision ferait passer une parution pour du déjà-vu.
        let presentes = Set(
            livres.flatMap { livre in
                (livre.intro.map { [$0] } ?? [] + []).map { "\(livre.id):\($0.id)" }
                    + livre.chapters.map { "\(livre.id):\($0.id)" }
            })
        guard !presentes.isEmpty else { return }

        guard let connues = defaults.stringArray(forKey: cle).map(Set.init) else {
            defaults.set(Array(presentes).sorted(), forKey: cle)
            log.info("état initial enregistré : \(presentes.count) unités")
            return
        }

        let neuves = presentes.subtracting(connues)
        defaults.set(Array(presentes).sorted(), forKey: cle)
        guard !neuves.isEmpty else { return }

        // **Jamais de demande d'autorisation ici.** Un réveil d'arrière-plan
        // n'a pas d'interface, et iOS n'y montrerait aucune alerte : la
        // demande serait consommée sans que personne la voie, et le lecteur ne
        // pourrait plus jamais l'accorder depuis l'app.
        let centre = UNUserNotificationCenter.current()
        guard await autorise(centre) else {
            log.info("\(neuves.count) unité(s) parue(s), notification non autorisée")
            return
        }

        // Regroupées par livre : une alerte, quel que soit le nombre d'unités.
        let parLivre = Dictionary(grouping: neuves) { $0.prefix(while: { $0 != ":" }) }
        for livre in livres.sorted(by: { $0.slot < $1.slot }) {
            guard let unites = parLivre[Substring(livre.id)] else { continue }
            let livreEntier = connues.allSatisfy { !$0.hasPrefix("\(livre.id):") }
            await annoncer(livre, unites: unites.count, entier: livreEntier, via: centre)
        }
    }

    private static func annoncer(
        _ livre: BookOutline, unites: Int, entier: Bool, via centre: UNUserNotificationCenter
    ) async {
        let contenu = UNMutableNotificationContent()
        contenu.title = livre.title
        contenu.body =
            entier
            ? "\(livre.french) vient de paraître dans La Bible ONT."
            : (unites == 1
                ? "Un nouveau chapitre de \(livre.title) vient de paraître."
                : "\(unites) nouveaux chapitres de \(livre.title) viennent de paraître.")
        contenu.sound = .default
        // Le livre à ouvrir, pour que toucher la notification mène au texte et
        // non à l'écran d'accueil.
        contenu.userInfo = ["livre": livre.id]

        // L'identifiant porte le livre **et** le compte connu : une seconde
        // parution dans le même livre remplacerait la première si l'identifiant
        // ne bougeait pas, et le lecteur qui n'a pas encore lu la première la
        // verrait disparaître.
        let requete = UNNotificationRequest(
            identifier: "\(prefixe)-\(livre.id)-\(unites)-\(Int(Date().timeIntervalSince1970))",
            content: contenu,
            // `nil` : livrée tout de suite. Un déclencheur temporel la ferait
            // attendre, et l'app peut être endormie avant l'échéance.
            trigger: nil
        )
        try? await centre.add(requete)
        log.info("parution annoncée : \(livre.id), \(unites) unité(s), livre entier : \(entier)")
    }

    private static func autorise(_ centre: UNUserNotificationCenter) async -> Bool {
        switch await centre.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }
}
