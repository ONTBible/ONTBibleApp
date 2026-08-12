import Foundation
import ONTKit
import Observation

/// Le compte et la synchronisation.
///
/// Deux principes qui gouvernent tout ce fichier :
///
/// 1. **Le local fait foi.** La synchronisation ajoute, elle ne commande pas.
///    L'app doit rester entièrement utilisable sans compte et sans réseau —
///    une liseuse qui ne s'ouvre pas dans le métro a raté son sujet.
/// 2. **Le consentement précède l'envoi.** Les surlignages d'un lecteur de
///    Bible révèlent des convictions religieuses (RGPD, article 9). Rien ne
///    part tant que l'accord n'est pas donné, explicitement et séparément.
@MainActor
@Observable
public final class AccountModel {
    public enum State: Equatable {
        case signedOut
        case working
        case signedIn
        case failed(String)
    }

    private let auth: any AuthService
    private let sync: any SyncService
    private let store: any SessionStore
    private let highlights: any HighlightRepository
    private let positions: any PositionRepository
    private let flow: SignInFlow
    private let reporter: any Reporter

    public private(set) var state: State = .signedOut
    public private(set) var lastSync: Date?
    public private(set) var syncing = false

    /// Le consentement à la synchronisation, distinct du fait d'avoir un compte.
    public var consent: Bool {
        get { store.consent.granted }
        set {
            store.consent = newValue ? .grantedNow() : .none
            if !newValue { lastSync = nil }
        }
    }

    public init(
        auth: any AuthService,
        sync: any SyncService,
        store: any SessionStore,
        highlights: any HighlightRepository,
        positions: any PositionRepository,
        flow: SignInFlow,
        reporter: any Reporter = SilentReporter()
    ) {
        self.auth = auth
        self.sync = sync
        self.store = store
        self.highlights = highlights
        self.positions = positions
        self.flow = flow
        self.reporter = reporter
        state = store.session == nil ? .signedOut : .signedIn
    }

    // MARK: - Connexion

    public func signIn(with provider: AuthProvider) async {
        state = .working
        do {
            let grant = try await flow.grant(for: provider)
            let session = try await auth.signIn(
                provider: provider,
                code: grant.code,
                redirectURI: grant.redirectURI,
                verifier: grant.verifier
            )
            store.session = session
            state = .signedIn
        } catch AccountError.cancelled {
            // Annuler n'est pas une erreur.
            state = .signedOut
        } catch {
            // Une connexion qui échoue est un vrai signal : le fournisseur a
            // changé quelque chose, ou nos identifiants ont expiré.
            reporter.report(error, context: "connexion \(provider.rawValue)")
            state = .failed(error.localizedDescription)
        }
    }

    /// Déconnecte l'appareil.
    ///
    /// N'efface **rien** en local : les annotations appartiennent au lecteur,
    /// et se déconnecter n'est pas renoncer à ce qu'on a écrit.
    public func signOut() {
        store.session = nil
        state = .signedOut
        lastSync = nil
    }

    /// Efface le compte côté serveur — le droit à l'effacement du RGPD.
    ///
    /// Le local, là encore, est laissé intact : c'est la copie distante qui
    /// disparaît, pas le travail du lecteur.
    public func eraseAccount() async {
        guard state == .signedIn else { return }
        state = .working
        do {
            try await sync.erase()
            store.session = nil
            store.consent = .none
            state = .signedOut
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Synchronisation

    /// Un aller-retour complet : on récupère, on fusionne, on renvoie.
    ///
    /// La fusion est **dernier écrit gagné**, arbitrée verset par verset — la
    /// même règle que côté serveur, appliquée des deux bords pour qu'un
    /// appareil resté longtemps hors ligne n'écrase rien en bloc.
    public func synchronise() async {
        guard state == .signedIn, consent, !syncing else { return }
        syncing = true
        defer { syncing = false }

        do {
            let remote = try await sync.pull(since: nil)
            merge(remote)

            reporter.breadcrumb("fusion : \(remote.highlights.count) surlignages reçus")

            try await sync.push(
                SyncPayload(highlights: highlights.all(), position: positions.position)
            )
            lastSync = Date()
        } catch AccountError.unauthorized {
            signOut()
        } catch AccountError.offline {
            // Hors ligne n'est pas une panne : c'est le mode normal de l'app.
            state = .signedIn
        } catch {
            // Un échec de synchronisation n'est pas une erreur pour le
            // lecteur — ses annotations sont intactes sur son appareil — mais
            // c'en est une pour nous. Sans remontée, elle serait invisible :
            // l'interface ne montre rien, et le lecteur ne signalera jamais
            // ce qu'il n'a pas vu.
            reporter.report(error, context: "synchronisation")
            state = .signedIn
        }
    }

    private func merge(_ remote: SyncPayload) {
        for incoming in remote.highlights {
            let local = highlights.highlight(
                chapterId: incoming.chapterId,
                verse: incoming.verse
            )
            if local == nil || incoming.updatedAt > local!.updatedAt {
                highlights.save(incoming)
            }
        }

        if let position = remote.position {
            let local = positions.position
            if local == nil || position.date > local!.date {
                positions.remember(position)
            }
        }
    }
}
