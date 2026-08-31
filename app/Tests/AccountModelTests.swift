import Foundation
import ONTData
import ONTKit
import Testing

@testable import YouFeature

/// Le compte et la fusion, sur des doublures.
///
/// Aucun réseau, aucun trousseau : ce sont les protocoles d'`ONTKit` qui
/// rendent ces tests possibles.
@MainActor
struct AccountModelTests {
    // MARK: - Doublures

    final class FakeAuth: AuthService, @unchecked Sendable {
        func signIn(
            provider: AuthProvider, code: String, redirectURI: String, verifier: String?
        ) async throws -> Session {
            .init(accessToken: "a", refreshToken: "r", expiresAt: .distantFuture)
        }
        func refresh(_ precedente: Session) async throws -> Session {
            .init(accessToken: "a2", refreshToken: "r2", expiresAt: .distantFuture)
        }
    }

    final class FakeSync: SyncService, @unchecked Sendable {
        var remote = SyncPayload()
        var pushed: SyncPayload?
        var erased = false

        func pull(since: Date?) async throws -> SyncPayload { remote }
        func push(_ payload: SyncPayload) async throws { pushed = payload }
        func erase() async throws { erased = true }
    }

    /// La doublure imite le vrai stockage, pierres tombales comprises : une
    /// doublure qui supprimerait physiquement rendrait les tests d'accord alors
    /// que l'app ne l'est pas.
    final class FakeHighlights: HighlightRepository {
        var stored: [String: Highlight] = [:]
        func all() -> [Highlight] { stored.values.filter { !$0.deleted } }
        func allForSync() -> [Highlight] { Array(stored.values) }
        func highlight(chapterId: String, verse: Int) -> Highlight? {
            stored[Highlight.key(chapterId: chapterId, verse: verse)]
                .flatMap { $0.deleted ? nil : $0 }
        }
        func save(_ highlight: Highlight) { stored[highlight.key] = highlight }
        func remove(_ highlight: Highlight) {
            guard var existant = stored[highlight.key] else { return }
            existant.deleted = true
            existant.note = nil
            existant.updatedAt = Date()
            stored[highlight.key] = existant
        }
    }

    final class FakePositions: PositionRepository {
        var position: ReadingPosition?
        func remember(_ position: ReadingPosition) { self.position = position }
    }

    /// Un dépôt de profil **en mémoire**, portrait compris.
    ///
    /// Le portrait est gardé sous son nom, comme sur le disque, pour que le
    /// test éprouve la même chorégraphie : écrire l'image, puis le profil qui
    /// la nomme. Une doublure qui rendrait toujours les mêmes octets laisserait
    /// passer une inversion de cet ordre.
    final class FakeProfils: ProfilRepository {
        var profil = Profil()
        var portraits: [String: Data] = [:]
        private(set) var oublie = false

        func enregistrerLePortrait(_ donnees: Data) throws -> String {
            let nom = "portrait-\(portraits.count).jpg"
            portraits[nom] = donnees
            return nom
        }

        func portrait() -> Data? { profil.portrait.flatMap { portraits[$0] } }

        func oublier() {
            profil = Profil()
            portraits.removeAll()
            oublie = true
        }
    }

    private func makeModel(
        signedIn: Bool = true,
        consent: Bool = true
    ) -> (AccountModel, FakeSync, FakeHighlights) {
        makeModel(signedIn: signedIn, consent: consent, profils: FakeProfils())
    }

    private func makeModel(
        signedIn: Bool = true,
        consent: Bool = true,
        profils: FakeProfils
    ) -> (AccountModel, FakeSync, FakeHighlights) {
        let sync = FakeSync()
        let highlights = FakeHighlights()
        let store = InMemorySessionStore(
            session: signedIn
                ? Session(accessToken: "a", refreshToken: "r", expiresAt: .distantFuture)
                : nil,
            consent: consent ? .grantedNow() : .none
        )
        let model = AccountModel(
            auth: FakeAuth(),
            sync: sync,
            store: store,
            highlights: highlights,
            positions: FakePositions(),
            profils: profils,
            flow: SignInFlow(baseURL: URL(string: "https://exemple.test")!)
        )
        return (model, sync, highlights)
    }

    private func highlight(_ verse: Int, _ color: HighlightColor, at seconds: TimeInterval)
        -> Highlight {
        Highlight(
            bookId: "bereshit", chapterId: "bereshit-18", verse: verse,
            color: color, updatedAt: Date(timeIntervalSince1970: seconds)
        )
    }

    // MARK: - Consentement

    @Test("sans consentement, rien ne part")
    func requiresConsent() async {
        let (model, sync, _) = makeModel(consent: false)
        await model.synchronise()

        #expect(sync.pushed == nil, "aucune donnée ne doit quitter l'appareil")
    }

    @Test("sans compte, rien ne part non plus")
    func requiresAccount() async {
        let (model, sync, _) = makeModel(signedIn: false)
        await model.synchronise()

        #expect(sync.pushed == nil)
    }

    @Test("retirer le consentement oublie la dernière synchronisation")
    func withdrawal() {
        let (model, _, _) = makeModel()
        model.consent = false

        #expect(!model.consent)
        #expect(model.lastSync == nil)
    }

    // MARK: - Fusion

    @Test("un surlignage distant plus récent gagne")
    func remoteWins() async {
        let (model, sync, highlights) = makeModel()
        highlights.save(highlight(19, .gold, at: 1_000))
        sync.remote = SyncPayload(highlights: [highlight(19, .sky, at: 2_000)])

        await model.synchronise()

        #expect(highlights.highlight(chapterId: "bereshit-18", verse: 19)?.color == .sky)
    }

    @Test("un surlignage local plus récent résiste")
    func localWins() async {
        let (model, sync, highlights) = makeModel()
        highlights.save(highlight(19, .sky, at: 2_000))
        sync.remote = SyncPayload(highlights: [highlight(19, .gold, at: 1_000)])

        await model.synchronise()

        #expect(highlights.highlight(chapterId: "bereshit-18", verse: 19)?.color == .sky)
    }

    @Test("un surlignage distant inconnu est adopté")
    func adoptsNew() async {
        let (model, sync, highlights) = makeModel()
        sync.remote = SyncPayload(highlights: [highlight(24, .olive, at: 1_000)])

        await model.synchronise()

        #expect(highlights.highlight(chapterId: "bereshit-18", verse: 24)?.color == .olive)
    }

    @Test("la synchronisation renvoie l'état fusionné")
    func pushesMerged() async {
        let (model, sync, highlights) = makeModel()
        highlights.save(highlight(19, .gold, at: 1_000))
        sync.remote = SyncPayload(highlights: [highlight(24, .sky, at: 1_000)])

        await model.synchronise()

        #expect(sync.pushed?.highlights.count == 2, "le local et le distant doivent repartir")
        #expect(model.lastSync != nil)
    }

    // MARK: - Déconnexion

    @Test("se déconnecter ne touche pas aux annotations locales")
    func signOutKeepsLocal() {
        let (model, _, highlights) = makeModel()
        highlights.save(highlight(19, .gold, at: 1_000))

        model.signOut()

        #expect(model.state == .signedOut)
        #expect(highlights.stored.count == 1, "les annotations appartiennent au lecteur")
    }

    @Test("supprimer le compte efface le serveur, pas l'appareil")
    func erasureKeepsLocal() async {
        let (model, sync, highlights) = makeModel()
        highlights.save(highlight(19, .gold, at: 1_000))

        await model.eraseAccount()

        #expect(sync.erased)
        #expect(model.state == .signedOut)
        #expect(highlights.stored.count == 1)
    }

    // MARK: - Ce que le lecteur lit quand la connexion échoue

    /// Le 19 août 2026, un examinateur de l'App Store a vu s'afficher, en
    /// rouge, sous l'onglet « Vous » :
    ///
    ///     L'opération n'a pas pu s'achever.
    ///     (com.apple.AuthenticationServices.AuthorizationError erreur 1000.)
    ///
    /// C'était le `localizedDescription` de l'erreur brute. Ce test tient la
    /// règle : aucune erreur, quelle qu'en soit l'origine, ne doit ressortir
    /// avec un domaine ni un numéro.
    @Test("une erreur système devient une phrase, jamais un code")
    func systemErrorBecomesASentence() {
        let brute = NSError(
            domain: "com.apple.AuthenticationServices.AuthorizationError",
            code: 1_000
        )

        let message = AccountError.lisible(brute, for: .apple).localizedDescription

        #expect(!message.contains("1000"))
        #expect(!message.contains("AuthorizationError"))
        #expect(!message.contains("com.apple"))
        #expect(message.contains("compte Apple"), "la phrase doit dire quoi vérifier")
    }

    @Test("une coupure réseau se dit comme une coupure réseau")
    func networkErrorStaysNetwork() {
        let coupure = URLError(.notConnectedToInternet)

        #expect(AccountError.lisible(coupure, for: .google) == .offline)
    }

    /// Une erreur du domaine porte déjà sa phrase — la convertir en
    /// « fournisseur indisponible » perdrait ce qu'elle disait de précis.
    @Test("une erreur du domaine traverse intacte")
    func domainErrorPassesThrough() {
        #expect(AccountError.lisible(AccountError.unauthorized, for: .apple) == .unauthorized)
        #expect(AccountError.lisible(AccountError.server(503), for: .apple) == .server(503))
    }
}

// ─────────────────────────────────────────────────────────────────────────────

/// **Le nom qu'Apple confie, et ce qu'on refuse d'écraser avec.**
///
/// Apple ne donne le nom qu'au client, et qu'à la toute première autorisation :
/// pas d'`id_token`, pas de seconde chance, pas même après une désinstallation.
/// Le serveur ne le voit jamais — Google et GitHub, eux, le lui disent, et c'est
/// lui qui amorce alors le profil.
///
/// Ces épreuves tiennent la seule garde qui compte : **on n'écrit que dans un
/// champ vide.** Sans elle, un lecteur qui a corrigé son prénom chez nous le
/// verrait remplacé par celui de sa fiche système — qu'il n'a pas choisi pour
/// cette app.
@MainActor
struct ProfilAmorceParAppleTests {
    private func modele(profil: Profil = Profil()) -> AccountModel {
        let profils = AccountModelTests.FakeProfils()
        profils.profil = profil
        return AccountModel(
            auth: AccountModelTests.FakeAuth(),
            sync: AccountModelTests.FakeSync(),
            store: InMemorySessionStore(session: nil, consent: .none),
            highlights: AccountModelTests.FakeHighlights(),
            positions: AccountModelTests.FakePositions(),
            profils: profils,
            flow: SignInFlow(baseURL: URL(string: "https://exemple.test")!)
        )
    }

    private func accord(prenom: String?, nom: String?) -> AuthorizationGrant {
        AuthorizationGrant(
            code: "code", verifier: nil, redirectURI: "", prenom: prenom, nom: nom)
    }

    @Test("Un profil vide reçoit le nom d'Apple")
    func leProfilVideLeRecoit() {
        let modele = modele()
        modele.amorcerLeProfil(depuis: accord(prenom: "Gloire", nom: "Bikouta"))

        #expect(modele.profil.prenom == "Gloire")
        #expect(modele.profil.nom == "Bikouta")
    }

    /// **La garde qui compte.** Entre la création du compte et cet instant, la
    /// synchronisation a pu descendre un profil écrit sur un autre appareil.
    @Test("Un nom déjà là n'est jamais écrasé")
    func leNomDuLecteurTient() {
        let modele = modele(profil: Profil(prenom: "Sha'eliel", nom: "Bikouta"))
        modele.amorcerLeProfil(depuis: accord(prenom: "Gloire", nom: "Autre"))

        #expect(modele.profil.prenom == "Sha'eliel")
        #expect(modele.profil.nom == "Bikouta")
    }

    /// Champ par champ, pas tout ou rien : un lecteur qui n'a rempli que son
    /// prénom doit recevoir son nom de famille.
    @Test("Seul le champ vide est rempli")
    func leRemplissageEstParChamp() {
        let modele = modele(profil: Profil(prenom: "Sha'eliel"))
        modele.amorcerLeProfil(depuis: accord(prenom: "Gloire", nom: "Bikouta"))

        #expect(modele.profil.prenom == "Sha'eliel")
        #expect(modele.profil.nom == "Bikouta")
    }

    /// **Rien reçu, rien écrit — et surtout pas de date.**
    ///
    /// Toucher `updatedAt` sans rien changer suffirait à faire gagner ce profil
    /// vide à la fusion, qui arbitre au dernier écrit. Le nom saisi sur un autre
    /// appareil serait effacé par une connexion qui n'a rien apporté.
    @Test("Sans nom d'Apple, le profil n'est pas touché")
    func leProfilResteIntact() {
        let avant = Profil(prenom: "Sha'eliel", nom: "Bikouta")
        let modele = modele(profil: avant)
        modele.amorcerLeProfil(depuis: accord(prenom: nil, nom: nil))

        #expect(modele.profil.updatedAt == avant.updatedAt)
    }
}
