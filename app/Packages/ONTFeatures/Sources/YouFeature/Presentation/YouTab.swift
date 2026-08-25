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
    @Environment(ReadingModel.self) private var reading

    /// Ce que fait l'app quand le rappel change. Injecté depuis la cible
    /// d'app : `UserNotifications` n'a rien à faire dans une feature.
    private let onDailyChange: (DailyVerseSchedule) async -> Bool
    private let onParutions: (Bool) async -> Bool

    public init(
        onDailyChange: @escaping (DailyVerseSchedule) async -> Bool = { _ in false },
        onParutions: @escaping (Bool) async -> Bool = { _ in false }
    ) {
        self.onDailyChange = onDailyChange
        self.onParutions = onParutions
    }

    public var body: some View {
        @Bindable var reading = reading

        return NavigationStack {
            List {
                AccountSection()

                // **Ce qui interrompt le lecteur est rangé à part.**
                //
                // Les deux réglages ci-dessous ne servaient qu'à un seul
                // écran, « Verset du jour », rangé sous « Lecture ». Accepter
                // d'envoyer un identifiant d'appareil à un serveur se faisait
                // donc au troisième niveau d'une section qui parle de
                // typographie. Le verset du jour y était mal rangé aussi : il
                // interrompt, il ne se lit pas.
                Section("Notifications") {
                    NavigationLink {
                        DailyVerseSettings(onChange: onDailyChange)
                    } label: {
                        Label("Verset du jour", systemImage: "sun.horizon")
                    }
                    NavigationLink {
                        ParutionsSettings(onParutions: onParutions)
                    } label: {
                        Label("Parutions", systemImage: "book.closed")
                    }
                }
                .ontRow()

                Section("Lecture") {
                    NavigationLink {
                        ReadingSettingsSheet()
                    } label: {
                        Label("Réglages de lecture", systemImage: "textformat.size")
                    }
                }
                .ontRow()

                // **Le registre ouvre la section du corpus, et ne s'y confond pas.**
                //
                // Il était rangé dans les réglages de lecture, entre la
                // disposition des versets et la taille du texte. C'était le
                // ranger avec la typographie : or il ne change pas la façon
                // dont le texte se présente, il change **ce que les livres
                // sont appelés** — donc le corpus lui-même, tel que le lecteur
                // le rencontre.
                //
                // Sa propre carte, détachée des trois compteurs, parce que ce
                // n'est pas une mesure : c'est le seul réglage de cet écran
                // qui décide de ce qu'on lit plutôt que de son état.
                Section {
                    Toggle(isOn: $reading.preferences.french) {
                        Label("Le français reçu", systemImage: "character.book.closed")
                    }
                } header: {
                    Text("Le Corpus")
                } footer: {
                    Text(
                        "Allumé, les livres portent le nom qu'on leur connaît — "
                            + "« Apocalypse », « la Loi », « Chapitre 7 ». Éteint, ils "
                            + "portent ce que leur nom hébreu veut dire : « le machazeh "
                            + "de Yohanan », « la Fondation », « Parashah 7 ».\n\n"
                            + "L'écart entre les deux n'est pas une nuance de traduction. "
                            + "La torah est l'instruction qui vise ; le grec l'a rendue par "
                            + "nomos, le code qui contraint, et le français en a hérité "
                            + "« la Loi ».\n\n"
                            + "Ce réglage est une béquille, et il est allumé pour qu'on "
                            + "puisse marcher avant de savoir. En l'éteignant, des mots "
                            + "apparaissent que vous n'avez peut-être jamais lus — parashah, "
                            + "la division que le scribe hébreu traçait en laissant un blanc, "
                            + "mille ans avant qu'on numérote des chapitres."
                    )
                }
                .ontRow()

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
                } footer: {
                    Text(
                        "La Bible ONT est une restitution en cours. Le corpus s'étend "
                            + "à mesure que les unités sont verrouillées."
                    )
                }
                .ontRow()

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
                .ontRow()
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
                .ontRow()
            }
            .ontRow()
            .ontScreen()
            .navigationTitle("Vous")
        }
        .ontColumn()
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
    var spacing = ONTSpacing()

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
                            // Le texte et l'icône sont en **or** sur le
                            // bordeaux, et non en encre claire : l'or est la
                            // couleur de marque du projet, et ces trois
                            // capsules sont le seul aplat de marque de l'app.
                            //
                            // `onBrandAccent` et non `gold` : sur les thèmes
                            // sombres la capsule **est** l'or, et demander l'or
                            // dessus donnerait un bouton vide.
                            Label("Continuer avec \(provider.label)", systemImage: icon(provider))
                                .foregroundStyle(ONTColors.onBrandAccent(theme.mode))
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
                // L'échec **s'ajoute** à l'explication, il ne la remplace pas.
                //
                // Il la remplaçait : une connexion ratée effaçait donc la seule
                // phrase qui dit que le compte est facultatif, et laissait
                // croire l'app cassée. C'est précisément ce qu'a vu un
                // examinateur de l'App Store le 19 août 2026.
                VStack(alignment: .leading, spacing: spacing.xs) {
                    if case .failed(let message) = account.state {
                        Text(message).foregroundStyle(.red)
                    }
                    Text(
                        "La lecture, les surlignages et les notes fonctionnent entièrement "
                            + "sans compte. La connexion ne sert qu'à les retrouver sur un "
                            + "autre appareil."
                    )
                }
            }
            .ontRow()

        case .working:
            Section("Compte") {
                HStack(spacing: spacing.m) {
                    ProgressView()
                    Text("Connexion…").foregroundStyle(.secondary)
                }
            }
            .ontRow()

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
            .ontRow()

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
            .ontRow()
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
