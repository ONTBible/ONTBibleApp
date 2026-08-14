import ONTDesignSystem
import ONTKit
import ReadingFeature
import SwiftUI

/// **Vous** — le compte, et l'état du corpus qu'on porte.
///
/// L'authentification est posée mais pas branchée : les trois fournisseurs
/// (Apple, Google, GitHub) supposent un backend qui délivre et vérifie les
/// jetons. « Sign in with Apple » est obligatoire dès qu'un autre fournisseur
/// tiers est proposé — c'est une règle de l'App Store, pas une préférence,
/// d'où sa place en premier.
public struct YouTab: View {
    @Environment(YouModel.self) private var model
    @Environment(AccountModel.self) private var account

    /// Ce que fait l'app quand le rappel change. Injecté depuis la cible
    /// d'app : `UserNotifications` n'a rien à faire dans une feature.
    private let onDailyChange: (DailyVerseSchedule) async -> Bool

    public init(onDailyChange: @escaping (DailyVerseSchedule) async -> Bool = { _ in false }) {
        self.onDailyChange = onDailyChange
    }

    public var body: some View {
        NavigationStack {
            List {
                AccountSection()

                Section("Lecture") {
                    NavigationLink {
                        ReadingSettingsSheet()
                    } label: {
                        Label("Réglages de lecture", systemImage: "textformat.size")
                    }
                    NavigationLink {
                        DailyVerseSettings(onChange: onDailyChange)
                    } label: {
                        Label("Verset du jour", systemImage: "sun.horizon")
                    }
                }

                Section {
                    LabeledContent("Slots rédigés") {
                        Text("\(model.writtenBooks) / \(model.allBooks)")
                            .monospacedDigit()
                    }
                    LabeledContent("Versets") {
                        Text("\(totalVerses)").monospacedDigit()
                    }
                    LabeledContent("Entrées de lexique") {
                        Text("\(model.glossaryCount)").monospacedDigit()
                    }
                } header: {
                    Text("Le corpus")
                } footer: {
                    Text(
                        "La Bible ONT est une restitution en cours. Le corpus s'étend "
                            + "à mesure que les unités sont verrouillées."
                    )
                }

                #if DEBUG
                Section {
                    NavigationLink {
                        DSCatalog()
                    } label: {
                        Label("Design system", systemImage: "paintpalette")
                    }
                } header: {
                    Text("Développement")
                } footer: {
                    Text(
                        "Le catalogue des jetons et composants. Un composant ajouté sans sa "
                            + "ligne de catalogue est un composant qu'on oubliera."
                    )
                }
                #endif

                Section("Crédits") {
                    // Le nom public, et jamais le nom fonctionnel.
                    //
                    // « Sha'eliel » est interne au vault : c'est le nom sous
                    // lequel l'auteur travaille, pas celui sous lequel il
                    // signe. Cet écran est la seule page de l'app où le crédit
                    // paraît, donc le seul endroit où la confusion se voyait.
                    LabeledContent("Traduction", value: "Gloire Bikouta")
                    LabeledContent("Hébreu", value: "Ezra SIL — SIL Open Font License")
                    LabeledContent("Titres", value: "Frank Ruhl Libre — OFL")
                }
            }
            .ontScreen()
            .navigationTitle("Vous")
        }
    }

    private var totalVerses: Int { model.verses }
}

/// Le compte et la synchronisation.
///
/// L'ordre des fournisseurs n'est pas cosmétique : « Continuer avec Apple »
/// doit figurer en premier dès qu'un autre fournisseur tiers est proposé —
/// c'est une règle de la revue App Store.
private struct AccountSection: View {
    @Environment(AccountModel.self) private var account
    @Environment(\.ontTheme) private var theme
    private var spacing = ONTSpacing()

    @State private var confirmingErasure = false

    var body: some View {
        @Bindable var account = account

        switch account.state {
        case .signedOut, .failed:
            Section {
                VStack(spacing: spacing.s) {
                    ForEach(AuthProvider.allCases, id: \.self) { provider in
                        Button {
                            Task { await account.signIn(with: provider) }
                        } label: {
                            // La capsule est dessinée ici plutôt que laissée à
                            // `.borderedProminent`. Ce style ne colore que le
                            // **titre** du label ; l'icône, elle, garde la
                            // teinte d'accent du formulaire — qui était le
                            // bordeaux de la capsule. L'icône était donc peinte
                            // de la couleur de son propre fond.
                            //
                            // En la posant à la main, le fond et ce qui se pose
                            // dessus viennent de la même paire de rôles et ne
                            // peuvent plus se confondre.
                            Label("Continuer avec \(provider.label)", systemImage: icon(provider))
                                .foregroundStyle(ONTColors.onBrand(theme.mode))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, spacing.m)
                                .background(
                                    Capsule().fill(ONTColors.brandInk(theme.mode))
                                )
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, spacing.xs)
            } header: {
                Text("Compte")
            } footer: {
                if case .failed(let message) = account.state {
                    Text(message).foregroundStyle(.red)
                } else {
                    Text(
                        "La lecture, les surlignages et les notes fonctionnent entièrement "
                            + "sans compte. La connexion ne sert qu'à les retrouver sur un "
                            + "autre appareil."
                    )
                }
            }

        case .working:
            Section("Compte") {
                HStack(spacing: spacing.m) {
                    ProgressView()
                    Text("Connexion…").foregroundStyle(.secondary)
                }
            }

        case .signedIn:
            Section {
                // Le consentement est explicite et séparé : les annotations
                // d'un lecteur de Bible révèlent des convictions religieuses
                // (RGPD, article 9), et ne peuvent pas partir sur la foi
                // d'une case noyée dans des conditions générales.
                Toggle("Synchroniser mes annotations", isOn: $account.consent)

                if account.consent {
                    Button {
                        Task { await account.synchronise() }
                    } label: {
                        LabeledContent("Synchroniser maintenant") {
                            if account.syncing {
                                ProgressView()
                            } else if let last = account.lastSync {
                                Text(last.formatted(date: .omitted, time: .shortened))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(account.syncing)
                }
            } header: {
                Text("Compte")
            } footer: {
                Text(
                    "Vos surlignages et vos notes disent ce que vous lisez et ce qui vous "
                        + "arrête. Tant que cet interrupteur est éteint, ils ne quittent pas "
                        + "cet appareil."
                )
            }

            Section {
                Button("Se déconnecter") { account.signOut() }
                Button("Supprimer mon compte", role: .destructive) {
                    confirmingErasure = true
                }
            } footer: {
                Text(
                    "La suppression efface la copie sur le serveur. Vos annotations restent "
                        + "sur cet appareil."
                )
            }
            .confirmDeletion($confirmingErasure) {
                Task { await account.eraseAccount() }
            }
        }
    }

    private func icon(_ provider: AuthProvider) -> String {
        switch provider {
        case .apple: "apple.logo"
        case .google: "g.circle.fill"
        case .github: "chevron.left.forwardslash.chevron.right"
        }
    }
}

extension View {
    fileprivate func confirmDeletion(
        _ presented: Binding<Bool>,
        action: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            "Supprimer le compte ?",
            isPresented: presented,
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive, action: action)
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("La copie de vos annotations sur le serveur sera effacée définitivement.")
        }
    }
}
