import ONTDesignSystem
import ONTKit
import SwiftUI

/// Être prévenu qu'un texte vient de paraître.
///
/// ## Pourquoi cet écran est séparé du verset du jour
///
/// Les deux réglages interrompent le lecteur et demandent la **même**
/// autorisation iOS, ce qui les a longtemps fait cohabiter sous « Verset du
/// jour ». Mais ils n'engagent pas la même chose, et c'est ce qui décide.
///
/// Le verset du jour est **préparé sur l'appareil** : rien n'en sort, jamais.
/// Les parutions envoient un **identifiant d'appareil** à un serveur — une
/// donnée qui révèle qu'un appareil lit une Bible, donc de catégorie
/// particulière au sens de l'article 9 du RGPD.
///
/// Sous un titre commun, le premier aurait paru engager autant que le second,
/// et le second aussi peu que le premier. Chacun garde donc son écran et son
/// propre texte.
public struct ParutionsSettings: View {
    @Environment(\.ontTheme) private var theme

    /// Ce que fait l'app quand le lecteur active les parutions. Rend `false`
    /// si la notification est refusée — le réglage se remet alors seul en
    /// position fermée, plutôt que d'annoncer un service qui ne marche pas.
    ///
    /// Injecté pour que la vue ne connaisse ni `UserNotifications` ni le
    /// réseau, qui vivent dans la cible d'app.
    private let onParutions: (Bool) async -> Bool

    @State private var refuse = false
    @AppStorage("push-distant-consenti") private var parutions = false

    public init(onParutions: @escaping (Bool) async -> Bool = { _ in true }) {
        self.onParutions = onParutions
    }

    public var body: some View {
        Form {
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
                RecoursNotificationsRefusees()
            }
        }
        .navigationTitle("Parutions")
        .ontTitreCompact()
        .ontRow()
        .ontScreen()
    }
}

/// Ce qu'on dit quand iOS a refusé les notifications à l'app.
///
/// Partagé par les deux écrans **parce qu'il n'y a qu'une autorisation**, pas
/// deux : un refus donné depuis le verset du jour empêche aussi les parutions.
/// Le laisser dans un seul des deux écrans le mettrait au mauvais endroit pour
/// l'autre — c'est exactement ce qui se passait quand les deux réglages
/// partageaient un écran nommé « Verset du jour ».
struct RecoursNotificationsRefusees: View {
    @Environment(\.ontTheme) private var theme

    var body: some View {
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
