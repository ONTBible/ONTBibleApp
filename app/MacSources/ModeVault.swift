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

    public init() {}

    /// Désigne un vault et commence à le suivre.
    public func suivre(_ dossier: URL) {
        arreter()
        vault = dossier
        etat = .enAttente
        ouvrirLaSurveillance(dossier)
        reconstruire()
    }

    /// Éteint le mode et referme le descripteur.
    public func arreter() {
        minuterie?.cancel()
        minuterie = nil
        source?.cancel()
        source = nil
        if descripteur >= 0 {
            close(descripteur)
            descripteur = -1
        }
        vault = nil
        etat = .eteint
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
        let binaire = Bundle.main.url(forAuxiliaryExecutable: "ont-pipeline")
            ?? URL(fileURLWithPath: "/usr/local/bin/ont-pipeline")
        guard FileManager.default.isExecutableFile(atPath: binaire.path) else {
            return .failure(Echec(raison: "pipeline introuvable — voir README, section macOS"))
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
