import Foundation
import Testing

@testable import ONTKit

/// Un réglage doit survivre à la fermeture.
///
/// # Pourquoi cette épreuve existe
///
/// Le 26 août 2026, « Le français reçu » se basculait sur Android, l'écran
/// suivait, et le réglage **disparaissait à la réouverture** : le DTO de
/// persistance était écrit à la main et n'avait pas le champ.
///
/// iOS n'a pas ce DTO — il encode ``ReadingPreferences`` directement, donc un
/// champ ajouté est enregistré sans qu'on y pense. Mais « sans qu'on y pense »
/// n'est pas « garanti » : un `CodingKeys` explicite, un `encodeIfPresent`
/// oublié, et le même silence reviendrait. La différence entre les deux
/// plateformes ne doit pas être une **confiance**, elle doit être une épreuve.
@Suite("Les réglages survivent")
struct ReglagesQuiSurviventTests {

    /// Chaque réglage, sur des valeurs toutes différentes du défaut.
    @Test("le tour complet conserve chaque réglage")
    func tourComplet() throws {
        let depart = ReadingPreferences(
            showGloss: false,
            showLevel3: false,
            textSize: 27,
            lineSpacing: 0.8,
            theme: .mystique,
            bodyFont: .spectral,
            continuous: false,
            french: false,
            hyphenation: true
        )

        let brut = try JSONEncoder().encode(depart)
        let relu = try JSONDecoder().decode(ReadingPreferences.self, from: brut)

        #expect(relu == depart)
    }

    /// **Le cas du jour** : un réglage neuf, basculé seul.
    @Test("la césure basculée seule tient à la réouverture")
    func cesureSeule() throws {
        var reglages = ReadingPreferences.default
        reglages.hyphenation = true

        let brut = try JSONEncoder().encode(reglages)
        #expect(
            String(data: brut, encoding: .utf8)?.contains("hyphenation") == true,
            "le réglage doit être écrit, pas seulement tenu en mémoire"
        )
        #expect(try JSONDecoder().decode(ReadingPreferences.self, from: brut).hyphenation)
    }

    /// Un fichier écrit **avant** l'arrivée du réglage doit se relire : c'est
    /// le cas de tout lecteur qui met l'app à jour. Il prend le défaut, sans
    /// emporter ses voisins.
    @Test("un fichier d'avant se relit sans rien perdre")
    func fichierDAvant() throws {
        let ancien = #"{"showGloss":false,"textSize":23,"continuous":false}"#
        let relu = try JSONDecoder().decode(
            ReadingPreferences.self,
            from: Data(ancien.utf8)
        )

        #expect(relu.hyphenation == false, "le défaut prend la place de la clé absente")
        #expect(relu.textSize == 23, "et le reste du fichier est conservé")
        #expect(relu.continuous == false)
    }
}
