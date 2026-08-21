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
    /// Ce que fait l'app quand le lecteur active les parutions. Rend `false`
    /// si la notification est refusée — le réglage se remet alors seul en
    /// position fermée, plutôt que d'annoncer un service qui ne marche pas.
    ///
    /// Injecté pour la même raison que `onChange` : la vue ne connaît ni
    /// `UserNotifications` ni le réseau.
    private let onParutions: (Bool) async -> Bool

    @State private var refuse = false
    @AppStorage("push-distant-consenti") private var parutions = false

    public init(
        onChange: @escaping (DailyVerseSchedule) async -> Bool,
        onParutions: @escaping (Bool) async -> Bool = { _ in true }
    ) {
        self.onChange = onChange
        self.onParutions = onParutions
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
            .ontRow()

            Section {
                Toggle(
                    "Être prévenu des parutions",
                    isOn: Binding(
                        get: { parutions },
                        set: { actif in
                            parutions = actif
                            Task {
                                let accorde = await onParutions(actif)
                                // Refusé : le réglage revient de lui-même. Le
                                // laisser ouvert annoncerait un service que
                                // l'appareil ne rendra pas.
                                if actif && !accorde {
                                    parutions = false
                                    refuse = true
                                }
                            }
                        }
                    ))
            } header: {
                Text("Parutions")
            } footer: {
                // Le consentement se donne en connaissance de cause, ou il ne
                // vaut rien. On dit donc ce qui sort de l'appareil, ce qui
                // n'en sort pas, et comment revenir en arrière — sans
                // euphémisme et sans renvoyer à une page de conditions.
                Text(
                    "Un livre, un chapitre ou un terme du lexique qui paraît "
                        + "vous est signalé aussitôt.\n\n"
                        + "Ce réglage envoie à La Bible ONT un identifiant "
                        + "d'appareil fourni par Apple. Il n'est rattaché à "
                        + "aucun compte, et rien de ce que vous lisez n'est "
                        + "transmis. Le couper l'efface de nos serveurs.\n\n"
                        + "Sans lui, vous serez prévenu quand même — mais "
                        + "seulement à l'ouverture de l'app, ou lorsque iOS "
                        + "la réveille."
                )
            }
            .ontRow()

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
                .ontRow()
            }
        }
        .navigationTitle("Rappel")
        .navigationBarTitleDisplayMode(.inline)
        .ontRow()
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
