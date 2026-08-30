import Foundation
import ONTKit

/// Le profil sur le disque — un petit JSON, et le portrait à côté.
///
/// **Un fichier distinct de `lecteur.json`.** Le profil se supprime avec le
/// compte, là où les réglages de lecture survivent à une déconnexion : les
/// mêlant, on finirait par effacer les deux ou aucun des deux, et l'un des
/// deux comportements serait faux.
///
/// **Le portrait ne vit pas dans le JSON.** Une image encodée en base64 y
/// ferait plusieurs centaines de kilo-octets, relus et réécrits à chaque
/// changement. Le fichier ne garde qu'un nom.
public final class FileProfilStore: ProfilRepository {
    private let dossier: URL
    private let url: URL
    private var etat: Profil

    public init(directory: URL = .applicationSupportDirectory, name: String = "profil.json") {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        dossier = directory
        url = directory.appending(path: name)

        if let ecrit = try? Data(contentsOf: url),
            let lu = try? JSONDecoder().decode(Profil.self, from: ecrit)
        {
            etat = lu
        } else {
            etat = Profil()
        }
    }

    public var profil: Profil {
        get { etat }
        set {
            // **Le portrait qu'on remplace est effacé.** Sans ça, chaque
            // changement de photo laisserait la précédente sur le disque, et
            // l'effacement du compte n'emporterait que la dernière.
            let ancien = etat.portrait
            etat = newValue
            if let ancien, ancien != newValue.portrait {
                try? FileManager.default.removeItem(at: dossier.appending(path: ancien))
            }
            ecrire()
        }
    }

    public func enregistrerLePortrait(_ donnees: Data) throws -> String {
        // Un nom neuf à chaque fois. Réécrire le même ferait garder à l'app la
        // vieille image en cache — `UIImage` retient par URL — et le lecteur
        // verrait son ancienne photo jusqu'au prochain lancement.
        let nom = "portrait-\(UUID().uuidString).jpg"
        try donnees.write(to: dossier.appending(path: nom), options: .atomic)
        return nom
    }

    public func portrait() -> Data? {
        guard let nom = etat.portrait else { return nil }
        return try? Data(contentsOf: dossier.appending(path: nom))
    }

    public func oublier() {
        if let nom = etat.portrait {
            try? FileManager.default.removeItem(at: dossier.appending(path: nom))
        }
        etat = Profil()
        try? FileManager.default.removeItem(at: url)
    }

    private func ecrire() {
        guard let donnees = try? JSONEncoder().encode(etat) else { return }
        try? donnees.write(to: url, options: .atomic)
    }
}
