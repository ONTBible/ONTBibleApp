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
        switch family {
        case .systemSmall: .small
        case .systemLarge: .large
        default: .medium
        }
    }
}

struct DailyVerseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ONTDailyVerse", provider: DailyVerseProvider()) { entry in
            DailyVerseWidgetView(entry: entry)
        }
        .configurationDisplayName("Verset du jour")
        .description("Un verset de La Bible ONT, renouvelé chaque jour.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct ONTWidgets: WidgetBundle {
    var body: some Widget {
        DailyVerseWidget()
    }
}
