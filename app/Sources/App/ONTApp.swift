import ONTData
import ONTDesignSystem
import LexiconFeature
import ONTKit
import QahalFeature
import ReadingFeature
import SearchFeature
import SwiftUI
import YouFeature
import os

/// Le seul rôle de ce délégué : recevoir le jeton d'appareil.
///
/// SwiftUI n'expose pas `didRegisterForRemoteNotificationsWithDeviceToken` —
/// c'est une méthode d'`UIApplicationDelegate`, et iOS n'a pas d'autre voie
/// pour rendre le jeton. Il faut donc en poser un, même vide par ailleurs.
final class PushDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken jeton: Data
    ) {
        Task { await PushDistant.enregistrer(jeton) }
    }

    /// L'échec est **silencieux pour le lecteur**, et tracé pour nous.
    ///
    /// Il arrive pour des raisons qui ne le concernent pas — pas de réseau au
    /// lancement, capacité Push absente du profil, simulateur sans compte
    /// Apple. Lui montrer une alerte reviendrait à lui reprocher notre
    /// configuration.
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Logger(subsystem: "com.labibleont.ONT", category: "push")
            .error("APNs a refusé l'enregistrement : \(error.localizedDescription)")
    }
}

@main
struct ONTApp: App {
    @UIApplicationDelegateAdaptor(PushDelegate.self) private var pushDelegate

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

    /// La mise à jour du corpus, détournable en développement.
    ///
    ///     xcrun simctl launch <sim> com.labibleont.ONT -corpus-origine http://localhost:8787/
    ///
    /// Sans cette couture, la seule façon d'éprouver l'arrivée d'un livre
    /// pendant que l'app tourne serait de publier pour de vrai sur
    /// `ontbible.com`. On vérifierait alors le rafraîchissement le jour où il
    /// est trop tard pour le corriger.
    static func miseAJour() -> CorpusUpdater {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "corpus-origine"),
            let origine = URL(string: raw) {
            return CorpusUpdater(origine: origine)
        }
        #endif
        return CorpusUpdater()
    }

    /// Les lecteurs de disque, gardés pour qu'on puisse leur dire d'oublier.
    private let corpusSurDisque: DiskCorpusRepository
    private let lexiqueSurDisque: DiskGlossaryRepository

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

        // Le corpus est lu du **disque** quand il y est, du bundle sinon.
        //
        // Le bundle n'est pas un repli : c'est le socle. Il fait marcher une
        // installation neuve avant tout réseau, et il ne disparaît jamais. Ce
        // que `CorpusUpdater` télécharge vient le recouvrir, fichier par
        // fichier — donc à tout instant chaque livre est lisible dans l'une ou
        // l'autre version, jamais dans aucune.
        //
        // C'est ce qui permet à une correction de verset d'atteindre les
        // lecteurs en minutes, sans compilation, sans envoi à Apple, sans
        // revue, et sans qu'ils aient à installer quoi que ce soit.
        let corpus = DiskCorpusRepository(socle: BundleCorpusRepository(bundle: source))
        daily = BundleDailyVerseRepository()
        let glossary = DiskGlossaryRepository()
        self.corpusSurDisque = corpus
        self.lexiqueSurDisque = glossary
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
        // La tâche d'arrière-plan doit être **enregistrée au lancement**, avant
        // que l'app ne finisse de démarrer : iOS lève une exception s'il tente
        // de lancer une tâche qui ne l'a pas été, et il le fait des heures plus
        // tard, dans un processus que personne ne regarde.
        CorpusRefresh.register { [corpusSurDisque, lexiqueSurDisque, reading, lexicon] in
            corpusSurDisque.oublier()
            lexiqueSurDisque.oublier()
            // Le réveil d'arrière-plan n'est pas sur l'acteur principal, et les
            // modèles y vivent : on repasse par lui pour le dire aux vues.
            Task { @MainActor in
                reading.corpusChanged()
                lexicon.glossaryChanged()
            }
            // **C'est ici que la notification a du sens.** Au lancement, le
            // lecteur a l'app sous les yeux — il verra le livre. Réveillé par
            // iOS, il ne saura rien sans qu'on le lui dise.
            Task { await NouveautesNotifications.verifier(corpusSurDisque, lexique: lexiqueSurDisque) }
        }
        CorpusRefresh.schedule()

        Task { [corpusSurDisque, lexiqueSurDisque, reading, lexicon] in
            // La mise à jour du corpus, en arrière-plan, une fois l'app posée.
            //
            // Elle ne bloque **rien** : l'app a déjà tout ce qu'il lui faut,
            // dans son bundle ou sur son disque. Ce qui arrive ici ne fait que
            // recouvrir, et si le réseau manque, il ne se passe simplement
            // rien.
            //
            // Le cas le plus fréquent est « rien de neuf », et il ne coûte
            // qu'une requête de huit cents octets.
            guard let neufs = try? await Self.miseAJour().synchroniser(), neufs > 0 else { return }

            // Sans cet oubli, le corpus fraîchement écrit n'apparaîtrait qu'au
            // prochain lancement : les caches en mémoire tiennent la version
            // d'avant, et rien ne leur dit qu'elle a vieilli.
            corpusSurDisque.oublier()
            lexiqueSurDisque.oublier()

            // Et sans ces deux lignes, l'oubli ne se voit pas non plus.
            //
            // Un cache vidé ne change aucune propriété observée : les vues ne
            // relisent donc rien, et le livre neuf attend le prochain
            // lancement — sur le disque, mais nulle part à l'écran. C'est
            // exactement ce que faisait la table des matières avant qu'on
            // pose des livres dans la barre latérale de l'iPad, où le trou
            // devient visible.
            reading.corpusChanged()
            lexicon.glossaryChanged()

            // Un slot qui cesse d'être vide est une parution, et le lecteur
            // veut le savoir. Après l'oubli des caches, jamais avant : c'est
            // le dépôt relu qui porte l'état neuf.
            await NouveautesNotifications.verifier(corpusSurDisque, lexique: lexiqueSurDisque)
        }

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
            // Ce que ce serveur-là sait faire. Sans session : l'app doit
            // pouvoir demander **avant** de savoir si la connexion est
            // possible.
            capacites: HTTPCapacitesService(baseURL: baseURL),
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
