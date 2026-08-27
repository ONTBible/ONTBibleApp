import Foundation

/// Un verset du vivier quotidien.
///
/// Plat et sans arbre d'inline, contrairement à `Verse` : ce type est lu par
/// un widget, qui dispose d'une trentaine de mégaoctets et doit se dessiner en
/// quelques dizaines de millisecondes. Y charger l'arbre complet d'un livre le
/// ferait tomber.
///
/// Il ne porte que le **corps** de la traduction. Un verset du jour se lit
/// d'une traite : les gloses de l'ONT font parfois quarante mots.
public struct DailyVerse: Hashable, Sendable, Identifiable {
    /// Le livre.
    public let b: String
    /// L'unité.
    public let c: String
    /// Le numéro du verset.
    public let n: Int
    /// Le renvoi affichable — « Bereshit 1:1 ».
    public let r: String
    /// Le texte.
    public let t: String

    public var id: String { "\(c)#\(n)" }
    public var bookId: String { b }
    public var chapterId: String { c }
    public var verse: Int { n }
    public var reference: String { r }
    public var text: String { t }

    public init(b: String, c: String, n: Int, r: String, t: String) {
        self.b = b
        self.c = c
        self.n = n
        self.r = r
        self.t = t
    }
}

/// Le choix du verset du jour.
///
/// ## Pourquoi c'est un calcul et non un tirage
///
/// Trois endroits doivent tomber sur le **même** verset le même jour : l'app,
/// le widget — qui vit dans un autre processus — et la notification, préparée
/// parfois des jours à l'avance par le système. Un tirage au sort les ferait
/// diverger ; un serveur les ferait dépendre du réseau et coûterait de la
/// donnée. Une fonction pure de la date les accorde sans qu'ils se parlent.
///
/// Et rien ne sort de l'appareil : ni requête, ni jeton, ni horaire de
/// lecture. Pour une app dont les annotations révèlent des convictions
/// religieuses, c'est la seule conception défendable.
public enum DailySelection {
    /// L'indice du verset du jour, dans un vivier de `count` éléments.
    ///
    /// ## Une permutation, pas un tirage
    ///
    /// La première version brassait le numéro du jour et prenait le reste.
    /// C'était un tirage : sur 251 versets, deux jours d'un même mois
    /// tombaient sur le même avec quatre chances sur cinq — le paradoxe des
    /// anniversaires. Un « verset du jour » qui revient le 12 du mois n'en est
    /// pas un.
    ///
    /// On avance donc d'un **pas fixe premier avec la taille du vivier**. Un
    /// tel pas engendre le groupe entier : il visite les 251 versets un par un
    /// avant d'en revoir un seul. Le pas vaut environ 0,618 × la taille — le
    /// nombre d'or, qui écarte au maximum deux positions consécutives. Deux
    /// jours voisins restent donc éloignés dans le corpus, sans qu'on lise
    /// jamais deux fois la même chose avant d'avoir tout lu.
    ///
    /// Et c'est toujours une fonction pure de la date : ni état, ni tirage,
    /// ni serveur. L'app, le widget et la notification s'accordent sans se
    /// parler.
    ///
    /// ## Ce que « pure de la date » coûte, et qui n'est pas un défaut
    ///
    /// Deux appareils du même lecteur montrent deux versets différents si
    /// **leurs horloges ne disent pas le même jour** — et rien ne le signale,
    /// puisque chacun calcule juste à partir de ce qu'il croit être la date.
    ///
    /// Ça s'est vu le 27 août 2026 : le Galaxy S20+ de l'auteur était resté en
    /// **2025**, et son verset différait de celui de l'émulateur. Une année
    /// d'écart déplace la position dans le vivier, ni plus ni moins.
    ///
    /// **Il n'y a rien à corriger ici.** Une app qui doit marcher sans réseau
    /// n'a pas d'autre source de date que l'appareil, et aller la demander à un
    /// serveur détruirait précisément ce qui fait tenir l'accord entre le
    /// widget, la notification et l'app. C'est noté pour qu'un écart entre deux
    /// appareils fasse regarder l'heure avant de faire chercher un défaut.
    public static func index(for date: Date, count: Int, calendar: Calendar = .current) -> Int {
        guard count > 1 else { return 0 }

        let jour = calendar.startOfDay(for: date)
        let numero = Int(jour.timeIntervalSince1970 / 86_400)
        // Le reste de Swift suit le signe du dividende : une date d'avant 1970
        // donnerait un indice négatif.
        let position = ((numero % count) + count) % count

        return (position * step(count)) % count
    }

    /// Le pas d'avancement — premier avec `count`, donc générateur du cycle.
    static func step(_ count: Int) -> Int {
        guard count > 2 else { return 1 }
        var pas = max(1, Int(Double(count) * 0.618_033_988_749_895))
        while pgcd(pas, count) != 1 { pas += 1 }
        return pas
    }

    private static func pgcd(_ a: Int, _ b: Int) -> Int {
        var x = a, y = b
        while y != 0 { (x, y) = (y, x % y) }
        return x
    }

    /// Le verset du jour dans un vivier donné.
    public static func verse(
        for date: Date,
        in pool: [DailyVerse],
        calendar: Calendar = .current
    ) -> DailyVerse? {
        guard !pool.isEmpty else { return nil }
        return pool[index(for: date, count: pool.count, calendar: calendar)]
    }
}

/// Quand le lecteur veut recevoir le verset du jour.
///
/// L'heure est à la minute près parce que la minute est ce qui rend le rappel
/// utilisable : 7 h 00 tombe dans le réveil, 7 h 12 dans le trajet. Une app
/// qui ne propose que des heures rondes force à choisir entre deux mauvais
/// moments.
public struct DailyVerseSchedule: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var hour: Int
    public var minute: Int

    public init(enabled: Bool = false, hour: Int = 7, minute: Int = 30) {
        self.enabled = enabled
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    /// L'heure du jour, telle que la voit `UNCalendarNotificationTrigger`.
    public var components: DateComponents {
        DateComponents(hour: hour, minute: minute)
    }

    public static let `default` = DailyVerseSchedule()
}
