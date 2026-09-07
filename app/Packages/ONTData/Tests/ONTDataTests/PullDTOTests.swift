import Foundation
import Testing

@testable import ONTData

/// Le décodage d'un `GET /sync` venu d'un serveur **plus ancien que l'app**.
///
/// ## Pourquoi ce cas n'est pas théorique
///
/// La moitié app d'un changement voyage `dev → staging → main` ; le backend
/// n'est déployé que par un push sur `main`. Entre deux promotions, une app
/// livrée aux testeurs interroge donc un serveur en retard sur elle — et rien
/// ne le lui dit, `/health` ne rendant que `ok`.
///
/// Avec des champs obligatoires, une clé absente faisait **lever tout le
/// décodage**, et l'échec était muet : le `catch` de `synchronise()` le rangeait
/// en remontée, l'interface ne montrait rien. La synchronisation cessait
/// entièrement pour un champ que ce serveur-là ne connaissait pas encore.
@Suite("La réponse d'un serveur plus ancien")
struct PullDTOTests {

    private func decode(_ json: String) throws -> PullDTO {
        try JSONDecoder.ontTest.decode(PullDTO.self, from: Data(json.utf8))
    }

    /// Le cas nominal, pour que le reste ait un point de comparaison.
    @Test("une réponse complète se décode")
    func complete() throws {
        let dto = try decode(
            #"{"highlights":[],"position":null,"server_time":1756108800123}"#
        )
        #expect(dto.highlights?.isEmpty == true)
        #expect(dto.server_time_ou_nil == 1_756_108_800_123)
    }

    /// **Le cas qui compte.** Un serveur qui ne connaît pas encore
    /// `server_time` ne doit pas faire échouer la synchronisation entière.
    @Test("un serveur sans server_time ne fait pas échouer le décodage")
    func sansServerTime() throws {
        let dto = try decode(#"{"highlights":[],"position":null}"#)
        #expect(dto.server_time_ou_nil == nil)
    }

    /// Une liste absente veut dire « rien reçu », **jamais** « tout effacé » —
    /// et c'est vrai ici parce que le `pull` fusionne au lieu de remplacer.
    @Test("une réponse sans highlights se décode, et ne dit rien de plus")
    func sansHighlights() throws {
        let dto = try decode(#"{"position":null,"server_time":1}"#)
        #expect(dto.highlights == nil)
    }

    /// Le corps le plus pauvre qu'un serveur puisse rendre.
    @Test("un objet vide se décode encore")
    func objetVide() throws {
        let dto = try decode("{}")
        #expect(dto.highlights == nil)
        #expect(dto.position == nil)
    }

    /// Et dans l'autre sens : un serveur **plus récent** que l'app, qui ajoute
    /// un champ qu'elle ne connaît pas. C'est le cas après une promotion vers
    /// `main`, quand le backend part avant la prochaine version de l'app.
    @Test("un champ inconnu est ignoré, pas fatal")
    func champInconnu() throws {
        let dto = try decode(
            #"{"highlights":[],"server_time":1,"venu_du_futur":{"quoi":"?"}}"#
        )
        #expect(dto.highlights?.isEmpty == true)
    }
}

extension PullDTO {
    /// `serverTime` traverse `convertFromSnakeCase` ; ce détour évite de le
    /// réécrire dans chaque attente.
    fileprivate var server_time_ou_nil: Int64? { serverTime }
}

extension JSONDecoder {
    /// Le même décodeur que `APIClient`, qui est `internal` à son type.
    fileprivate static var ontTest: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
