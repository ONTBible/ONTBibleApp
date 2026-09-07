import Foundation
import ONTDesignSystem
import ONTKit
import SwiftUI
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
        didSet {
            UserDefaults.standard.set(tailleInterface, forKey: Self.cle)
            appliquerLEchelle()
        }
    }

    /// Porte le cran choisi jusqu'au design system, qui met les fontes à
    /// l'échelle — voir `ONTEchelleUI`. Le réglage n'a pas d'autre chemin :
    /// `dynamicTypeSize` ne fait rien sur macOS.
    private func appliquerLEchelle() {
        ONTEchelleUI.partage.facteur = TaillesAuClavier.facteur(tailleInterface)
    }

    /// Comment les fiches paraissent — au centre ou sur le côté.
    ///
    /// Gardé, comme le reste : le lecteur choisit une fois, pas à chaque nom
    /// qu'il touche.
    var modeDeFiche: ModeDeFiche {
        didSet { UserDefaults.standard.set(modeDeFiche.rawValue, forKey: Self.cleFiche) }
    }

    /// La largeur du panneau latéral des fiches, quand elles s'ouvrent à côté.
    ///
    /// Réglable à la poignée, gardée d'une session à l'autre : c'est un arbitrage
    /// entre la fiche et le texte, et il n'est pas le même pour un article de
    /// trois lignes et pour un Shem qui en fait trente.
    ///
    /// **Le bornage est dans l'accesseur, pas dans un `didSet`.** Écrit ainsi :
    ///
    ///     var largeur: CGFloat { didSet { largeur = borner(largeur) } }
    ///
    /// il se rappelle lui-même à chaque écriture, et la pile déborde — mesuré,
    /// `EXC_BAD_ACCESS` par récursion, l'app disparaissait au premier tiré de
    /// poignée. Une propriété calculée sur une réserve privée n'a pas ce
    /// défaut : la réserve est écrite une fois, et rien ne se rappelle.
    var largeurDuPanneau: CGFloat {
        get { largeurBrute }
        set {
            largeurBrute = Self.largeurDePanneauValide(newValue)
            UserDefaults.standard.set(Double(largeurBrute), forKey: Self.clePanneau)
        }
    }

    private var largeurBrute: CGFloat

    /// Les bornes du panneau, au même endroit que celles du corps et de
    /// l'interface : une borne écrite deux fois est une borne qui divergera.
    static func largeurDePanneauValide(_ brute: CGFloat) -> CGFloat {
        min(max(brute, 300), 680)
    }

    static let largeurDePanneauParDefaut: CGFloat = 420

    private static let cle = "tailleDeLInterface"
    private static let cleFiche = "modeDeFiche"
    private static let clePanneau = "largeurDuPanneauDeFiche"

    private init() {
        let garde = UserDefaults.standard.object(forKey: Self.cle) as? Int
        tailleInterface = garde ?? TaillesAuClavier.interfaceParDefaut
        let gardeFiche = UserDefaults.standard.string(forKey: Self.cleFiche)
        modeDeFiche = gardeFiche.flatMap(ModeDeFiche.init(rawValue:)) ?? .apercu
        let gardePanneau = UserDefaults.standard.object(forKey: Self.clePanneau) as? Double
        largeurBrute = gardePanneau.map { Self.largeurDePanneauValide(CGFloat($0)) }
            ?? Self.largeurDePanneauParDefaut
        appliquerLEchelle()
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
    /// Une option de lecture, sous forme de liaison, pour le menu.
    ///
    /// **Générique plutôt que cinq propriétés.** Chaque option d'affichage est
    /// un booléen de `ReadingPreferences` ; écrire cinq paires de get/set les
    /// ferait diverger à la première correction, et le menu doit rester le
    /// reflet exact de l'écran de réglages, pas une seconde source.
    ///
    /// Un `Toggle` plutôt qu'un `Button` : le menu montre alors l'état par une
    /// coche. Un raccourci qui bascule sans qu'on puisse voir dans quel sens
    /// oblige à regarder le texte pour savoir ce qu'on vient de faire.
    func option(_ chemin: WritableKeyPath<ReadingPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { self.composition.reading.preferences[keyPath: chemin] },
            set: { self.composition.reading.preferences[keyPath: chemin] = $0 })
    }

    /// La police du corps, l'une après l'autre.
    ///
    /// Parcourue et non choisie, comme le thème : quatre polices ne méritent
    /// pas quatre raccourcis, et l'écran de réglages garde la liste complète
    /// pour qui veut viser.
    func policeSuivante() {
        let ordre = ReadingFont.allCases
        guard let i = ordre.firstIndex(of: composition.reading.preferences.bodyFont) else { return }
        composition.reading.preferences.bodyFont = ordre[(i + 1) % ordre.count]
    }

    func themeSuivant() {
        let ordre = ReadingTheme.allCases
        guard let i = ordre.firstIndex(of: composition.reading.preferences.theme) else { return }
        composition.reading.preferences.theme = ordre[(i + 1) % ordre.count]
    }
}
