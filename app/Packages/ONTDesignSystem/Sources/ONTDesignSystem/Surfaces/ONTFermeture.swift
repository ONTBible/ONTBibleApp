import SwiftUI

/// Comment une fiche se ferme, quand ce n'est pas le système qui le sait.
///
/// ## Pourquoi `dismiss` ne suffit pas
///
/// `@Environment(\.dismiss)` ferme ce que **SwiftUI** a présenté : une feuille,
/// une fenêtre, un `NavigationStack`. Il ne connaît rien d'un panneau latéral
/// ni d'un aperçu que l'app dessine elle-même en surimpression — appelé depuis
/// là, il ne fait rien, silencieusement.
///
/// C'est ce qui rendait « Fermer » inerte dans l'inspecteur du Mac : le bouton
/// était bien là, il appelait bien `dismiss()`, et rien ne se fermait. Un défaut
/// qu'aucune lecture du code ne signale, puisque le code est juste — il parle
/// simplement à quelqu'un qui n'écoute pas.
///
/// La fiche ne doit pas savoir comment elle est présentée : c'est la
/// présentation qui doit lui dire comment se refermer. Quand personne ne le dit,
/// `dismiss` reste le bon défaut.
private struct ONTFermetureKey: EnvironmentKey {
    static let defaultValue: ONTFermeture? = nil
}

/// Un geste de fermeture, posé par ce qui présente.
///
/// `@unchecked Sendable`, et c'est le seul endroit du projet où on l'écrit :
/// une valeur d'environnement doit être `Sendable` — sa valeur par défaut est
/// une propriété statique —, alors que le geste qu'on y range est une fermeture
/// isolée au fil principal, capturant une vue qui ne l'est pas.
///
/// La garantie ne vient donc pas du compilateur mais du type : `geste` est
/// `@MainActor`, il ne peut être appelé que de là, et rien d'autre n'est
/// accessible depuis cette structure. Le franchissement est réel, la sûreté
/// aussi — elle est simplement portée par la forme du type plutôt que vérifiée.
public struct ONTFermeture: @unchecked Sendable {
    private let geste: @MainActor () -> Void

    public init(_ geste: @escaping @MainActor () -> Void) {
        self.geste = geste
    }

    @MainActor public func callAsFunction() { geste() }
}

extension EnvironmentValues {
    /// Le geste de fermeture imposé par la présentation, s'il y en a un.
    public var ontFermer: ONTFermeture? {
        get { self[ONTFermetureKey.self] }
        set { self[ONTFermetureKey.self] = newValue }
    }
}
