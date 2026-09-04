import Foundation
import Testing

/// **Ce que le compilateur ne peut pas voir.**
///
/// L'`Info.plist` d'une cible n'est **pas** partagé avec une autre, même quand
/// les deux compilent le même code et portent jusqu'au même identifiant de
/// bundle. La cible du Mac déclarait `ONTWebBaseURL` et le schéma `ont://`, mais
/// ni l'adresse du backend ni les deux identifiants clients d'OAuth.
///
/// ## Pourquoi ça ne s'est pas vu
///
/// `Composition` lit `ONTAPIBaseURL`, retombe sur `""` quand la clé est absente,
/// et de là sur `https://invalide.local` — un hôte qui n'existe pas. Chaque
/// appel rendait donc `cannotFindHost`, que `AccountError.lisible` traduit
/// fidèlement en `.offline`, affiché « Pas de connexion. Vos annotations restent
/// sur cet appareil. »
///
/// **Le message était juste, et sa cause n'avait rien à voir avec le réseau.**
/// Il invitait à réessayer, et réessayer ne pouvait rien donner. Le repli en dur
/// évite un `!` sur une URL, ce qui est bien ; il transforme aussi un oubli de
/// configuration en panne de réseau, ce qui l'est moins. Ces épreuves sont le
/// prix de ce repli.
///
/// `Bundle.main` est ici celui de **l'app** et non du bundle d'épreuves : la
/// cible pose `TEST_HOST` sur « La Bible ONT.app ».
@Suite("La configuration du bundle du Mac")
struct ConfigurationDuBundleTests {
    private func clef(_ nom: String) -> String? {
        (Bundle.main.object(forInfoDictionaryKey: nom) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilSiVide
    }

    @Test(
        "les clés que le compte réclame sont déclarées",
        arguments: ["ONTAPIBaseURL", "ONTWebBaseURL", "ONTGoogleClientID", "ONTGitHubClientID"])
    func lesClefsSontLa(_ nom: String) {
        #expect(
            clef(nom) != nil,
            """
            « \(nom) » manque à l'Info.plist de la cible ONTMac. Rien ne le dira \
            à l'exécution : l'app retombera sur un repli et l'échec se lira comme \
            une panne de réseau. Voir `info:` de la cible ONTMac dans project.yml.
            """)
    }

    /// **Déclarée ne suffit pas : encore faut-il qu'elle mène quelque part.**
    ///
    /// Une clé présente mais vide, ou pointant sur le repli, produirait
    /// exactement le défaut qu'on vient de corriger — et passerait l'épreuve
    /// ci-dessus sans un mot.
    @Test("l'adresse du backend est une adresse, et pas le repli")
    func lAdresseMeneQuelquePart() throws {
        let brut = try #require(clef("ONTAPIBaseURL"), "ONTAPIBaseURL manque")
        let url = try #require(URL(string: brut), "« \(brut) » n'est pas une URL")
        #expect(url.scheme == "https", "le backend doit être en https, pas « \(url.scheme ?? "—") »")
        let hote = try #require(url.host(), "« \(brut) » n'a pas d'hôte")
        #expect(
            hote != "invalide.local",
            "l'adresse est le repli de `Composition` — la clé n'est pas lue")
    }
}

extension String {
    fileprivate var nilSiVide: String? { isEmpty ? nil : self }
}
