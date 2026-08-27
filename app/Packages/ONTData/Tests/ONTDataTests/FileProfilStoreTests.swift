import Foundation
import ONTKit
import Testing

@testable import ONTData

/// Le profil sur le disque.
///
/// Ce qu'on éprouve ici, c'est surtout ce qu'on **efface** : un effacement qu'on
/// croit fait est la faute la plus coûteuse de cette couche, parce qu'elle ne se
/// voit jamais — l'écran est vide dans les deux cas.
struct FileProfilStoreTests {
    private func dossierNeuf() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "profil-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("ce qu'on écrit se relit au lancement suivant")
    func laPersistance() throws {
        let dossier = dossierNeuf()
        let premier = FileProfilStore(directory: dossier)
        premier.profil = Profil(prenom: "Gloire", nom: "Bikouta", bio: "Traducteur de l'ONT")

        let second = FileProfilStore(directory: dossier)
        #expect(second.profil.nomAffiche == "Gloire Bikouta")
        #expect(second.profil.bio == "Traducteur de l'ONT")
    }

    @Test("le portrait s'écrit à côté, et se relit")
    func lePortrait() throws {
        let dossier = dossierNeuf()
        let store = FileProfilStore(directory: dossier)
        let nom = try store.enregistrerLePortrait(Data([0xFF, 0xD8, 0xFF]))
        store.profil = Profil(prenom: "G", portrait: nom)

        #expect(FileProfilStore(directory: dossier).portrait() == Data([0xFF, 0xD8, 0xFF]))
        // Et **pas** dans le JSON : une image en base64 y ferait des centaines
        // de kilo-octets relus à chaque changement de réglage.
        let json = try Data(contentsOf: dossier.appending(path: "profil.json"))
        #expect(json.count < 500)
    }

    /// **Changer de photo efface l'ancienne.**
    ///
    /// Sans ça, chaque changement laisserait un fichier derrière lui, et
    /// l'effacement du compte n'emporterait que le dernier — les autres
    /// resteraient sur l'appareil, invisibles et indéfiniment.
    @Test("l'ancien portrait ne reste pas sur le disque")
    func leRemplacement() throws {
        let dossier = dossierNeuf()
        let store = FileProfilStore(directory: dossier)

        let premier = try store.enregistrerLePortrait(Data([1]))
        store.profil = Profil(portrait: premier)
        let second = try store.enregistrerLePortrait(Data([2]))
        store.profil = Profil(portrait: second)

        #expect(!FileManager.default.fileExists(atPath: dossier.appending(path: premier).path()))
        #expect(store.portrait() == Data([2]))
    }

    /// L'effacement du compte doit tout emporter — le fichier **et** l'image.
    @Test("oublier n'oublie rien derrière lui")
    func lOubli() throws {
        let dossier = dossierNeuf()
        let store = FileProfilStore(directory: dossier)
        let nom = try store.enregistrerLePortrait(Data([1, 2, 3]))
        store.profil = Profil(prenom: "Gloire", bio: "quelque chose", portrait: nom)

        store.oublier()

        #expect(store.profil.estVide)
        #expect(store.portrait() == nil)
        #expect(!FileManager.default.fileExists(atPath: dossier.appending(path: nom).path()))
        #expect(!FileManager.default.fileExists(atPath: dossier.appending(path: "profil.json").path()))
        // Et il ne ressuscite pas au lancement suivant.
        #expect(FileProfilStore(directory: dossier).profil.estVide)
    }

    /// Un fichier écrit avant qu'un champ existe se relit sans erreur.
    @Test("un profil d'une version antérieure se relit")
    func leDecodageTolerant() throws {
        let dossier = dossierNeuf()
        try Data(#"{"prenom":"Gloire"}"#.utf8)
            .write(to: dossier.appending(path: "profil.json"))

        let store = FileProfilStore(directory: dossier)
        #expect(store.profil.prenom == "Gloire")
        #expect(store.profil.bio.isEmpty)
    }
}
