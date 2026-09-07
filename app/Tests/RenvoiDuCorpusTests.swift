import Foundation
import ONTKit
import Testing

/// Le renvoi que le pipeline écrit, ouvert par la liseuse.
///
/// ## Pourquoi ce test vit dans la cible de l'app et non dans `ONTKit`
///
/// `Router.webBase` lit `ONTWebBaseURL` dans `Bundle.main`. Dans les tests du
/// paquet, `Bundle.main` est celui du harnais de test : la clé n'y est pas,
/// `openWeb` refuse, et le test échoue **sans qu'aucun défaut existe**.
///
/// La dépendance est réelle et voulue — la liseuse ne reconnaît le domaine du
/// site que parce que sa configuration le nomme. Le test doit donc s'exécuter
/// là où cette configuration existe. Écrit dans le paquet, il n'éprouvait pas
/// le code : il éprouvait l'absence d'un fichier de configuration.
/// **Sur l'acteur principal**, comme le routeur qu'elle éprouve : `Router`
/// porte l'état de navigation d'une interface, donc il y est isolé. Un test
/// qui l'appellerait d'ailleurs ne compilerait pas — et c'est le compilateur
/// qui a raison.
@MainActor
@Suite("Le renvoi du corpus")
struct RenvoiDuCorpusTests {
    /// **Le maillon qui relie deux chantiers.** Le pipeline résout
    /// « Bereshit 9:27 » vers l'unité neuf, verset interne dix — la
    /// numérotation ONT repart de 1 à chaque unité — et l'écrit en adresse
    /// absolue vers le site, pour qu'une liseuse qui ne sait pas intercepter
    /// ouvre quand même quelque chose d'utile.
    ///
    /// Ici, l'app doit la rattraper : `RootView` renvoie tout `openURL` au
    /// routeur, qui reconnaît son propre domaine et ouvre l'unité **sans
    /// jamais sortir vers Safari**.
    @Test("un renvoi ouvre l'unité au verset, sans passer par Safari")
    func renvoiDuCorpus() {
        let router = Router()
        let url = URL(string: "https://ontbible.com/fr/lire/bereshit/bereshit-9?v=10#v10")!
        #expect(router.open(url), "le routeur doit reconnaître le domaine du site")

        #expect(router.tab == .bible)
        #expect(
            router.biblePath == [
                .book("bereshit"),
                .chapter(book: "bereshit", chapter: "bereshit-9"),
            ]
        )
        #expect(router.pendingVerse?.n == 10, "le verset désigné doit être repris")
    }
}

// ─────────────────────────────────────────────────────────────────────────────

/// **Viser n'est pas désigner**, et la distinction s'était perdue.
///
/// Le widget composait `?v=<n>`, qui désigne le verset ; la carte du verset du
/// jour, dans le Qahal, appelait `open(book:chapter:verse:)`, qui ne fait que
/// viser. Deux gestes identiques à l'écran, deux comportements — l'auteur l'a
/// relevé ainsi : « ça fonctionne depuis le widget, le verset est même
/// sélectionné ».
///
/// La distinction reste voulue : un résultat de recherche amène à un verset
/// sans prétendre que c'est **celui-là** qu'on voulait, puisqu'il en a rendu
/// vingt. Une carte qui montre un seul verset, elle, dit « celui-ci ».
@MainActor
struct ViserOuDesignerTests {
    @Test("Désigner sélectionne le verset")
    func designerLeSelectionne() {
        let router = Router()
        router.designer(book: "bereshit", chapter: "bereshit-1", verse: 20)

        #expect(router.pendingVerse?.n == 20)
        #expect(router.pendingSelection == [20], "le verset doit arriver désigné")
    }

    /// La recherche garde son geste : elle amène sans élire.
    @Test("Viser ne sélectionne rien")
    func viserNeSelectionnePas() {
        let router = Router()
        router.open(book: "bereshit", chapter: "bereshit-1", verse: 20)

        #expect(router.pendingVerse?.n == 20)
        #expect(router.pendingSelection.isEmpty)
    }

    /// Le widget et la carte doivent produire **le même état**, puisqu'ils font
    /// le même geste. C'est cette égalité qui manquait, et rien ne la tenait.
    @Test("La carte du Qahal et le widget mènent au même endroit")
    func lesDeuxPortesSeRejoignent() throws {
        let parLeWidget = Router()
        parLeWidget.open(try #require(URL(string: "ont://read/bereshit/bereshit-1?v=20")))

        let parLaCarte = Router()
        parLaCarte.designer(book: "bereshit", chapter: "bereshit-1", verse: 20)

        #expect(parLeWidget.tab == parLaCarte.tab)
        #expect(parLeWidget.biblePath == parLaCarte.biblePath)
        #expect(parLeWidget.pendingVerse == parLaCarte.pendingVerse)
        #expect(parLeWidget.pendingSelection == parLaCarte.pendingSelection)
    }
}

// ─────────────────────────────────────────────────────────────────────────────

/// **Un verset visé porte son unité**, sinon une vue de lecture mange celui
/// d'une autre.
///
/// Mesuré au simulateur : demander `bereshit-2?v=25` alors que `bereshit-1` est
/// à l'écran, et l'ancienne vue efface le verset avant que la nouvelle ne se
/// monte. Elle ne le trouvait pas chez elle, ne défilait pas — et le remettait
/// quand même à `nil`. On atterrissait sur la bonne unité, en haut.
///
/// Troisième fois de la journée qu'un identifiant local sert là où il en faut un
/// global : après les modes homonymes de deux corpus, et les résultats de
/// recherche. Le remède est le même — porter avec soi ce qui rend unique.
@MainActor
struct VersetViseAvecSonUniteTests {
    @Test("Le verset visé sait de quelle unité il vient")
    func ilPorteSonUnite() throws {
        let router = Router()
        router.open(try #require(URL(string: "ont://read/bereshit/bereshit-2?v=25")))

        let vise = try #require(router.pendingVerse)
        #expect(vise.chapitre == "bereshit-2")
        #expect(vise.n == 25)
    }

    /// Les trois portes qui posent un verset le nomment toutes avec son unité.
    @Test("Les trois portes nomment l'unité")
    func lesTroisPortes() throws {
        let parLaCarte = Router()
        parLaCarte.designer(book: "bereshit", chapter: "bereshit-3", verse: 7)
        #expect(parLaCarte.pendingVerse?.chapitre == "bereshit-3")

        let parLaRecherche = Router()
        parLaRecherche.open(book: "bereshit", chapter: "bereshit-4", verse: 2)
        #expect(parLaRecherche.pendingVerse?.chapitre == "bereshit-4")

        let parLePartage = Router()
        parLePartage.open(try #require(URL(string: "ont://share/bereshit/bereshit-5?v=9")))
        #expect(parLePartage.pendingVerse?.chapitre == "bereshit-5")
    }

    /// Une unité ouverte sans viser de verset n'en invente pas un.
    @Test("Sans verset, rien n'est visé")
    func sansVersetRien() throws {
        let router = Router()
        router.open(try #require(URL(string: "ont://read/bereshit/bereshit-1")))
        #expect(router.pendingVerse == nil)
    }
}
