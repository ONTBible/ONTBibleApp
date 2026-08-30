import ONTKit
import SwiftUI
import Testing

@testable import ONTMac

/// Les bornes des deux raccourcis de taille.
///
/// **C'est la seule chose ici qui puisse mentir en silence.** Un raccourci qui
/// dépasse la borne ne casse rien de visible : il continue d'accepter des
/// appuis, la taille ne bouge plus, et l'on croit le raccourci mort plutôt que
/// la valeur saturée. Le reste — brancher un bouton sur une commande — se voit
/// à l'usage dès le premier essai.
@Suite("Les tailles au clavier")
struct TaillesAuClavierTests {

    // MARK: - Le corps du texte

    /// **Les mêmes bornes que le curseur des réglages**, `Slider(in: 11...28)`.
    /// Un raccourci qui atteindrait une valeur que le curseur refuse ferait
    /// mentir le curseur sur ce que le lecteur lit.
    @Test("le corps du texte ne sort pas des bornes du curseur")
    func leCorpsResteDansLesBornes() {
        #expect(TaillesAuClavier.corpsDeplace(28, de: 1) == 28)
        #expect(TaillesAuClavier.corpsDeplace(11, de: -1) == 11)
        #expect(TaillesAuClavier.corps == 11...28)
    }

    @Test("un cran monte et descend d'un point")
    func leCorpsBougeDUnCran() {
        #expect(TaillesAuClavier.corpsDeplace(19, de: 1) == 20)
        #expect(TaillesAuClavier.corpsDeplace(19, de: -1) == 18)
    }

    /// Une valeur venue d'ailleurs — un fichier de préférences écrit par une
    /// version antérieure — est ramenée dans les bornes, pas propagée.
    @Test("une valeur hors bornes est ramenée, pas conservée")
    func lHorsBornesEstRamene() {
        #expect(TaillesAuClavier.corpsDeplace(99, de: 1) == 28)
        #expect(TaillesAuClavier.corpsDeplace(2, de: -1) == 11)
    }

    // MARK: - L'interface

    @Test("l'interface ne sort pas de ses crans")
    func lInterfaceResteDansSesCrans() {
        let dernier = TaillesAuClavier.interface.count - 1
        #expect(TaillesAuClavier.interfaceDeplacee(dernier, de: 1) == dernier)
        #expect(TaillesAuClavier.interfaceDeplacee(0, de: -1) == 0)
    }

    /// **Aucune taille d'accessibilité.** `DynamicTypeSize` en compte cinq de
    /// plus, qui recomposent les vues en colonnes et rendent une barre latérale
    /// inutilisable. Le lecteur qui en a besoin les obtient du système, pour
    /// toutes ses apps ; ce raccourci règle le confort, pas l'accessibilité.
    @Test("les tailles d'accessibilité ne sont pas offertes au raccourci")
    func pasDeTaillesDAccessibilite() {
        #expect(TaillesAuClavier.interface.allSatisfy { !$0.isAccessibilitySize })
    }

    /// Le départ est celui du système, pas le milieu de la liste — un lecteur
    /// qui n'a jamais touché au raccourci doit voir ce que ses autres apps lui
    /// montrent.
    @Test("le départ est la taille du système")
    func leDepartEstCeluiDuSysteme() {
        #expect(TaillesAuClavier.interface[TaillesAuClavier.interfaceParDefaut] == .large)
    }
}

/// Que le geste atteigne bien le réglage que la fenêtre affiche.
///
/// **Le défaut rapporté était là, et aucune épreuve ne le voyait :** « je vois
/// le menu clignoter mais l'app n'est pas impactée ». L'action partait, la
/// valeur changeait — dans un objet que personne n'affichait, parce que les
/// fermetures de `.commands` ne voient pas la même instance d'`App` que la
/// scène.
///
/// Ces épreuves-ci passent par `EtatMac.partage`, l'exemplaire unique, et
/// vérifient qu'un geste laisse une trace là où on ira la lire.
@Suite("Les gestes atteignent le réglage")
@MainActor
struct EtatMacTests {

    @Test("agrandir le texte bouge la préférence que le curseur montre")
    func leCorpsBouge() {
        let etat = EtatMac.partage
        etat.composition.reading.preferences.textSize = 19
        etat.corps(de: 1)
        #expect(etat.composition.reading.preferences.textSize == 20)
        etat.corps(de: -1)
        #expect(etat.composition.reading.preferences.textSize == 19)
    }

    @Test("agrandir l'interface bouge le cran, et s'arrête au bout")
    func lInterfaceBouge() {
        let etat = EtatMac.partage
        etat.interfaceParDefaut()
        let depart = etat.tailleInterface
        etat.interface(de: 1)
        #expect(etat.tailleInterface == depart + 1)
        for _ in 0..<20 { etat.interface(de: 1) }
        #expect(etat.tailleInterface == TaillesAuClavier.interface.count - 1)
        etat.interfaceParDefaut()
    }

    @Test("le thème tourne en boucle et revient")
    func leThemeTourne() {
        let etat = EtatMac.partage
        let depart = etat.composition.reading.preferences.theme
        for _ in ReadingTheme.allCases { etat.themeSuivant() }
        #expect(etat.composition.reading.preferences.theme == depart)
    }
}
