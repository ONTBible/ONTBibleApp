import Foundation
import Observation
import os

/// Le mode développeur : lire ce qu'on est en train d'écrire.
///
/// ## Le besoin
///
/// Relire un brouillon dans un aperçu markdown est pénible, et davantage avec
/// un kératocône : corps et gloses n'y sont distingués que par **l'italique**,
/// c'est-à-dire par la pente des lettres — le pire discriminant possible quand
/// la condition déforme déjà les formes et effondre le contraste.
///
/// L'app, elle, distingue les niveaux par **la couleur, la taille et
/// l'espace** — voir `ONTTypography.apparatus` — et sait éteindre les gloses
/// pour ne garder que le corps. Elle a donc déjà raison contre l'éditeur ; il
/// lui manquait seulement de pouvoir lire le vault.
///
/// ## Comment
///
/// L'app lit `dist/`, pas le vault. Entre les deux il y a le pipeline, qui
/// tourne en quelques secondes et prend déjà `brouillons/`. Ce mode ne fait
/// donc rien d'autre que **fermer la boucle** : on désigne le vault, on
/// surveille ses fichiers, on relance le pipeline, l'app recharge.
///
/// ## Ce qu'il ne fait pas, délibérément
///
/// Il ne relance **pas** à chaque frappe. Un `.md` sauvegardé pendant qu'on
/// écrit une phrase produirait une unité à moitié écrite, et l'app clignoterait
/// à chaque mot. On attend que l'écriture se soit tue — voir `silence`.
@Observable
@MainActor
public final class ModeVault {
    /// Le dossier surveillé, ou `nil` quand le mode est éteint.
    public private(set) var vault: URL?

    /// Ce qui s'est passé en dernier, à montrer dans l'interface.
    public private(set) var etat: Etat = .eteint

    public enum Etat: Equatable {
        case eteint
        case enAttente
        case enCours
        case fait(unites: Int, versets: Int)
        case echec(String)
    }

    /// Ce qui peut empêcher une reconstruction.
    ///
    /// Un type plutôt qu'une `String` : `Result` exige une `Error`, et surtout
    /// une chaîne d'erreur finit toujours par être comparée quelque part —
    /// alors qu'on veut savoir *laquelle*, pas *comment elle s'écrit*.
    public struct Echec: Error, Equatable {
        public let raison: String
    }

    private var source: DispatchSourceFileSystemObject?
    private var descripteur: CInt = -1
    private var minuterie: Task<Void, Never>?
    private let journal = Logger(subsystem: "com.labibleont.ONT.mac", category: "vault")

    /// Le signet du vault, d'une session à l'autre.
    ///
    /// Sous bac à sable, le droit de lire un dossier ne survit pas à la
    /// fermeture de l'app : c'est le sélecteur qui l'accorde, et il l'accorde
    /// **au processus**. Un chemin relu des réglages désignerait le bon dossier
    /// et ne l'ouvrirait pas — l'échec dirait « dossier illisible » à propos
    /// d'un dossier parfaitement lisible, ce qui est le pire des messages.
    ///
    /// Un signet à portée de sécurité garde le droit lui-même, pas le chemin.
    private static let cleSignet = "vault.signet"

    /// Le dossier dont on tient l'accès ouvert, et qu'il faut refermer.
    ///
    /// `nil` quand le dossier vient du sélecteur : le système a déjà ouvert
    /// l'accès pour cette session, et il n'y a rien à refermer. Non-`nil`
    /// seulement quand on l'a rouvert soi-même depuis un signet. Chaque
    /// `start` veut son `stop`, et un compteur laissé ouvert fuit un droit.
    private var accesOuvert: URL?

    /// Où le signet est gardé.
    ///
    /// Injectable pour que les épreuves n'écrivent pas dans les réglages de
    /// l'app installée : sans ça, lancer la suite laisserait l'auteur avec un
    /// vault qu'il n'a pas désigné, ou lui retirerait le sien.
    private let reglages: UserDefaults

    /// Le temps de silence avant de reconstruire.
    ///
    /// **Deux secondes, et c'est un choix, pas un chiffre rond.** En dessous,
    /// une sauvegarde automatique d'éditeur — la plupart en font une à chaque
    /// pause de frappe — déclencherait une reconstruction par phrase. Au-dessus,
    /// on attend devant un texte qu'on vient de corriger.
    ///
    /// Chaque écriture repousse l'échéance : c'est la fin de l'écriture qu'on
    /// guette, pas son début.
    private let silence: Duration = .seconds(2)

    public init(reglages: UserDefaults = .standard) {
        self.reglages = reglages
    }

    /// Désigne un vault et commence à le suivre.
    ///
    /// L'URL vient du sélecteur, donc le système a déjà ouvert l'accès pour
    /// cette session. On enregistre un signet pour les suivantes.
    public func suivre(_ dossier: URL) {
        arreter()
        enregistrerLeSignet(dossier)
        commencer(dossier, accesAFermer: nil)
    }

    /// Reprend le vault de la session précédente, s'il y en avait un.
    ///
    /// Sans bruit quand il n'y en a pas : le mode reste éteint, ce qui est
    /// l'état de qui ne s'en sert pas. Ce n'est pas une erreur à signaler.
    public func reprendre() {
        guard let donnees = reglages.data(forKey: Self.cleSignet) else { return }
        var perime = false
        let resolu = try? URL(
            resolvingBookmarkData: donnees,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &perime)
        // Un signet qui ne se résout plus désigne un dossier déplacé, effacé,
        // ou sur un volume démonté. On l'oublie : le retenter à chaque
        // ouverture ferait échouer le lancement pour un dossier dont l'auteur
        // ne se sert peut-être plus.
        guard let dossier = resolu, dossier.startAccessingSecurityScopedResource() else {
            journal.info("signet du vault caduc — oublié")
            reglages.removeObject(forKey: Self.cleSignet)
            return
        }
        // Périmé ne veut pas dire invalide : il s'est résolu, et il porte la
        // bonne cible. Il faut seulement le réécrire, sans quoi il se périmera
        // un peu plus à chaque fois jusqu'à ne plus se résoudre du tout.
        if perime { enregistrerLeSignet(dossier) }
        commencer(dossier, accesAFermer: dossier)
    }

    /// Éteint le mode, referme le descripteur, et oublie le vault.
    ///
    /// Le signet part avec : « Cesser de suivre » veut dire cesser, pas
    /// suspendre. Le retrouver à la prochaine ouverture serait une surprise.
    public func arreter() {
        minuterie?.cancel()
        minuterie = nil
        source?.cancel()
        source = nil
        if descripteur >= 0 {
            close(descripteur)
            descripteur = -1
        }
        accesOuvert?.stopAccessingSecurityScopedResource()
        accesOuvert = nil
        reglages.removeObject(forKey: Self.cleSignet)
        vault = nil
        etat = .eteint
    }

    private func commencer(_ dossier: URL, accesAFermer: URL?) {
        vault = dossier
        accesOuvert = accesAFermer
        etat = .enAttente
        ouvrirLaSurveillance(dossier)
        reconstruire()
    }

    /// Garde le droit d'accès, et non le chemin.
    ///
    /// L'échec est silencieux à dessein : le mode marche tout de même pour la
    /// session en cours, et l'auteur n'a rien à faire de la nouvelle qu'il
    /// devra redésigner son dossier la prochaine fois. Le journal la porte.
    private func enregistrerLeSignet(_ dossier: URL) {
        do {
            let donnees = try dossier.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil)
            reglages.set(donnees, forKey: Self.cleSignet)
        } catch {
            journal.error("signet du vault non enregistré — \(error.localizedDescription)")
        }
    }

    // MARK: - La surveillance

    private func ouvrirLaSurveillance(_ dossier: URL) {
        // `open` avec `O_EVTONLY` : on ne veut pas lire le dossier, seulement
        // savoir qu'il a bougé. C'est aussi ce qui permet de le surveiller sans
        // empêcher qu'on le déplace ou le démonte.
        descripteur = open(dossier.path, O_EVTONLY)
        guard descripteur >= 0 else {
            etat = .echec("dossier illisible")
            return
        }
        let s = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descripteur,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )
        s.setEventHandler { [weak self] in self?.quelqueChoseABouge() }
        s.resume()
        source = s
    }

    private func quelqueChoseABouge() {
        etat = .enAttente
        // Chaque événement annule l'attente en cours et en ouvre une neuve.
        minuterie?.cancel()
        minuterie = Task { [silence] in
            try? await Task.sleep(for: silence)
            guard !Task.isCancelled else { return }
            self.reconstruire()
        }
    }

    // MARK: - La reconstruction

    private func reconstruire() {
        guard let vault else { return }
        etat = .enCours
        Task.detached { [journal] in
            let resultat = Self.lancerLePipeline(vault: vault)
            await MainActor.run {
                switch resultat {
                case .success(let (unites, versets)):
                    journal.info("corpus rebâti — \(unites) unités, \(versets) versets")
                    self.etat = .fait(unites: unites, versets: versets)
                case .failure(let echec):
                    journal.error("pipeline en échec — \(echec.raison)")
                    self.etat = .echec(echec.raison)
                }
            }
        }
    }

    /// Lance le pipeline sur le vault et rend ce qu'il a compté.
    ///
    /// Il écrit dans le dossier de l'app plutôt que dans `dist/` du dépôt :
    /// **on ne veut pas qu'un aperçu de brouillon salisse un arbre de travail
    /// git**, ni qu'il entre dans un build par accident.
    nonisolated private static func lancerLePipeline(
        vault: URL
    ) -> Result<(Int, Int), Echec> {
        // **Le bundle, et lui seul.**
        //
        // Il y avait ici un repli sur `/usr/local/bin/ont-pipeline`. Le bac à
        // sable l'interdit — un exécutable hors du bundle n'est pas lançable —,
        // mais ce n'est pas la seule raison de le retirer : un binaire installé
        // à part vieillit à part, et on relirait ses brouillons avec un pipeline
        // d'il y a trois semaines sans que rien ne le dise. C'est exactement ce
        // qu'`embarquer-le-pipeline.sh` explique vouloir éviter, et que le repli
        // rendait possible par la porte de derrière.
        guard let binaire = Bundle.main.url(forAuxiliaryExecutable: "ont-pipeline"),
            FileManager.default.isExecutableFile(atPath: binaire.path)
        else {
            return .failure(Echec(raison: "pipeline non embarqué — voir scripts/embarquer-le-pipeline.sh"))
        }
        let sortie = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("vault-apercu", isDirectory: true)

        let processus = Process()
        processus.executableURL = binaire
        processus.environment = [
            "ONT_VAULT": vault.path,
            "ONT_OUT": sortie.path,
        ]
        let tuyau = Pipe()
        processus.standardOutput = tuyau
        processus.standardError = tuyau
        do {
            try processus.run()
            let donnees = tuyau.fileHandleForReading.readDataToEndOfFile()
            processus.waitUntilExit()
            let texte = String(decoding: donnees, as: UTF8.self)
            guard processus.terminationStatus == 0 else {
                // La dernière ligne non vide porte l'erreur ; le reste est du
                // compte-rendu que personne ne veut lire dans une alerte.
                let derniere = texte.split(separator: "\n").last.map(String.init)
                return .failure(Echec(raison: derniere ?? "le pipeline a échoué"))
            }
            return .success(Self.compter(texte))
        } catch {
            return .failure(Echec(raison: error.localizedDescription))
        }
    }

    /// Relève les deux nombres de la ligne « Unités » du compte-rendu.
    ///
    /// Sur le format, pas sur une position : le pipeline peut ajouter une ligne
    /// sans qu'on ait à revenir ici.
    nonisolated static func compter(_ compteRendu: String) -> (Int, Int) {
        guard let ligne = compteRendu.split(separator: "\n")
            .first(where: { $0.hasPrefix("Unités") })
        else { return (0, 0) }
        let nombres = ligne.split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
        // « Unités 41 chapitres + 3 intros — 864 versets »
        guard nombres.count >= 3 else { return (0, 0) }
        return (nombres[0] + nombres[1], nombres[2])
    }
}
