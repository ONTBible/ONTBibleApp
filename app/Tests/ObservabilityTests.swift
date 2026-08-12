import Foundation
import ONTData
import Testing

@testable import ONT

/// L'expurgation avant envoi à Sentry.
///
/// Ces tests gardent un équilibre qui se dérègle facilement dans les deux
/// sens : trop laxiste, une note de lecteur part sur un serveur tiers ; trop
/// zélé, il ne reste plus rien d'exploitable — la première version remplaçait
/// « ressource introuvable : data/corpus.json » par
/// « ressource introuvable : <chemin> », soit un diagnostic sans diagnostic.
struct ObservabilityTests {
    // MARK: - Ce qui doit disparaître

    @Test("un chemin absolu est masqué — il porte l'UUID du conteneur")
    func absolutePath() {
        let out = Observability.redact(
            "Échec d'écriture /Users/x/Library/Containers/ABC/lecteur.json"
        )
        #expect(out.contains("<chemin>"))
        #expect(!out.contains("/Users/"))
    }

    @Test("un identifiant de conteneur est masqué")
    func containerIdentifier() {
        let out = Observability.redact("Container 0882524D-8C94-4154-A872-164E79702E0E absent")
        #expect(out.contains("<chemin>"))
        #expect(!out.contains("0882524D"))
    }

    @Test("une note de lecteur citée est masquée")
    func quotedNote() {
        // Le cas qui compte : une note révèle une réflexion religieuse —
        // catégorie particulière au sens de l'article 9 du RGPD.
        let out = Observability.redact(
            "Note trop longue : « je médite sur ce verset depuis des semaines »"
        )
        #expect(out.contains("<texte>"))
        #expect(!out.contains("médite"))
    }

    @Test("un texte cité entre guillemets droits est masqué aussi")
    func straightQuotes() {
        let out = Observability.redact("valeur inattendue \"ce passage me bouleverse\"")
        #expect(!out.contains("bouleverse"))
    }

    // MARK: - Ce qui doit survivre

    @Test("un nom de ressource du bundle est conservé")
    func bundleResource() {
        // `data/corpus.json` est une ressource à nous : elle ne révèle rien
        // du lecteur, et c'est la seule information utile du message.
        let out = Observability.redact("Ressource introuvable dans le bundle : data/corpus.json")
        #expect(out.contains("data/corpus.json"))
    }

    @Test("le vrai message d'erreur du chargeur reste lisible")
    func realLoaderMessage() {
        // Régression : ce message est parti deux fois vers Sentry réduit à
        // « <chemin> » puis « missing(<texte>) » — un diagnostic sans
        // diagnostic. Il doit nommer la ressource manquante.
        let error = BundleLoader.Failure.missing("data/corpus.json")
        let out = Observability.redact(error.localizedDescription)

        #expect(out.contains("data/corpus.json"))
        #expect(!out.contains("<texte>"))
        #expect(!out.contains("<chemin>"))
    }

    @Test("un message ordinaire passe intact")
    func plainMessage() {
        let message = "Verset 19 hors limites pour bereshit-18"
        #expect(Observability.redact(message) == message)
    }

    @Test("une citation courte survit — ce n'est pas une note")
    func shortQuote() {
        let out = Observability.redact("clé « tov » inconnue")
        #expect(out.contains("tov"))
    }

    @Test("un identifiant cité survit, même long — il n'a pas d'espace")
    func quotedIdentifier() {
        // C'est le cas qui a échoué trois fois : Sentry capture la
        // description Swift de l'énumération, `missing("data/corpus.json")`,
        // dont la valeur est entre guillemets droits.
        let out = Observability.redact(#"missing("data/corpus.json") (Code: 0)"#)
        #expect(out.contains("data/corpus.json"))
        #expect(!out.contains("<texte>"))
    }

    @Test("de la prose citée est masquée, même sans être très longue")
    func quotedProse() {
        let out = Observability.redact(#"valeur "ce verset me parle" refusée"#)
        #expect(!out.contains("verset me parle"))
    }
}
