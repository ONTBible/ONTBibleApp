import Foundation
import ONTKit
import Observation

/// Ce que le Mac règle, tenu à un seul endroit.
///
/// ## Pourquoi une référence partagée, et non un `@State` de l'`App`
///
/// **Les fermetures de `.commands` ne voient pas la même instance que la
/// fenêtre.** SwiftUI reconstruit la structure `App` ; le menu capture alors un
/// exemplaire dont les `@State` ne sont pas raccordés à ceux qui rendent la
/// scène. L'action part — le menu clignote —, la valeur change dans un objet
/// que personne n'affiche, et rien ne bouge à l'écran.
///
/// C'est exactement le symptôme rapporté : « je vois le menu clignoter mais
/// l'app n'est pas impactée ». Un défaut de câblage, pas de logique — et
/// invisible à la compilation.
///
/// Une référence unique le supprime : quelle que soit l'instance d'`App` que le
/// menu a capturée, elle mène au même objet que la fenêtre observe.
@Observable
@MainActor
final class EtatMac {
    /// L'exemplaire que la fenêtre et le menu partagent.
    static let partage = EtatMac()

    /// Le montage des dépôts — le même que sur iOS.
    let composition = Composition()

    /// La taille de l'interface, en crans de `TaillesAuClavier.interface`.
    ///
    /// Gardée d'une session à l'autre, à la main plutôt que par `@AppStorage` :
    /// celui-ci est un enveloppeur de propriété, donc il vit dans une structure
    /// de vue et souffre du même défaut de câblage que le reste.
    var tailleInterface: Int {
        didSet { UserDefaults.standard.set(tailleInterface, forKey: Self.cle) }
    }

    private static let cle = "tailleDeLInterface"

    private init() {
        let garde = UserDefaults.standard.object(forKey: Self.cle) as? Int
        tailleInterface = garde ?? TaillesAuClavier.interfaceParDefaut
    }

    // MARK: - Les gestes du clavier

    /// L'interface, d'un cran.
    func interface(de pas: Int) {
        tailleInterface = TaillesAuClavier.interfaceDeplacee(tailleInterface, de: pas)
    }

    /// L'interface, à la taille du système.
    func interfaceParDefaut() {
        tailleInterface = TaillesAuClavier.interfaceParDefaut
    }

    /// Le corps du texte, d'un cran — **le même réglage que le curseur**.
    ///
    /// `preferences.textSize` et pas une valeur parallèle : le raccourci doit
    /// bouger le curseur, sinon les deux divergent et le lecteur voit un
    /// curseur qui ment sur ce qu'il lit.
    func corps(de pas: Double) {
        composition.reading.preferences.textSize = TaillesAuClavier.corpsDeplace(
            composition.reading.preferences.textSize, de: pas)
    }

    /// Le thème suivant, en boucle.
    func themeSuivant() {
        let ordre = ReadingTheme.allCases
        guard let i = ordre.firstIndex(of: composition.reading.preferences.theme) else { return }
        composition.reading.preferences.theme = ordre[(i + 1) % ordre.count]
    }
}
