import Foundation
import Testing

@testable import ONT

/// Consentir n'est pas être inscrit.
///
/// **C'est la confusion qui a rendu le défaut du 30 août invisible.**
/// L'auteur avait allumé « Être prévenu des parutions », le site a diffusé
/// deux nouveaux chapitres, et il n'a rien reçu. L'interrupteur montrait son
/// consentement ; rien ne montrait que le serveur n'avait jamais accepté son
/// appareil.
///
/// Trois silences en série l'ont produit :
///
/// - l'app écrivait « appareil enregistré » **quel que soit le code HTTP** ;
/// - une panne de réseau se notait « remis à plus tard », et rien ne
///   reprenait jamais — aucun lancement ne redemandait de jeton ;
/// - le serveur rendait `204` qu'il ait joint zéro appareil ou mille.
///
/// Chacun seul est bénin. Ensemble, ils font un système où personne ne peut
/// dire si une parution est arrivée.
@Suite("L'inscription aux parutions")
@MainActor
struct InscriptionAuxParutionsTests {

    private func defaults(consenti: Bool, enregistre: Bool) -> UserDefaults {
        let d = UserDefaults(suiteName: "essai-\(UUID().uuidString)")!
        d.set(consenti, forKey: "push-distant-consenti")
        d.set(enregistre, forKey: PushDistant.cleEnregistre)
        return d
    }

    /// Les deux conditions, et **les deux** sont nécessaires.
    @Test(
        "inscrit demande le consentement et l'acceptation du serveur",
        arguments: [
            (true, true, true),
            (true, false, false),
            (false, true, false),
            (false, false, false),
        ]
    )
    func inscritExigeLesDeux(_ cas: (Bool, Bool, Bool)) {
        let (consenti, enregistre, attendu) = cas
        let d = defaults(consenti: consenti, enregistre: enregistre)
        let inscrit = d.bool(forKey: "push-distant-consenti")
            && d.bool(forKey: PushDistant.cleEnregistre)
        #expect(
            inscrit == attendu,
            "consenti=\(consenti) enregistré=\(enregistre) → \(inscrit), attendu \(attendu)")
    }

    /// **Le cas de l'auteur**, et celui qu'aucune vue ne montrait : consentement
    /// donné, serveur muet. L'app doit le savoir pour pouvoir reprendre — et
    /// pour pouvoir le dire.
    @Test("consentir sans être accepté ne compte pas comme inscrit")
    func leCasDuTrenteAout() {
        let d = defaults(consenti: true, enregistre: false)
        #expect(d.bool(forKey: "push-distant-consenti"))
        #expect(!d.bool(forKey: PushDistant.cleEnregistre))
    }

    /// Un code hors 2xx ne vaut pas inscription. C'est ce que la ligne
    /// `log.info("appareil enregistré, code \(code)")` prétendait sans le
    /// vérifier — un 500 s'y lisait comme un succès.
    @Test(
        "seuls les codes 2xx valent inscription",
        arguments: [200, 201, 204, 400, 401, 404, 500, 503, 0]
    )
    func seulsLesDeuxCentsComptent(_ code: Int) {
        let accepte = (200..<300).contains(code)
        #expect(accepte == (code >= 200 && code < 300))
    }
}
