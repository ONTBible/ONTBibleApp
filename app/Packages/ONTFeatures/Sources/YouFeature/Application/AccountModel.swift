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
    private let profils: any ProfilRepository
    private let flow: SignInFlow
    private let reporter: any Reporter

    public private(set) var state: State = .signedOut
    public private(set) var lastSync: Date?
    public private(set) var syncing = false

    /// Ce que le lecteur dit de lui — privé aujourd'hui, profil du Qahal
    /// demain.
    ///
    /// Doublé en mémoire pour que SwiftUI voie le changement, comme les
    /// réglages de lecture : le dépôt persiste, cette propriété notifie.
    public var profil: Profil {
        didSet { profils.profil = profil }
    }

    /// Adopte le profil du serveur s'il est plus récent que le nôtre.
    ///
    /// **Le portrait est écrit avant le profil**, jamais l'inverse : le profil
    /// ne porte que le *nom* du fichier, et l'enregistrer avant que le fichier
    /// existe laisserait, entre les deux écritures, un profil qui pointe vers
    /// rien. C'est court, mais c'est exactement l'instant où l'app peut être
    /// tuée par le système.
    private func fusionnerLeProfil(_ recu: ProfilEnVol?) {
        guard let recu, recu.updatedAt > profil.updatedAt else { return }

        var nomDuFichier = profil.portrait
        if let octets = recu.portrait {
            nomDuFichier = try? profils.enregistrerLePortrait(octets)
        } else {
            // Le serveur n'a pas de portrait **et** il est plus récent : il a
            // donc été retiré ailleurs. Le garder ici ferait revivre une photo
            // que le lecteur croit supprimée.
            nomDuFichier = nil
        }
        profil = recu.versLeProfil(portrait: nomDuFichier)
    }

    /// Les octets du portrait, relus du disque.
    ///
    /// Une fonction et non une propriété : c'est une lecture de fichier, et une
    /// propriété laisserait croire qu'elle ne coûte rien.
    public func portrait() -> Data? { profils.portrait() }

    /// Enregistre un portrait et l'attache au profil.
    public func poserLePortrait(_ donnees: Data) {
        guard let nom = try? profils.enregistrerLePortrait(donnees) else { return }
        profil.portrait = nom
    }

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
        profils: any ProfilRepository,
        flow: SignInFlow,
        reporter: any Reporter = SilentReporter()
    ) {
        self.auth = auth
        self.sync = sync
        self.store = store
        self.highlights = highlights
        self.positions = positions
        self.profils = profils
        self.flow = flow
        self.reporter = reporter
        profil = profils.profil
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
            //
            // On remonte l'erreur **d'origine**, puis on affiche la phrase.
            // L'ordre compte : convertir d'abord perdrait le code exact, seul
            // renseignement qui dise quoi corriger.
            reporter.report(error, context: "connexion \(provider.rawValue)")
            let lisible = AccountError.lisible(error, for: provider)
            state = .failed(lisible.localizedDescription)
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
            // **Le profil part avec le compte.** Il n'a de sens qu'attaché à
            // lui — c'est ce qui deviendra visible au Qahal —, et le garder
            // après un effacement laisserait sur l'appareil un portrait et un
            // nom que le lecteur croit avoir supprimés.
            //
            // Une simple déconnexion, elle, le laisse : on se reconnecte, et
            // ressaisir son nom à chaque fois n'aurait aucun sens.
            profils.oublier()
            profil = Profil()
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
                // `allForSync` et non `all` : le second masque les pierres
                // tombales, et un envoi sans elles perdrait les suppressions.
                SyncPayload(
                    highlights: highlights.allForSync(),
                    position: positions.position,
                    // **Le profil ne monte que s'il porte quelque chose.**
                    // Envoyer un profil vide écraserait celui d'un autre
                    // appareil si son horodatage était plus récent — et il le
                    // serait, puisqu'un profil vide vient d'être créé.
                    profil: profil.estVide ? nil : ProfilEnVol(profil, portrait: profils.portrait())
                )
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
        fusionnerLeProfil(remote.profil)

        // La comparaison se fait sur **toutes** les lignes, pierres tombales
        // comprises : `highlight(chapterId:verse:)` ne rend que le vivant, donc
        // une suppression locale y paraîtrait comme une absence, et le serveur
        // la réécraserait avec sa version d'avant.
        let locales = Dictionary(
            highlights.allForSync().map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for incoming in remote.highlights {
            let local = locales[incoming.key]
            guard local == nil || incoming.updatedAt > local!.updatedAt else { continue }

            if incoming.deleted {
                // Une suppression reçue s'applique — et se garde comme pierre
                // tombale, sans quoi cet appareil renverrait le surlignage au
                // prochain échange.
                if let local, !local.deleted {
                    highlights.remove(local)
                }
            } else {
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
