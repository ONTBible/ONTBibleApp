import ONTData
import ONTDesignSystem
import LexiconFeature
import ONTKit
import QahalFeature
import ReadingFeature
import SearchFeature
import SwiftUI
import YouFeature

@main
struct ONTApp: App {
    /// L'unique endroit où les types concrets sont nommés.
    ///
    /// Partout ailleurs, le code ne connaît que les protocoles d'`ONTKit`.
    /// C'est ici, et seulement ici, qu'on décide que le corpus vient du
    /// bundle et que les surlignages vont sur le disque — remplacer l'un ou
    /// l'autre ne demande de toucher qu'à ces lignes.
    @State private var composition = Composition()
    @State private var loadError: String?

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(composition.router)
                .environment(composition.reading)
                .environment(composition.lexicon)
                .environment(composition.search)
                .environment(composition.qahal)
                .environment(composition.you)
                .environment(composition.account)
                .environment(composition)
                .task { openLaunchArgumentURL() }
                // Les rappels sont reposés à chaque ouverture : l'horizon de
                // quatorze jours se recomplète, et un changement d'heure du
                // système est pris en compte sans que le lecteur ait à
                // retoucher son réglage.
                .task {
                    await DailyVerseNotifications.reschedule(
                        composition.reading.preferences.daily,
                        pool: composition.dailyPool
                    )
                }
        }
    }

    /// Ouvre l'URL passée en argument de lancement.
    ///
    ///     xcrun simctl launch <sim> com.labibleont.ONT -ouvrir ont://read/bereshit/bereshit-18
    ///
    /// Sert à conduire l'app depuis la ligne de commande — captures et
    /// vérifications — sans passer par la confirmation système que déclenche
    /// un lien ouvert de l'extérieur.
    private func openLaunchArgumentURL() {
        #if DEBUG
        guard
            let raw = UserDefaults.standard.string(forKey: "ouvrir"),
            let url = URL(string: raw)
        else { return }
        composition.router.open(url)
        #endif
    }
}

/// La composition des dépendances.
///
/// Un objet, construit une fois au lancement, qui câble les implémentations
/// concrètes aux modèles de features. C'est la seule couche qui a le droit de
/// tout connaître.
@MainActor
@Observable
final class Composition {
    let router = Router()

    let reading: ReadingModel
    let lexicon: LexiconModel
    let search: SearchModel
    let qahal: QahalModel
    let you: YouModel
    let account: AccountModel

    /// Le vivier du verset du jour, pour la programmation des rappels.
    private let daily: any DailyVerseRepository

    var dailyPool: [DailyVerse] { daily.pool() }

    init() {
        // En premier : une erreur pendant le chargement du corpus doit déjà
        // pouvoir être remontée.
        Observability.start()
        let reporter = SentryReporter()

        // Le corpus vient du bundle de l'app. En développement, un argument
        // de lancement permet de le faire échouer pour de bon — c'est ainsi
        // qu'on vérifie que la chaîne de remontée fonctionne de bout en bout,
        // sans fabriquer un faux événement qui contournerait le vrai chemin.
        #if DEBUG
        let source = ProcessInfo.processInfo.arguments.contains("-corpus-absent")
            ? Foundation.Bundle(for: NSString.self)  // ne contient aucun corpus
            : Foundation.Bundle.main
        #else
        let source = Foundation.Bundle.main
        #endif

        let corpus = BundleCorpusRepository(bundle: source)
        daily = BundleDailyVerseRepository()
        let glossary = BundleGlossaryRepository()
        let index = BundleSearchIndex()
        let store = FileReaderStore()

        reading = ReadingModel(
            corpus: corpus,
            highlights: store,
            positions: store,
            preferences: store
        )
        lexicon = LexiconModel(glossary: glossary)
        search = SearchModel(index: index, glossary: glossary, corpus: corpus)
        qahal = QahalModel(corpus: corpus, daily: daily)
        you = YouModel(corpus: corpus, glossary: glossary)

        // Le compte. L'adresse du backend vient du Info.plist : elle change
        // entre développement et production, et n'a rien à faire dans le code.
        let sessions = KeychainSessionStore()
        let base = Bundle.main.object(forInfoDictionaryKey: "ONTAPIBaseURL") as? String ?? ""
        let baseURL = URL(string: base) ?? URL(string: "https://invalide.local")!

        let auth = HTTPAuthService(baseURL: baseURL)
        let api = APIClient(baseURL: baseURL, store: sessions, auth: auth)

        account = AccountModel(
            auth: auth,
            sync: HTTPSyncService(client: api),
            store: sessions,
            highlights: store,
            positions: store,
            flow: SignInFlow(baseURL: baseURL),
            reporter: reporter
        )

        // Le corpus est embarqué : s'il ne se charge pas, c'est un défaut de
        // build, pas un incident réseau. Silencieux jusqu'ici — donc invisible.
        do {
            _ = try corpus.corpora()
        } catch {
            reporter.report(error, context: "chargement du corpus")
        }
    }
}
