import ONTDesignSystem
import ONTKit
import SwiftUI

/// Le réglage du rappel quotidien.
///
/// L'heure se choisit **à la minute** : 7 h 00 tombe dans le réveil, 7 h 12
/// dans le trajet. Une app qui n'offre que des heures rondes force à choisir
/// entre deux mauvais moments.
public struct DailyVerseSettings: View {
    @Environment(ReadingModel.self) private var model
    @Environment(\.ontTheme) private var theme

    /// Ce que fait l'app quand le lecteur active le rappel — demander
    /// l'autorisation puis programmer. Injecté pour que la vue ne connaisse
    /// pas `UserNotifications`, qui vit dans la cible d'app.
    private let onChange: (DailyVerseSchedule) async -> Bool

    @State private var refuse = false

    public init(onChange: @escaping (DailyVerseSchedule) async -> Bool) {
        self.onChange = onChange
    }

    public var body: some View {
        @Bindable var model = model

        Form {
            Section {
                Toggle("Recevoir le verset du jour", isOn: Binding(
                    get: { model.preferences.daily.enabled },
                    set: { actif in
                        model.preferences.daily.enabled = actif
                        appliquer()
                    }
                ))

                if model.preferences.daily.enabled {
                    DatePicker(
                        "Heure",
                        selection: Binding(
                            get: { heure },
                            set: { nouvelle in
                                let parts = Calendar.current.dateComponents(
                                    [.hour, .minute], from: nouvelle
                                )
                                model.preferences.daily.hour = parts.hour ?? 7
                                model.preferences.daily.minute = parts.minute ?? 30
                                appliquer()
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                }
            } header: {
                Text("Verset du jour")
            } footer: {
                Text(
                    "Un verset différent chaque jour, tiré du corpus rédigé. "
                        + "Le rappel est préparé sur l'appareil : il fonctionne sans réseau, "
                        + "et rien de ce que vous lisez n'est envoyé nulle part."
                )
            }

            if refuse {
                Section {
                    Label {
                        Text(
                            "Les notifications sont refusées pour La Bible ONT. "
                                + "Elles s'autorisent dans Réglages › Notifications."
                        )
                    } icon: {
                        Image(systemName: "bell.slash")
                    }
                    .font(.footnote)
                    .foregroundStyle(theme.ink.opacity(0.7))
                }
            }
        }
        .navigationTitle("Rappel")
        .navigationBarTitleDisplayMode(.inline)
        .ontScreen()
    }

    /// L'heure du jour, ramenée à une date — ce que `DatePicker` sait manipuler.
    private var heure: Date {
        Calendar.current.date(
            bySettingHour: model.preferences.daily.hour,
            minute: model.preferences.daily.minute,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    private func appliquer() {
        let schedule = model.preferences.daily
        Task {
            let accorde = await onChange(schedule)
            // Le refus se constate, il ne se contourne pas : on repose
            // l'interrupteur et on dit où aller le changer, au lieu de laisser
            // un réglage allumé qui ne produirait jamais rien.
            if schedule.enabled, !accorde {
                refuse = true
                model.preferences.daily.enabled = false
            } else if accorde {
                refuse = false
            }
        }
    }
}
