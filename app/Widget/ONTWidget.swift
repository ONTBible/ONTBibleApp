import ONTData
import ONTDesignSystem
import ONTKit
import SwiftUI
import WidgetKit

/// Le verset du jour, sur l'écran d'accueil.
///
/// ## Pourquoi il ne parle à personne
///
/// Un widget vit dans un autre processus que l'app, réveillé par le système
/// quelques dizaines de millisecondes à la fois, avec une trentaine de
/// mégaoctets. Il ne peut ni attendre le réseau, ni charger le corpus.
///
/// Il n'en a pas besoin : le verset du jour est une **fonction de la date**
/// (`DailySelection`), calculée sur un vivier plat de 125 Ko. L'app, la
/// notification et le widget tombent donc sur le même verset le même jour
/// sans jamais se parler — et rien ne quitte l'appareil.
struct DailyVerseEntry: TimelineEntry {
    let date: Date
    let verse: DailyVerse?
}

struct DailyVerseProvider: TimelineProvider {
    private let repository = BundleDailyVerseRepository(bundle: .main)

    func placeholder(in context: Context) -> DailyVerseEntry {
        DailyVerseEntry(date: Date(), verse: repository.pool().first)
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyVerseEntry) -> Void) {
        completion(entry(for: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyVerseEntry>) -> Void) {
        // Une entrée par jour, sur une semaine. Le système les tient toutes
        // en réserve : le widget reste juste même si l'app n'est pas ouverte
        // pendant une semaine, et même en avion.
        let calendar = Calendar.current
        let debut = calendar.startOfDay(for: Date())
        let entrees = (0..<7).compactMap { offset -> DailyVerseEntry? in
            guard let jour = calendar.date(byAdding: .day, value: offset, to: debut) else { return nil }
            return entry(for: jour)
        }
        // `.atEnd` et non une échéance fixe : le système redemande quand il a
        // épuisé la réserve, sans qu'on ait à deviner minuit dans le bon fuseau.
        completion(Timeline(entries: entrees, policy: .atEnd))
    }

    private func entry(for date: Date) -> DailyVerseEntry {
        DailyVerseEntry(
            date: Calendar.current.startOfDay(for: date),
            verse: DailySelection.verse(for: date, in: repository.pool())
        )
    }
}

struct DailyVerseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DailyVerseEntry

    var body: some View {
        Group {
            if let verse = entry.verse {
                ONTDailyCard.widget(verse: verse, size: taille)
            } else {
                // Le vivier manque : on le dit, plutôt qu'un widget vide qu'on
                // prendrait pour une panne du système.
                Text("Corpus indisponible")
                    .font(.footnote)
                    .foregroundStyle(ONTColors.gold.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Le bordeaux du logo, quelle que soit l'apparence du système : c'est
        // à cette couleur qu'on reconnaît la carte au milieu des autres.
        .containerBackground(ONTColors.burgundy, for: .widget)
        // Toucher **hors** de la pastille ouvre le passage, sélectionné.
        .widgetURL(entry.verse.flatMap {
            URL(string: "ont://read/\($0.bookId)/\($0.chapterId)?v=\($0.verse)")
        })
    }

    private var taille: ONTDailyCard<AnyView>.Size {
        // **La quatrième famille prend la plus grande typographie, pas une
        // quatrième.**
        //
        // Les trois tailles de `ONTDailyCard` ont été **mesurées au pixel**
        // contre la carte de YouVersion, hauteur d'x contre hauteur d'x. En
        // inventer une quatrième pour `systemExtraLargePortrait` reviendrait à
        // poser des nombres que personne n'a mesurés, dans le fichier qui dit
        // en toutes lettres d'où viennent les siens.
        //
        // `.large` est donc juste, et perfectible : la carte est plus haute,
        // son texte pourrait l'être aussi. Ça demande la même mesure que les
        // trois autres ont reçue, sur une capture de la vraie famille.
        if #available(iOS 27.0, *), family == .systemExtraLargePortrait {
            return .large
        }
        return switch family {
        case .systemSmall: .small
        case .systemLarge: .large
        default: .medium
        }
    }
}

struct DailyVerseWidget: Widget {
    /// **Les tailles que le lecteur peut choisir**, celle d'iOS 27 comprise.
    ///
    /// `systemExtraLargePortrait` est arrivée avec iOS 27 — le SDK la déclare
    /// `@available(iOS 27.0, *)`. L'app vise iOS 18, donc la liste se compose
    /// à l'exécution : l'écrire en dur ne compilerait pas, et la taire
    /// laisserait la quatrième case grisée dans le choix du lecteur, ce que
    /// l'auteur a vu sur son écran avant que personne ne le mesure.
    private var famillesOffertes: [WidgetFamily] {
        var familles: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
        if #available(iOS 27.0, *) {
            familles.append(.systemExtraLargePortrait)
        }
        return familles
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ONTDailyVerse", provider: DailyVerseProvider()) { entry in
            DailyVerseWidgetView(entry: entry)
        }
        .configurationDisplayName("Verset du jour")
        .description("Un verset de La Bible ONT, renouvelé chaque jour.")
        .supportedFamilies(famillesOffertes)
    }
}

@main
struct ONTWidgets: WidgetBundle {
    var body: some Widget {
        DailyVerseWidget()
    }
}
