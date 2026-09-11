import Foundation
import ONTKit
import SwiftUI

/// **Un chargeur provisoire, et il le dit.**
///
/// La vraie lecture des langues sources — port dans `ONTKit`, réalisation
/// disque-d'abord dans `ONTData`, cache par livre — est en cours d'écriture.
/// Celui-ci lit le bundle directement pour que la feuille soit essayable
/// aujourd'hui, et il sera remplacé sans que l'interface bouge : elle ne
/// connaît que `VersetAffiche`.
///
/// Ce qu'il ne fait **pas**, et qu'il faudra : lire le disque avant le bundle,
/// mettre en cache, et suivre le manifeste plutôt que de deviner le chemin
/// d'un témoin.
enum ChargeurDeSources {
    /// **Le chemin, et non `forResource:`.**
    ///
    /// Les langues sources entrent dans le paquet par une **référence de
    /// dossier** — il le fallait, `sources/he-wlc/bereshit.json` portant le
    /// même nom de base que le livre `books/bereshit.json`, que la phase de
    /// ressources aplatit. Or `url(forResource:withExtension:)` ne descend pas
    /// dans une référence de dossier : il rend `nil` sans rien dire, et la
    /// feuille affiche « pas de texte source » sur un fichier qui est là.
    ///
    /// Constaté à l'écran le 11 septembre 2026, le paquet ouvert à côté.
    /// La première part d'un nom de témoin.
    private static func court(_ nom: String) -> String {
        for coupe in [" + ", " — ", " - "] {
            if let r = nom.range(of: coupe) {
                return String(nom[..<r.lowerBound])
            }
        }
        return nom
    }

    private static func fichier(_ chemin: String) -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent(chemin)
    }

    private struct Fichier: Decodable {
        let temoin: String
        let unites: [String: [Verset]]
    }

    private struct Verset: Decodable {
        let n: Int
        let t: String
        let mots: [Mot]?
    }

    private struct Mot: Decodable {
        let t: String
        let lem: String?
        let morph: String?
        let translit: String?
        let cible: Cible?
    }

    private struct Cible: Decodable {
        let t: String
        let lemma: String
    }

    private struct Manifeste: Decodable {
        struct Temoin: Decodable {
            let nom: String
            let langue: String
        }
        struct Livre: Decodable {
            let temoins: [String: Fichier]?
            struct Fichier: Decodable { let chemin: String }
        }
        let temoins: [String: Temoin]
        let livres: [String: Livre]
    }

    /// **Les témoins qui couvrent ce livre**, et non tous ceux qui existent.
    ///
    /// Le premier jet rendait les cinq témoins déclarés, triés par clé, et la
    /// feuille prenait le premier : `gez-dillmann`, le guèze — qui ne couvre
    /// pas Bereshit. Le fichier n'existait pas, la feuille disait « pas de
    /// texte source », et l'hébreu était là, à côté, dans le même paquet.
    ///
    /// Le manifeste porte la réponse dans `livres.<slug>.temoins` : **six
    /// livres sur sept n'en ont aucun**, et l'absence est donc le cas
    /// dominant, pas le cas limite.
    static func temoins(de livre: String) -> [TemoinAffiche] {
        guard
            let url = fichier("sources/manifeste.json"),
            let octets = try? Data(contentsOf: url),
            let m = try? JSONDecoder().decode(Manifeste.self, from: octets),
            let couvrants = m.livres[livre]?.temoins
        else { return [] }
        return couvrants.keys
            .compactMap { cle in
                m.temoins[cle].map {
                    // **Le nom du manifeste est une attribution, pas un
                    // titre.** « Westminster Leningrad Codex + Open Scriptures
                    // Hebrew Bible » déborde sur deux lignes en tête de
                    // feuille, là où le lecteur attend de savoir en un coup
                    // d'œil quelle langue il regarde. On garde sa première
                    // part, avant le « + » ou le tiret cadratin, et le nom
                    // entier reste où il doit être — dans le crédit.
                    TemoinAffiche(id: cle, nom: court($0.nom), langue: $0.langue)
                }
            }
            .sorted { $0.id < $1.id }
    }

    /// Les versets d'une unité chez un témoin — vide quand il ne la couvre pas.
    ///
    /// **L'absence n'est pas une panne** : la plupart des unités n'ont pas
    /// encore de témoin, et la feuille doit le dire plutôt que de lever.
    static func versets(temoin: String, livre: String, unite: String) -> [VersetAffiche] {
        guard
            let url = fichier("sources/\(temoin)/\(livre).json"),
            let octets = try? Data(contentsOf: url),
            let f = try? JSONDecoder().decode(Fichier.self, from: octets),
            let versets = f.unites[unite]
        else { return [] }

        return versets.enumerated().map { position, v in
            VersetAffiche(
                id: position,
                numero: v.n,
                texte: v.t,
                mots: (v.mots ?? []).enumerated().map { i, m in
                    MotAffiche(
                        id: i,
                        forme: m.t,
                        strong: m.lem,
                        morphologie: m.morph,
                        translitteration: m.translit,
                        fiche: m.cible.flatMap { c in
                            switch c.t {
                            case "term": .term(lemma: c.lemma)
                            case "shem": .shem(lemma: c.lemma)
                            // Une sorte inconnue ne mène nulle part — jamais
                            // vers une fiche choisie au hasard.
                            default: nil
                            }
                        }
                    )
                }
            )
        }
    }
}

/// Où se trouve un verset, en position et non en numéro.
public struct PositionDeVerset: Identifiable, Hashable, Sendable {
    public let livre: String
    public let unite: String
    public let position: Int

    public var id: String { "\(unite)#\(position)" }

    public init(livre: String, unite: String, position: Int) {
        self.livre = livre
        self.unite = unite
        self.position = position
    }
}

// MARK: - Les fiches, pour les rendre dans la carte

/// Ce qu'une fiche ONT donne à lire, sans quitter le verset.
public struct FicheAffichee: Hashable, Sendable {
    /// La translittération — « bara », « ʾelohim ».
    public let titre: String
    public let hebreu: String?
    /// Ce que l'ONT en dit, tel que le corpus le porte.
    public let definition: [Block]

    public init(titre: String, hebreu: String?, definition: [Block]) {
        self.titre = titre
        self.hebreu = hebreu
        self.definition = definition
    }
}

/// **Comment la feuille obtient une fiche, sans savoir d'où elle vient.**
///
/// `ReadingFeature` ne dépend d'aucune autre feature — c'est écrit dans
/// `Package.swift` : « un onglet qui ne sait rien des autres reste un onglet
/// qu'on peut déplacer, replier ou retirer ». Et il ne lit pas non plus les
/// fichiers du corpus : le lexique a ses dépôts, et les court-circuiter
/// reviendrait à ouvrir un second chemin vers la même donnée.
///
/// La composition pose donc la fonction, et la lecture ne connaît qu'elle.
public struct FicheDunMotKey: EnvironmentKey {
    public static let defaultValue: @Sendable (CibleDuNiveauTrois) -> FicheAffichee? = { _ in
        nil
    }
}

extension EnvironmentValues {
    /// La fiche d'un mot source, posée par la composition.
    public var ontFicheDunMot: @Sendable (CibleDuNiveauTrois) -> FicheAffichee? {
        get { self[FicheDunMotKey.self] }
        set { self[FicheDunMotKey.self] = newValue }
    }
}
