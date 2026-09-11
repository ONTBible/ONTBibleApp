import Foundation
import ONTKit
import Observation

/// Le modèle de l'onglet **Chuqqot**.
///
/// ## Ce qu'il sait, et tout ce qu'il ne sait pas
///
/// Un seul port : `ChuqqotRepository`. L'onglet n'a aucune raison de pouvoir
/// lire le corpus, le lexique ou le compte, et ne le peut donc pas — c'est la
/// même règle que `LexiconModel`, qui ne connaît que le glossaire.
///
/// Elle se paiera le jour où une chuqqah renverra à un verset : il faudra alors
/// une dépendance, et elle se déclarera. Une dépendance qu'on prend « au cas
/// où » ne se retire jamais, parce que personne ne sait plus si elle sert.
///
/// ## Pourquoi un modèle pour si peu
///
/// Il n'orchestre qu'une lecture, et la vue pourrait appeler le dépôt
/// elle-même. Deux raisons de ne pas le faire, et la seconde est la vraie :
///
/// - **le rechargement**. Une chuqqah validée arrive par le corpus, en cours de
///   route. Vider le cache du dépôt ne change aucune propriété observée : sans
///   un `@Observable` entre les deux, la vue ne relit rien et la chuqqah neuve
///   attend le prochain lancement. C'est le défaut exact qu'ont connu la table
///   des matières et le lexique, deux fois ;
/// - **l'épreuve**. Un modèle se construit sur un dépôt de papier, sans écran,
///   sans simulateur. C'est ce qui permet de vérifier l'ordre de lecture en
///   quelques millisecondes plutôt qu'en montant une hiérarchie de vues.
@MainActor
@Observable
public final class ChuqqotModel {
    private let depot: any ChuqqotRepository

    /// Les chuqqot publiées, **dans l'ordre de lecture**.
    ///
    /// Vide est la réponse normale aujourd'hui : les sept écrites sont en
    /// brouillon, et la garde du pipeline les retient — un énoncé permanent
    /// « en attente de validation » se contredirait lui-même. L'écran le dit
    /// en toutes lettres au lieu de laisser croire à une panne.
    public private(set) var chuqqot: [Chuqqah] = []

    public init(depot: any ChuqqotRepository) {
        self.depot = depot
        charger()
    }

    private func charger() {
        chuqqot = depot.chuqqot()
    }

    /// À appeler quand le corpus sur disque a changé.
    ///
    /// Jumelle de `LexiconModel.glossaryChanged()`, et pour la même raison :
    /// le dépôt a oublié son cache, encore faut-il que quelqu'un le relise et
    /// que la vue l'apprenne.
    public func corpusChanged() {
        charger()
    }
}
