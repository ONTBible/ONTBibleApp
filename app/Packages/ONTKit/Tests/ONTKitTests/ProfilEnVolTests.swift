import Foundation
import Testing

@testable import ONTKit

/// Le profil qui voyage.
///
/// Ce qu'on éprouve ici est la **traduction**, pas le transport : le domaine
/// local dit le portrait par un nom de fichier, le domaine en vol par ses
/// octets, et confondre les deux ferait arriver sur l'autre téléphone une
/// adresse qui ne mène nulle part.
struct ProfilEnVolTests {
    @Test("le portrait part en octets, pas en nom de fichier")
    func lePortraitPartEnOctets() {
        let local = Profil(
            nomDUsage: "gloiiire_", prenom: "Gloire", nom: "Bikouta",
            portrait: "portrait-ABC.jpg")
        let enVol = ProfilEnVol(local, portrait: Data([0xFF, 0xD8]))

        #expect(enVol.portrait == Data([0xFF, 0xD8]))
        #expect(enVol.nomDUsage == "gloiiire_")
    }

    /// Et le retour ne devine **pas** de nom de fichier : c'est le dépôt qui
    /// écrit l'image qui le décide, lui seul sait où.
    @Test("au retour, le nom du fichier vient du dépôt")
    func leRetour() {
        let recu = ProfilEnVol(
            nomDUsage: "gloiiire_", prenom: "Gloire", portrait: Data([1]),
            updatedAt: Date(timeIntervalSince1970: 500))

        let local = recu.versLeProfil(portrait: "portrait-neuf.jpg")
        #expect(local.portrait == "portrait-neuf.jpg")
        #expect(local.updatedAt == Date(timeIntervalSince1970: 500))
    }

    /// **Un profil d'avant l'horodatage doit perdre.**
    ///
    /// `.distantPast` et non « maintenant » : un fichier écrit avant que ce
    /// champ existe gagnerait sinon contre tout ce qui vient du serveur, du
    /// seul fait qu'on vient de le lire.
    @Test("un profil sans horodatage est daté du fond des âges")
    func leProfilSansHorodatage() throws {
        let ancien = try JSONDecoder().decode(
            Profil.self, from: Data(#"{"prenom":"Gloire"}"#.utf8))

        #expect(ancien.updatedAt == .distantPast)
        #expect(Date(timeIntervalSince1970: 0) > ancien.updatedAt)
    }

    /// Le portrait s'écrit en **base64** sur le fil — c'est ce que le serveur
    /// range, et l'écrire à la main serait une occasion de se tromper.
    ///
    /// On lit le champ dans le JSON plutôt que de comparer deux chaînes : le
    /// JSON échappe les barres obliques, et `/9j/` s'y écrit `\/9j\/`. Une
    /// comparaison littérale mesurerait donc l'échappement de `JSONEncoder`,
    /// pas l'encodage du portrait — et rougirait le jour où il changerait
    /// d'avis là-dessus.
    @Test("le portrait s'encode en base64")
    func lEncodage() throws {
        let octets = Data([0xFF, 0xD8, 0xFF])
        let json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(ProfilEnVol(prenom: "G", portrait: octets)))

        let champ = (json as? [String: Any])?["portrait"] as? String
        #expect(champ == octets.base64EncodedString())
        #expect(Data(base64Encoded: champ ?? "") == octets)
    }

    /// Et il revient tel qu'il est parti.
    @Test("l'aller-retour rend les mêmes octets")
    func lAllerRetour() throws {
        let parti = ProfilEnVol(
            nomDUsage: "gloiiire_", prenom: "Gloire", bio: "Traducteur",
            portrait: Data([0xFF, 0xD8, 0xFF, 0xE0]))
        let revenu = try JSONDecoder().decode(
            ProfilEnVol.self, from: try JSONEncoder().encode(parti))

        #expect(revenu == parti)
    }
}
