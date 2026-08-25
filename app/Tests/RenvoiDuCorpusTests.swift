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
        #expect(router.pendingVerse == 10, "le verset désigné doit être repris")
    }
}
