import CryptoKit
import Foundation

/// La mise à jour des langues sources par le réseau.
///
/// ## Pourquoi elle ne ressemble pas à `CorpusUpdater`
///
/// Le corpus se remplace **fichier par fichier**, et c'est un choix assumé
/// là-bas : ses morceaux sont indépendants, sept livres sur huit valent mieux
/// que rien. Les sources n'ont pas ce luxe. Le manifeste et ses fichiers se
/// répondent — une empreinte, un chemin, un compte d'octets par témoin — et le
/// bundle ne porte qu'**un témoin sur cinq** (l'hébreu, décision de l'auteur
/// du 11 septembre 2026). Un remplacement partiel peut donc être à la fois
/// plus neuf pour le grec et plus vieux pour l'hébreu, et une estampille
/// globale ne saurait pas le dire.
///
/// L'audit externe du 8 septembre a donné un nom à ce défaut sur le corpus
/// (A08 : « une mise à jour peut laisser un corpus composé de versions
/// incompatibles ») ; ici il est écarté **par construction** :
///
/// > **Une génération = un dossier = une estampille.** Le bundle est le
/// > plancher : sous le plancher on purge, on ne fusionne jamais.
///
/// Concrètement : tout ce que le manifeste annonce est téléchargé dans un
/// dossier candidat, chaque fichier est prouvé par son empreinte **sur les
/// octets reçus** (A09), l'estampille s'écrit en dernier, puis le dossier
/// bascule d'un seul geste. À aucun instant le dossier actif ne mêle deux
/// générations.
///
/// ## Ce que ce fichier sait du contrat, et ce qu'il en attend
///
/// Le manifeste publié est celui du pipeline **verbatim** — `ONTSources.Manifeste`,
/// le même décodeur que le bundle. Son `genere` est émis par le pipeline
/// (#286) depuis `ONT_GENERE` : la date du dernier commit du vault, la même
/// valeur au caractère près que le `generatedAt` du corpus sorti du même
/// passage — jamais un `now()`, qui republierait tout à des lecteurs dont
/// rien n'a changé. Le publieur du site vérifie ce champ avant la première
/// copie et publie le fichier tel quel. Quand il manque — `ONT_GENERE`
/// absent, doctrine « vide plutôt que fausse » — la garde d'âge refuse : un
/// manifeste sans date n'est pas prouvable plus récent, et « refuser plutôt
/// qu'accepter quand l'ordre est indécidable » est la doctrine du corpus,
/// reprise telle quelle.
///
/// Les empreintes, elles, sont **pleines** — 64 hexadécimaux, posées par le
/// pipeline dans le manifeste. Pas la forme tronquée à douze signes du
/// publieur du corpus : deux normalisations pour une même donnée finissent
/// par diverger, et celle-ci existe déjà de bout en bout.
public actor SourcesUpdater {
    /// La version du manifeste des sources que ce code sait lire.
    static let schema = 1

    public enum Failure: LocalizedError {
        case unsupportedSchema(Int)

        public var errorDescription: String? {
            switch self {
            case .unsupportedSchema(let version):
                // Même doctrine que le corpus : un manifeste plus récent que
                // cette version de l'app décrit peut-être des fichiers qu'elle
                // ne saurait pas lire. Mieux vaut rester sur le bundle.
                "Manifeste des sources non pris en charge, version \(version)"
            }
        }
    }

    private let origine: URL
    private let dossier: URL
    private let session: URLSession
    /// Le plancher : l'estampille du build, lue de son `manifest.json` — la
    /// même que celle du corpus, et c'est voulu. Corpus et sources embarquent
    /// dans le même passage de `corpus.sh` : un build = une date, et un
    /// deuxième champ serait un A07 en attente.
    ///
    /// Injectable : sans ça, l'épreuve des gardes dépendrait du bundle de
    /// l'hôte des tests, qui ne porte pas de manifeste.
    let plancher: CorpusUpdater.Estampille?

    public init(
        origine: URL = URL(string: "https://ontbible.com/")!,
        dossier: URL? = nil,
        session: URLSession = .shared
    ) {
        self.init(
            origine: origine, dossier: dossier, session: session,
            plancher: CorpusUpdater.estampilleEmbarquee())
    }

    init(
        origine: URL,
        dossier: URL?,
        session: URLSession,
        plancher: CorpusUpdater.Estampille?
    ) {
        self.origine = origine
        self.dossier = dossier ?? Self.dossierParDefaut()
        self.session = session
        self.plancher = plancher
    }

    /// `Application Support/sources` — le dossier des générations.
    ///
    /// La génération active vit dans `actif/`, et les chemins du manifeste
    /// valent sous elle comme partout : `actif/sources/he-wlc/bereshit.json`.
    /// La répétition de « sources » est le prix d'une convention unique — la
    /// même chaîne désigne le fichier dans le paquet, sur le disque et chez
    /// le publieur.
    public static func dossierParDefaut() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("sources", isDirectory: true)
    }

    /// La génération active — ce que les lecteurs de disque liront.
    public var actif: URL { dossier.appendingPathComponent("actif", isDirectory: true) }

    /// Va chercher la génération publiée si elle est plus récente, et bascule.
    ///
    /// Rend le nombre de fichiers de la génération installée, `0` quand rien
    /// n'a changé — le cas le plus fréquent, au prix d'une requête.
    ///
    /// **Ne jette pas sur une panne de réseau.** Une mise à jour est un
    /// agrément, pas une condition : la liseuse lit ce qu'elle a. Seul un
    /// manifeste d'une version inconnue remonte — il dit quelque chose.
    @discardableResult
    public func synchroniser() async throws -> Int {
        guard let (manifeste, octetsDuManifeste) = try await manifestePublie() else { return 0 }
        guard manifeste.schema == Self.schema else {
            throw Failure.unsupportedSchema(manifeste.schema)
        }

        // **On n'accepte que ce qu'on peut prouver plus récent** — que le
        // plancher du bundle ET que la génération active. La comparaison à
        // l'actif est la leçon A08 : ne comparer qu'au bundle laisse une
        // publication V2 recouvrir une V3 téléchargée, tant que V2 reste plus
        // neuve que le bundle V1. Et un manifeste **sans** date n'est pas
        // « plus vieux » : il est indécidable, donc refusé — ne rien trouver
        // n'est pas trouver zéro.
        guard let genere = manifeste.genere,
            let publiee = CorpusUpdater.Estampille(genere),
            let plancher,
            publiee > plancher,
            estampilleActive.map({ publiee > $0 }) ?? true
        else { return 0 }

        // **La génération entière, dans un dossier candidat.** Chaque fichier
        // que le manifeste annonce doit arriver et se prouver ; un seul échec
        // jette le candidat entier. Un livre à `temoins` vide est complet par
        // déclaration — son absence est du contrat, pas un trou.
        let annonces = fichiersAnnonces(manifeste)
        let candidat = dossier.appendingPathComponent(
            "candidat-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: candidat) }

        do {
            try preparer(candidat)
            for fichier in annonces {
                let octets = try await telecharger(fichier)
                try ecrire(octets, chemin: fichier.chemin, sous: candidat)
            }
            // Le manifeste lui-même, dans les octets reçus — pas re-sérialisé :
            // une re-sérialisation est une normalisation de plus.
            try ecrire(octetsDuManifeste, chemin: "sources/manifeste.json", sous: candidat)
            // **L'estampille en dernier.** Tant qu'elle n'y est pas, le
            // candidat n'est pas une génération — et comme la bascule est le
            // seul geste qui rend visible, l'ordre vaut aussi après une mort
            // subite au milieu : un candidat orphelin n'est jamais lu.
            try publiee.texte.write(
                to: candidat.appendingPathComponent("estampille.txt"),
                atomically: true, encoding: .utf8)
        } catch {
            return 0
        }

        // **La bascule, d'un seul geste.** `replaceItemAt` échange les deux
        // dossiers atomiquement ; s'il n'y a pas encore d'actif, un simple
        // déplacement suffit — il est tout aussi atomique sur un même volume.
        do {
            if FileManager.default.fileExists(atPath: actif.path) {
                _ = try FileManager.default.replaceItemAt(actif, withItemAt: candidat)
            } else {
                try FileManager.default.moveItem(at: candidat, to: actif)
            }
        } catch {
            return 0
        }
        return annonces.count
    }

    /// **Écarte la génération du disque quand le bundle est plus récent.**
    ///
    /// Le pendant de la garde de `synchroniser`, pour ce qui est **déjà là** :
    /// refuser de poser du plus vieux ne fait rien à une génération posée
    /// avant la garde. C'est la leçon du corpus (30 août — le publié écrasait
    /// le bundle plus neuf), et l'audit l'a généralisée (A08).
    ///
    /// Une estampille absente vaut « plus vieux » : une génération que
    /// personne n'a datée date forcément d'avant ce code.
    public static func purgerSiLeBundleEstPlusNeuf(
        dossier: URL = dossierParDefaut(),
        bundle: Foundation.Bundle = .main
    ) {
        purgerSiLeBundleEstPlusNeuf(
            dossier: dossier, plancher: CorpusUpdater.estampilleEmbarquee(bundle))
    }

    static func purgerSiLeBundleEstPlusNeuf(
        dossier: URL, plancher: CorpusUpdater.Estampille?
    ) {
        guard let plancher else { return }
        let actif = dossier.appendingPathComponent("actif", isDirectory: true)
        guard FileManager.default.fileExists(atPath: actif.path) else { return }
        let estampille = (try? String(
            contentsOf: actif.appendingPathComponent("estampille.txt"), encoding: .utf8))
            .flatMap { CorpusUpdater.Estampille($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if let estampille, !(estampille < plancher) { return }
        try? FileManager.default.removeItem(at: actif)
    }

    // MARK: - Ce que le manifeste annonce

    /// Tous les fichiers que la génération doit porter — les témoins de
    /// chaque livre, et l'apparat d'éditions quand il existe. La complétude
    /// se mesure contre **cette** liste : c'est le manifeste qui parle, pas
    /// une convention de nommage.
    private func fichiersAnnonces(_ manifeste: ONTSources.Manifeste) -> [ONTSources.Fichier] {
        manifeste.livres.values
            .flatMap { livre in
                livre.temoins.values + (livre.editions.map { [$0] } ?? [])
            }
            .sorted { $0.chemin < $1.chemin }
    }

    // MARK: - Le réseau

    private func manifestePublie() async throws -> (ONTSources.Manifeste, Data)? {
        let url = origine.appendingPathComponent("sources/manifeste.json")
        guard let (octets, reponse) = try? await session.data(from: url),
            (reponse as? HTTPURLResponse)?.statusCode == 200,
            let manifeste = try? JSONDecoder().decode(ONTSources.Manifeste.self, from: octets)
        else { return nil }
        return (manifeste, octets)
    }

    private func telecharger(_ fichier: ONTSources.Fichier) async throws -> Data {
        let (octets, reponse) = try await session.data(
            from: origine.appendingPathComponent(fichier.chemin))
        guard (reponse as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        // La taille d'abord, pour le diagnostic — « 1 204 octets au lieu de
        // 502 186 » dit quoi chercher, là où « empreinte fausse » ne dit rien.
        guard octets.count == fichier.octets else {
            throw URLError(.dataLengthExceedsMaximum)
        }
        // **L'empreinte, sur les octets reçus** (A09) — pleine, 64 signes,
        // celle que le pipeline a posée. Un contenu faux de même taille ne
        // doit jamais passer pour bon.
        guard Self.empreinte(octets) == fichier.sha256 else {
            throw URLError(.badServerResponse)
        }
        return octets
    }

    /// `sha256` plein, hexadécimal minuscule — la forme du manifeste des
    /// sources. Pas celle, tronquée à douze signes, du publieur du corpus.
    static func empreinte(_ octets: Data) -> String {
        SHA256.hash(data: octets).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Le disque

    private var estampilleActive: CorpusUpdater.Estampille? {
        (try? String(
            contentsOf: actif.appendingPathComponent("estampille.txt"), encoding: .utf8))
            .flatMap { CorpusUpdater.Estampille($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private func preparer(_ candidat: URL) throws {
        try FileManager.default.createDirectory(
            at: candidat, withIntermediateDirectories: true)
        // L'exclusion des sauvegardes se pose sur la racine du chantier :
        // tout ce qui vit dessous est retéléchargeable, rien n'a sa place
        // dans l'iCloud du lecteur.
        var racine = dossier
        var valeurs = URLResourceValues()
        valeurs.isExcludedFromBackup = true
        try? racine.setResourceValues(valeurs)
    }

    /// Écrit sous le candidat, au chemin que le manifeste donne — le même qui
    /// vaut dans le paquet et chez le publieur.
    private func ecrire(_ octets: Data, chemin: String, sous candidat: URL) throws {
        let destination = candidat.appendingPathComponent(chemin)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try octets.write(to: destination, options: .atomic)
    }
}
