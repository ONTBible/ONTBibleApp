import Foundation
import ONTKit
import Testing

@testable import ChuqqotFeature

/// Le modèle de l'onglet Chuqqot.
///
/// ## Pourquoi ces épreuves existent, alors que le dépôt est déjà éprouvé
///
/// `ChuqqotSurDisqueTests` garde la **lecture** — que le fichier soit ouvert,
/// traduit et trié. Ici on garde ce que le modèle ajoute, et il n'ajoute qu'une
/// chose : que l'écran **l'apprenne**.
///
/// Ce n'est pas un détail de plomberie. Vider le cache d'un dépôt ne change
/// aucune propriété observée : la vue ne relit rien, et ce qui vient d'arriver
/// sur le disque attend le prochain lancement. Le défaut s'est déjà produit
/// deux fois dans cette app — la table des matières, puis le lexique — et il
/// est invisible depuis le code, parce que tout y est correct.
@MainActor
struct ChuqqotTests {
    /// Un dépôt de papier, dont on peut changer la réponse en cours de route.
    ///
    /// **Une classe et non une `struct`** : le port est `Sendable`, et la
    /// mutation doit être visible depuis la référence que le modèle tient.
    /// `@unchecked` assumé — l'épreuve est sur l'acteur principal de bout en
    /// bout, il n'y a pas de second fil pour concourir.
    private final class DepotDePapier: ChuqqotRepository, @unchecked Sendable {
        var rendu: [Chuqqah]
        /// Combien de fois on est venu lire. C'est ce qui distingue « le modèle
        /// a relu » de « le modèle rend par chance la bonne valeur ».
        private(set) var lectures = 0

        init(_ rendu: [Chuqqah] = []) { self.rendu = rendu }

        func chuqqot() -> [Chuqqah] {
            lectures += 1
            return rendu
        }
    }

    private func chuqqah(_ id: String, rang: Int = 0) -> Chuqqah {
        Chuqqah(id: id, titre: id.uppercased(), rang: rang, blocs: [])
    }

    /// Le modèle lit à la construction — l'écran n'a rien à demander.
    ///
    /// Vue rougir en retirant l'appel à `charger()` de l'`init` :
    /// « (modele.chuqqot.count → 0) == 2 ».
    @Test("le modèle porte les chuqqot dès sa construction")
    func chargementInitial() {
        let depot = DepotDePapier([chuqqah("chuqqot-0-intro"), chuqqah("yhwh-ha-maqom", rang: 9)])
        let modele = ChuqqotModel(depot: depot)

        #expect(modele.chuqqot.count == 2)
        #expect(depot.lectures == 1)
    }

    /// **L'épreuve qui garde le défaut de fond.**
    ///
    /// Une chuqqah validée arrive par le corpus, en cours de route. Le dépôt
    /// oublie son cache ; encore faut-il que quelqu'un le relise et que la vue
    /// l'apprenne. Sans `corpusChanged()`, elle attendrait le prochain
    /// lancement — sur le disque, mais nulle part à l'écran.
    ///
    /// Vue rougir en vidant le corps de `corpusChanged()` :
    /// « (modele.chuqqot.count → 0) == 1 », et `lectures` restait à 1.
    @Test("une chuqqah validée en cours de route atteint l'écran")
    func rechargement() {
        let depot = DepotDePapier()
        let modele = ChuqqotModel(depot: depot)
        #expect(modele.chuqqot.isEmpty)

        depot.rendu = [chuqqah("yhwh-ha-maqom")]
        // Sans le signal, le modèle tient toujours le vide d'avant : c'est le
        // comportement attendu, et c'est ce qui rend la ligne suivante utile.
        #expect(modele.chuqqot.isEmpty)

        modele.corpusChanged()

        #expect(modele.chuqqot.count == 1)
        #expect(depot.lectures == 2)
    }

    /// **Le modèle relaie l'ordre du dépôt, il ne le refait pas.**
    ///
    /// L'ordre de lecture est tenu par `DiskChuqqotRepository`, qui est le seul
    /// endroit où toutes les sources de chuqqot passent. Le retrier ici en
    /// ferait un second endroit où l'ordre se décide, et le jour où les deux
    /// divergeraient, rien ne dirait lequel fait foi.
    ///
    /// Vue rougir en ajoutant un `.sorted { $0.titre < $1.titre }` dans
    /// `charger()` : « (modele.chuqqot.map(\.id) → ["a", "z"]) == ["z", "a"] ».
    @Test("le modèle ne réordonne pas ce que le dépôt lui rend")
    func ordreRelaye() {
        let depot = DepotDePapier([chuqqah("z", rang: 0), chuqqah("a", rang: 1)])
        let modele = ChuqqotModel(depot: depot)

        #expect(modele.chuqqot.map(\.id) == ["z", "a"])
    }
}
