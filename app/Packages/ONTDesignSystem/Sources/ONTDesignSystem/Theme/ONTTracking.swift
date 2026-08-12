import SwiftUI

/// Le suivi de la position de lecture est-il actif ?
///
/// ## Le piège qu'il désamorce
///
/// Chaque verset affiché enregistre « on en est là ». Or SwiftUI fait
/// apparaître les **enfants avant le parent** : au moment où la vue de lecture
/// cherche où reprendre, les premières lignes ont déjà répondu « verset 1 ».
/// La position à restaurer était donc écrasée avant d'être lue, et la reprise
/// de lecture ramenait toujours en haut du chapitre.
///
/// Le suivi reste éteint jusqu'à ce que la restauration ait eu lieu.
public struct ONTTrackingKey: EnvironmentKey {
    public static let defaultValue = true
}

extension EnvironmentValues {
    public var ontTracking: Bool {
        get { self[ONTTrackingKey.self] }
        set { self[ONTTrackingKey.self] = newValue }
    }
}
