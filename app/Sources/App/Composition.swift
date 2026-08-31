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
    /// Les fiches des noms propres.
    ///
    /// **Depuis le bundle seul, sans doublure de disque.** Les mises à jour de
    /// corpus n'en portent pas encore ; le jour où elles le feront, ce champ
    /// prendra son `DiskShemotRepository` comme le glossaire a le sien, et rien
    /// d'autre ne bougera.
    let shemotSurDisque: BundleShemotRepository

    var dailyPool: [DailyVerse] { daily.pool() }

    init() {
        // En premier : une erreur pendant le chargement du corpus doit déjà
        // pouvoir être remontée.
        // **Le port fait son office.** `Reporter` est une interface d'`ONTKit` ;
        // iOS y branche Sentry, le Mac le silence. Rien d'autre ne change,
        // parce que rien d'autre ne connaît Sentry — c'est précisément ce que
        // le port permettait, et la première fois qu'on s'en sert ainsi.
        #if os(iOS)
            Observability.start()
            let reporter: any Reporter = SentryReporter()
        #else
            // On n'instrumente pas une liseuse avant qu'elle ait un lecteur.
            let reporter: any Reporter = SilentReporter()
        #endif

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
        // **Avant de lire le disque, on écarte ce qui y est périmé.**
        //
        // Le disque recouvre le bundle sans condition. Une copie téléchargée
        // avant que l'estampille existe gagnerait donc sur un bundle plus
        // neuf, et pour toujours : la 1.0.5 embarquait les Shemot et n'en
        // affichait aucun, parce que le corpus de l'avant-veille répondait à
        // sa place.
        //
        // Ici et pas plus tard : après la construction, le dépôt aurait déjà
        // ouvert des fichiers qu'on s'apprête à retirer.
        CorpusUpdater.purgerSiLeBundleEstPlusNeuf()
        let corpus = DiskCorpusRepository(socle: BundleCorpusRepository(bundle: source))
        daily = BundleDailyVerseRepository()
        let glossary = DiskGlossaryRepository()
        self.corpusSurDisque = corpus
        self.lexiqueSurDisque = glossary
        self.shemotSurDisque = BundleShemotRepository()
        let index = BundleSearchIndex()
        let store = FileReaderStore()
        // Un fichier à part : le profil se supprime avec le compte, les
        // réglages de lecture survivent à une déconnexion.
        let profils = FileProfilStore()

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
        // **iOS seulement.** Voir `CorpusRefresh` : le Mac n'a pas de
        // `BGTaskScheduler`, et la mise à jour à l'ouverture — juste en
        // dessous, et commune aux deux — lui suffit.
        #if os(iOS)
            // Le consentement aux parutions sans inscription au serveur est
            // un silence : on redemande un jeton. Voir `PushDistant`.
            PushDistant.reprendreSiBesoin()

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
        #endif

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
            profils: profils,
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
    /// **Fait lire à la liseuse un corpus d'aperçu, ou la ramène au publié.**
    ///
    /// Le mode développeur du Mac reconstruit depuis le vault et écrit à côté
    /// du corpus publié — dans `Application Support/vault-apercu`, jamais dans
    /// `dist/` : un aperçu de brouillon n'a rien à faire dans un arbre de
    /// travail git.
    ///
    /// Il l'écrivait déjà. **Personne ne le lisait.** Le dossier des dépôts
    /// était fixé à la construction, et la boucle que le README décrit —
    /// « on désigne le vault, il surveille, il reconstruit, l'app recharge » —
    /// s'arrêtait avant son dernier mot.
    ///
    /// Le défaut se cachait derrière un nombre juste : le bandeau affichait le
    /// compte que le pipeline venait de rendre, sur un corpus que la liseuse
    /// n'ouvrait pas. L'auteur l'a pris en cherchant le **chapitre** plutôt que
    /// le compte.
    ///
    /// `nil` ramène au corpus publié — c'est ce que fait « Cesser de suivre ».
    func regarderLApercu(_ dossier: URL?) {
        let cible = dossier ?? CorpusUpdater.dossierParDefaut()
        corpusSurDisque.regarder(cible)
        lexiqueSurDisque.regarder(cible)
        reading.corpusChanged()
        lexicon.glossaryChanged()
    }

}
