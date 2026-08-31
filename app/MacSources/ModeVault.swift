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

    private var surveillance: FSEventStreamRef?
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
    /// Où le pipeline écrit son aperçu, et où la liseuse va le lire.
    ///
    /// **Un seul endroit nommé**, et non deux chemins construits de part et
    /// d'autre : c'est la seule garantie que celui qui écrit et celui qui lit
    /// parlent du même dossier. Ils ne le faisaient pas — le second n'existait
    /// pas.
    nonisolated static let sortie: URL = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("vault-apercu", isDirectory: true)

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

    /// Ce qu'on fait du corpus reconstruit — injecté, et non appelé en dur.
    ///
    /// Sans ça, `ModeVault` devrait atteindre la composition de l'app, et les
    /// épreuves du signet monteraient tout le montage pour vérifier un
    /// aller-retour de `UserDefaults`. Le défaut par défaut ne fait rien :
    /// c'est ce qui rend le mode éprouvable sans corpus.
    private let montrer: @MainActor (URL?) -> Void

    public init(
        reglages: UserDefaults = .standard,
        montrer: @escaping @MainActor (URL?) -> Void = { _ in }
    ) {
        self.reglages = reglages
        self.montrer = montrer
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
        if let surveillance {
            // Les trois gestes vont ensemble : arrêter, détacher, libérer. En
            // omettre un laisse un flux vivant sur un dossier qu'on ne suit
            // plus — et il rallumerait le pipeline à chaque frappe.
            FSEventStreamStop(surveillance)
            FSEventStreamInvalidate(surveillance)
            FSEventStreamRelease(surveillance)
            self.surveillance = nil
        }
        accesOuvert?.stopAccessingSecurityScopedResource()
        accesOuvert = nil
        reglages.removeObject(forKey: Self.cleSignet)
        vault = nil
        etat = .eteint
        // Cesser de suivre, c'est aussi cesser de lire l'aperçu.
        montrer(nil)
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

    /// **FSEvents, et non un descripteur sur le dossier.**
    ///
    /// La première version ouvrait la racine du vault avec `O_EVTONLY` et un
    /// `DispatchSource`. C'est juste pour surveiller *un* dossier — et c'est
    /// précisément ce qui ne servait à rien ici : **un descripteur de dossier
    /// ne signale que ses propres entrées, jamais celles de ses
    /// sous-dossiers.** Or les brouillons vivent quatre niveaux plus bas :
    ///
    ///     brouillons/1. kenesset (le Rassemblement)/1. torah (la Fondation)/
    ///         01. bereshit (Genèse)/bereshit-7.md
    ///
    /// Le mode ne se déclenchait donc **jamais sur le travail réel**. Il
    /// paraissait fonctionner parce qu'une reconstruction a lieu au moment où
    /// l'on désigne le vault : on voyait un compte juste, et on l'attribuait à
    /// la surveillance.
    ///
    /// **Mesuré** — l'auteur a proposé le seul essai qui distingue les deux :
    /// ajouter un brouillon non publié et regarder si le compte bouge.
    ///
    ///     à la désignation du vault    44 unités, 864 versets
    ///     brouillon ajouté             44 unités, 864 versets   ← inchangé
    ///     pipeline lancé à la main     45 unités, 866 versets   ← il le lit
    ///
    /// Le pipeline lisait le brouillon ; l'app ne savait pas qu'il existait.
    /// Sans cet essai, le compte affiché — exact, et identique au corpus publié
    /// — était **indistinguable** entre « il a lu le vault » et « il a relu ce
    /// qui était déjà là ».
    ///
    /// `FSEventStream` surveille une arborescence entière, ce qu'aucun
    /// descripteur ne sait faire. Sa latence est mise à zéro : l'attente qui
    /// compte est le **silence de deux secondes** que `quelqueChoseABouge`
    /// impose déjà, et en ajouter une seconde ici la rendrait moins lisible.
    private func ouvrirLaSurveillance(_ dossier: URL) {
        var contexte = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)

        let rappel: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let mode = Unmanaged<ModeVault>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { mode.quelqueChoseABouge() }
        }

        guard
            let flux = FSEventStreamCreate(
                nil, rappel, &contexte,
                [dossier.path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0,
                UInt32(
                    kFSEventStreamCreateFlagFileEvents
                        | kFSEventStreamCreateFlagNoDefer
                        | kFSEventStreamCreateFlagIgnoreSelf))
        else {
            etat = .echec("surveillance impossible")
            return
        }
        FSEventStreamSetDispatchQueue(flux, .main)
        FSEventStreamStart(flux)
        surveillance = flux
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
                    // **Et on le fait lire.** C'est le dernier mot de la
                    // boucle, et il manquait : le pipeline écrivait un corpus
                    // que la liseuse n'ouvrait pas.
                    self.montrer(Self.sortie)
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
        let sortie = Self.sortie

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
