import Foundation
import Observation

/// L'état de navigation.
///
/// Dans `ONTKit` et non dans une feature, parce qu'il est *partagé* : la
/// recherche pousse vers la lecture, le lexique se soulève par-dessus
/// n'importe quel onglet, et un lien `ont://` doit pouvoir amener le lecteur
/// n'importe où. Aucune feature ne peut en être propriétaire.
///
/// N'importe pas SwiftUI : `Observation` suffit, et le domaine reste libre de
/// toute dépendance à l'interface.
@MainActor
@Observable
public final class Router {
    /// Un emplacement de la barre d'onglets.
    ///
    /// Les quatre premiers sont les onglets de toujours. `book` n'existe que
    /// dans la **barre latérale de l'iPad** : un livre y est une destination à
    /// part entière, comme une playlist dans Music, et non une ligne dans la
    /// table des matières. Il garde donc sa propre pile de navigation.
    ///
    /// `RawRepresentable` écrit à la main plutôt qu'engendré : un cas à valeur
    /// associée ne peut pas avoir de brut automatique, et on tient à ce que le
    /// dernier onglet reste une seule chaîne dans les réglages.
    public enum TabID: RawRepresentable, Hashable, Sendable {
        case qahal, bible, lexicon, you
        case book(String)

        public init?(rawValue: String) {
            switch rawValue {
            case "qahal": self = .qahal
            case "bible": self = .bible
            case "lexicon": self = .lexicon
            case "you": self = .you
            default:
                guard rawValue.hasPrefix("book:") else { return nil }
                self = .book(String(rawValue.dropFirst(5)))
            }
        }

        public var rawValue: String {
            switch self {
            case .qahal: "qahal"
            case .bible: "bible"
            case .lexicon: "lexicon"
            case .you: "you"
            case .book(let id): "book:\(id)"
            }
        }

        /// Le livre visé, quand cet onglet en est un.
        public var bookId: String? {
            if case .book(let id) = self { return id }
            return nil
        }
    }

    /// Le chemin de navigation dans l'onglet Bible.
    public enum Destination: Hashable, Sendable {
        case book(String)
        case chapter(book: String, chapter: String)
        /// Le choix du verset avant d'ouvrir — l'étape que le sommaire offre.
        case verses(book: String, chapter: String)
    }

    /// L'app rouvre là où on l'a laissée — sur la lecture au premier lancement.
    public var tab: TabID {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: "tab") }
    }

    public var biblePath: [Destination] = []

    /// Le lemme dont la fiche est soulevée par-dessus la lecture.
    public var openedLemma: LemmaSelection?

    /// Le verset à atteindre à l'ouverture d'une unité — posé par la
    /// recherche, consommé par la vue de lecture.
    public var pendingVerse: Int?

    /// Les versets à **sélectionner** à l'ouverture — posés par un lien reçu.
    ///
    /// Distinct de `pendingVerse`, et pas par goût de la nuance : un résultat
    /// de recherche amène à un verset sans rien désigner, alors qu'un lien
    /// partagé dit précisément « ce passage-là ». Arriver sur un lien et
    /// devoir deviner lesquels des versets à l'écran étaient les bons, c'est
    /// perdre ce que l'expéditeur avait pris la peine de choisir.
    public var pendingSelection: Set<Int> = []

    /// Le verset qu'on vient de toucher **en lecture continue**.
    ///
    /// En prose continue il n'y a plus de ligne par verset, donc plus rien à
    /// toucher : le texte est une seule coulée. On donne alors à chaque verset
    /// une plage de lien `ont://verse/<n>`, et c'est le moteur de texte qui
    /// nous dit lequel a été atteint. Les intraduisibles gardent leur propre
    /// lien — le plus intérieur gagne, donc toucher un terme ouvre sa fiche et
    /// toucher ailleurs désigne le verset.
    public var tappedVerse: VerseSelection?

    /// Vrai quand l'ouverture doit enchaîner sur la feuille de partage — posé
    /// par la pastille du widget, consommé par la vue de lecture.
    ///
    /// Toucher « Partager » sur l'écran d'accueil puis devoir retoucher
    /// « Partager » dans l'app, c'est demander deux fois la même chose.
    public var pendingShare = false

    public init() {
        let stored = UserDefaults.standard.string(forKey: "tab") ?? ""
        tab = TabID(rawValue: stored) ?? .bible
    }

    // MARK: - Liens

    /// Le schéma d'URL interne.
    ///
    ///     ont://read/<livre>/<unité>      ouvre une unité
    ///     ont://read/<livre>              ouvre la table d'un livre
    ///     ont://term/<lemme>              soulève une fiche de lexique
    ///     ont://verse/<n>                 désigne un verset en lecture continue
    ///     ont://share/<livre>/<unité>?v=…  ouvre le passage et le partage
    public static let scheme = "ont"

    /// Le domaine des liens publics, s'il en existe un.
    ///
    /// Un lien `ont://` ne vaut que sur un appareil où l'app est installée :
    /// collé dans un message, il n'est pas cliquable, et pour qui n'a pas
    /// l'app il ne mène nulle part. Partager un passage demande donc une
    /// adresse `https://` — d'où un nom de domaine, qui sert à trois choses :
    /// ouvrir l'app quand elle est là (lien universel), montrer le passage
    /// dans un navigateur sinon, et donner un aperçu dans les messageries.
    ///
    /// Tant que la clé `ONTWebBaseURL` est absente ou vide du `Info.plist`,
    /// l'app ne propose pas de partage de lien : mieux vaut pas de bouton
    /// qu'un bouton qui produit une adresse morte.
    public static var webBase: URL? {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "ONTWebBaseURL") as? String,
            !raw.isEmpty, !raw.contains("à-remplir"),
            let url = URL(string: raw)
        else { return nil }
        return url
    }

    /// Traite un lien. Rend `false` si l'URL ne nous concerne pas.
    ///
    /// Deux formes acceptées : le schéma interne `ont://`, et le lien public
    /// `https://ontbible.com/fr/lire/<livre>/<unité>?v=1-3`, que iOS remet à
    /// l'app quand elle est installée — c'est le lien universel.
    @discardableResult
    public func open(_ url: URL) -> Bool {
        if url.scheme == "https" || url.scheme == "http" {
            return openWeb(url)
        }
        guard url.scheme == Self.scheme else { return false }
        let parts = url.pathComponents.filter { $0 != "/" }

        switch url.host {
        case "term":
            guard let lemma = parts.first else { return false }
            openedLemma = LemmaSelection(lemma)
            return true

        case "verse":
            guard let n = parts.first.flatMap(Int.init) else { return false }
            tappedVerse = VerseSelection(n)
            return true

        case "share":
            guard let book = parts.first, parts.count >= 2 else { return false }
            tab = .bible
            biblePath = [.book(book), .chapter(book: book, chapter: parts[1])]
            pendingSelection = Self.verses(in: url)
            pendingVerse = pendingSelection.min()
            pendingShare = true
            return true

        case "read":
            guard let book = parts.first else { return false }
            tab = .bible
            biblePath = parts.count >= 2
                ? [.book(book), .chapter(book: book, chapter: parts[1])]
                : [.book(book)]
            // Le widget passe `?v=12` : le passage arrive désigné, donc la
            // carte d'actions est déjà ouverte et « Partager » est à un doigt.
            pendingSelection = Self.verses(in: url)
            pendingVerse = pendingSelection.min()
            return true

        default:
            return false
        }
    }

    /// Ouvre une unité à un verset donné — ce que fait un résultat de recherche.
    public func open(book: String, chapter: String, verse: Int? = nil) {
        tab = .bible
        biblePath = [.book(book), .chapter(book: book, chapter: chapter)]
        pendingVerse = verse
    }

    /// Traite un lien public `https://ontbible.com/fr/lire/<livre>/<unité>?v=1-3`.
    private func openWeb(_ url: URL) -> Bool {
        guard
            let base = Self.webBase,
            url.host == base.host
        else { return false }

        // `/fr/lire/…` — le segment de langue coûte trois caractères
        // aujourd'hui et épargne une migration le jour d'une édition
        // anglaise. On ne vérifie pas *laquelle* : une seule existe, et un
        // lien d'une autre langue doit quand même ouvrir le passage.
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 3, parts[1] == "lire" else { return false }

        let book = parts[2]
        tab = .bible
        if parts.count >= 4 {
            biblePath = [.book(book), .chapter(book: book, chapter: parts[3])]
            // Le renvoi entier : on rouvre là où le lien pointait, et on
            // désigne ce qu'il désignait.
            pendingSelection = Self.verses(in: url)
            pendingVerse = pendingSelection.min()
        } else {
            biblePath = [.book(book)]
        }
        return true
    }

    /// Les versets du paramètre `v` — `?v=12-15,20` donne {12,13,14,15,20}.
    public static func verses(in url: URL) -> Set<Int> {
        guard
            let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "v" })?.value
        else { return [] }
        return VerseRange.parse(value)
    }

    /// Le premier numéro du renvoi — celui vers lequel la page défile.
    public static func firstVerse(in url: URL) -> Int? {
        verses(in: url).min()
    }

    /// Le lien interne d'une unité — ne vaut que sur cet appareil.
    public static func link(book: String, chapter: String) -> URL? {
        URL(string: "\(scheme)://read/\(book)/\(chapter)")
    }

    /// Le lien public d'un passage, à coller dans une conversation.
    ///
    /// `nil` tant qu'aucun domaine n'est configuré — l'app n'affiche alors pas
    /// le bouton correspondant.
    public static func webLink(book: String, chapter: String, verses: String? = nil) -> URL? {
        guard let base = webBase else { return nil }
        var components = URLComponents(
            url: base.appendingPathComponent("fr/lire/\(book)/\(chapter)"),
            resolvingAgainstBaseURL: false
        )
        if let verses, !verses.isEmpty {
            components?.queryItems = [URLQueryItem(name: "v", value: verses)]
        }
        return components?.url
    }
}
