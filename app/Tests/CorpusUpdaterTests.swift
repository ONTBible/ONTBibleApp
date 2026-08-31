import Foundation
import Testing

@testable import ONTData
@testable import ONTKit

/// La mise à jour du corpus par le réseau.
///
/// Ces tests interrogent **le vrai serveur**, `ontbible.com/corpus/`. C'est
/// délibéré : ce qu'on veut éprouver n'est pas la logique — elle tient en
/// trente lignes — mais l'**accord** entre ce que le site publie et ce que
/// l'app sait lire. Une doublure de réseau ne dirait rien de cet accord, et
/// c'est précisément là que ça casse : un champ renommé, un manifeste dont le
/// schéma monte, un fichier servi en `text/html` par une page d'erreur.
///
/// Ils sont donc ignorés quand le réseau manque, plutôt qu'échouer : on ne
/// bloque pas une compilation parce qu'un train est entré dans un tunnel.
@Suite("Mise à jour du corpus")
struct CorpusUpdaterTests {
    /// Un dossier neuf par test, effacé ensuite. Sans ça, le second test
    /// trouverait le corpus que le premier a téléchargé et ne prouverait rien.
    static func dossierTemporaire() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("corpus-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Le corpus publié est-il au format que cette version sait lire ?
    ///
    /// Faux pendant une montée de schéma — entre la version qui apprend le
    /// nouveau format et la publication qui l'émet. Les tests qui téléchargent
    /// vraiment n'ont alors rien à éprouver : `CorpusUpdater` refuse le
    /// manifeste **à dessein**, et c'est ce refus qui protège les versions
    /// antérieures. `manifesteLisible` continue, lui, de vérifier que l'écart
    /// va bien dans le sens inoffensif.
    static var corpusAuFormatDeLApp: Bool {
        get async {
            let url = URL(string: "https://ontbible.com/corpus/manifeste.json")!
            guard let (octets, _) = try? await URLSession.shared.data(from: url),
                let manifeste = try? JSONDecoder().decode(
                    CorpusUpdater.Manifest.self, from: octets)
            else { return false }
            return manifeste.schema == CorpusUpdater.schema
        }
    }

    /// Le corpus publié porte-t-il une estampille lisible ?
    ///
    /// **Nouveau garde-fou, et il change ce que ces tests peuvent prouver.**
    /// `CorpusUpdater` n'accepte plus qu'un corpus qu'il peut *prouver* plus
    /// récent que celui du bundle — voir `Estampille`. Tant que le site publie
    /// `genere: ""`, aucun téléchargement n'a lieu, et les tests qui en
    /// attendent un n'ont rien à mesurer.
    ///
    /// Ils sont donc ignorés, comme quand le réseau manque, **et pas
    /// réécrits** : le jour où la chaîne pipeline → site publie une vraie date,
    /// ils reprennent leur office sans que personne ait à y penser. Les
    /// abaisser à « zéro fichier, c'est bien aussi » aurait fait taire
    /// exactement ce qu'ils gardent.
    ///
    /// Le refus lui-même est éprouvé sans réseau, dans `EstampilleTests` : on
    /// ne peut pas demander au serveur de publier un corpus plus vieux que le
    /// bundle sur commande.
    static var corpusDatable: Bool {
        get async {
            let url = URL(string: "https://ontbible.com/corpus/manifeste.json")!
            guard let (octets, _) = try? await URLSession.shared.data(from: url),
                let manifeste = try? JSONDecoder().decode(
                    CorpusUpdater.Manifest.self, from: octets),
                let publiee = CorpusUpdater.Estampille(manifeste.genere),
                let embarquee = CorpusUpdater.estampilleEmbarquee()
            else { return false }
            // **Lisibles ne suffit pas : il faut que le publié soit le plus
            // neuf.**
            //
            // La garde vérifiait que les deux dates existent, alors que ce que
            // `synchroniser()` exige est `publiee > embarquee`. Deux dates
            // lisibles dont la publiée est la plus vieille passaient donc la
            // garde et rendaient zéro fichier — « rien n'a été téléchargé »,
            // sur une branche qui n'avait pas touché au corpus.
            //
            // Ça arrive à chaque fois que le vault avance avant que le site ne
            // republie : le paquet construit par l'intégration continue porte
            // alors une date plus récente que ce qui est en ligne. Autrement
            // dit, **toutes les PR tombaient jusqu'à la prochaine publication**,
            // pour une raison qui n'était dans aucune d'elles.
            //
            // Une garde doit répéter la condition qu'elle garde, mot pour mot.
            // Écrite « à peu près », elle laisse passer précisément les cas
            // qu'elle existait pour écarter.
            return publiee > embarquee
        }
    }

    static var reseauDisponible: Bool {
        get async {
            let url = URL(string: "https://ontbible.com/corpus/manifeste.json")!
            guard let (_, reponse) = try? await URLSession.shared.data(from: url) else {
                return false
            }
            return (reponse as? HTTPURLResponse)?.statusCode == 200
        }
    }

    @Test("Le manifeste publié est celui que l'app sait lire")
    func manifesteLisible() async throws {
        guard await Self.reseauDisponible else { return }

        let url = URL(string: "https://ontbible.com/corpus/manifeste.json")!
        let (octets, _) = try await URLSession.shared.data(from: url)
        let manifeste = try JSONDecoder().decode(CorpusUpdater.Manifest.self, from: octets)

        // **Pas une égalité — une direction.** Un corpus publié *en avance*
        // sur l'app est le cas dangereux : les lecteurs installés cesseraient
        // de se mettre à jour sans qu'aucune erreur ne le dise. L'app en
        // avance sur le corpus est l'état normal d'une montée de schéma, entre
        // le moment où une version part chez Apple et celui où le site publie
        // le nouveau format ; l'app garde alors son corpus embarqué.
        #expect(
            manifeste.schema <= CorpusUpdater.schema,
            """
            le corpus publié (schéma \(manifeste.schema)) est en avance sur \
            l'app (schéma \(CorpusUpdater.schema)) — les lecteurs installés \
            ne reçoivent plus rien, en silence
            """
        )
        #expect(!manifeste.livres.isEmpty)
        // Les quatre fichiers que le lecteur de disque sait recouvrir. Un de
        // moins, et l'app lirait celui-là du bundle sans qu'on le sache.
        for attendu in ["plan", "quotidien", "glossaire", "occurrences"] {
            #expect(manifeste.fichiers[attendu] != nil, "\(attendu) absent du manifeste")
        }
    }

    @Test("Une première synchronisation télécharge tout, la seconde rien")
    func synchronisationIdempotente() async throws {
        guard await Self.reseauDisponible else { return }
        guard await Self.corpusAuFormatDeLApp else { return }
        guard await Self.corpusDatable else { return }

        let dossier = Self.dossierTemporaire()
        defer { try? FileManager.default.removeItem(at: dossier) }

        let miseAJour = CorpusUpdater(dossier: dossier)
        let premiere = try await miseAJour.synchroniser()
        #expect(premiere > 0, "rien n'a été téléchargé")

        // Le point du registre d'empreintes : ne pas retélécharger ce qu'on a.
        // Sans lui, chaque lancement d'app reprendrait vingt méga.
        let seconde = try await miseAJour.synchroniser()
        #expect(seconde == 0, "\(seconde) fichiers retéléchargés pour rien")
    }

    @Test("Le corpus téléchargé se lit, et recouvre le bundle")
    func lectureDepuisLeDisque() async throws {
        guard await Self.reseauDisponible else { return }
        guard await Self.corpusAuFormatDeLApp else { return }
        guard await Self.corpusDatable else { return }

        let dossier = Self.dossierTemporaire()
        defer { try? FileManager.default.removeItem(at: dossier) }

        try await CorpusUpdater(dossier: dossier).synchroniser()

        // Un socle qui **échoue toujours** : si la lecture réussit, c'est
        // nécessairement le disque qui a répondu. Avec le vrai bundle, on ne
        // saurait pas lequel des deux a parlé.
        let lecteur = DiskCorpusRepository(dossier: dossier, socle: SocleMuet())
        let corpora = try lecteur.corpora()
        #expect(!corpora.isEmpty)

        let livres = lecteur.writtenBooks()
        #expect(!livres.isEmpty, "aucun livre écrit dans le plan téléchargé")

        let premier = try #require(livres.first)
        let livre = try lecteur.book(premier.id)
        #expect(!livre.chapters.isEmpty, "le livre téléchargé n'a pas de chapitre")
    }

    @Test("Sans rien sur le disque, c'est le socle qui répond")
    func repliSurLeSocle() throws {
        let vide = Self.dossierTemporaire()
        defer { try? FileManager.default.removeItem(at: vide) }

        let lecteur = DiskCorpusRepository(dossier: vide, socle: SocleFictif())
        #expect(try lecteur.corpora().count == 1)
        #expect(try lecteur.book("temoin").id == "temoin")
    }

    @Test("Un manifeste d'un schéma inconnu est refusé, pas deviné")
    func schemaInconnu() async throws {
        let dossier = Self.dossierTemporaire()
        defer { try? FileManager.default.removeItem(at: dossier) }

        // Une origine qui n'existe pas : `synchroniser` rend zéro sans jeter.
        // Une mise à jour est un agrément, pas une condition — l'app doit
        // continuer de lire ce qu'elle a.
        let miseAJour = CorpusUpdater(
            origine: URL(string: "https://ontbible.com/corpus-qui-n-existe-pas/")!,
            dossier: dossier
        )
        #expect(try await miseAJour.synchroniser() == 0)
    }
}

// MARK: - Les doublures

/// Un socle qui échoue toujours, pour prouver que c'est le disque qui répond.
private struct SocleMuet: CorpusRepository {
    struct Absent: Error {}
    func corpora() throws -> [Corpus] { throw Absent() }
    func book(_ id: String) throws -> Book { throw Absent() }
}

/// Un socle minimal, pour prouver le repli.
private struct SocleFictif: CorpusRepository {
    func corpora() throws -> [Corpus] {
        [Corpus(id: "temoin", title: "Témoin", order: 1, modes: [])]
    }

    func book(_ id: String) throws -> Book {
        Book(
            id: "temoin",
            slot: 1,
            title: "Témoin",
            french: "Témoin",
            hebrew: "",
            corpusId: "temoin",
            modeId: "temoin",
            groupId: nil,
            chapters: [],
            intro: nil,
            empty: false
        )
    }
}
