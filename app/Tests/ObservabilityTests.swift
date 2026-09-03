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

    // MARK: - L'apostrophe, et l'espace de typographie

    /// **Le défaut le plus grave qu'ait porté cette fonction.**
    ///
    /// `'` figurait dans la classe des délimiteurs. En français elle est dans
    /// un mot sur cinq : celle de `m'` fermait donc la citation, le début
    /// partait, et **la fin passait en clair** — « a bouleversé hier soir »
    /// en dit plus long que « ce passage m ».
    ///
    /// Ce n'est pas une expurgation absente, c'est une expurgation qui garde
    /// précisément ce qu'elle devait cacher, sous l'apparence d'avoir agi.
    /// Trouvé par la session Android en portant cette fonction en Kotlin.
    @Test("une note contenant une apostrophe part en entier")
    func apostropheDansLaNote() {
        let out = Observability.redact("échec « ce passage m'a bouleversé hier soir »")
        #expect(out == "échec <texte>")
        #expect(!out.contains("bouleversé"))
        #expect(!out.contains("hier soir"))
    }

    /// Plusieurs apostrophes, et une élision en tête — la forme la plus
    /// courante d'une note écrite en français.
    @Test("plusieurs apostrophes ne rouvrent pas la citation")
    func plusieursApostrophes() {
        let out = Observability.redact("échec « l'endroit qu'il n'avait pas relu »")
        #expect(out == "échec <texte>")
        #expect(!out.contains("relu"))
    }

    /// L'autre sens, et il coûte le diagnostic.
    ///
    /// Le français encadre `« … »` d'espaces insécables. Le critère « douze
    /// signes **et une espace** » était donc satisfait par la typographie
    /// seule : une clé qui ne révèle rien se faisait expurger, et le message
    /// ne disait plus quelle clé manquait.
    ///
    /// C'est le même défaut que celui déjà corrigé pour `data/corpus.json`,
    /// revenu par une autre porte.
    @Test("une clé entre guillemets français garde son nom")
    func cleEntreGuillemetsFrancais() {
        let out = Observability.redact("clé « bereshit-1-verset-30 » absente")
        #expect(out.contains("bereshit-1-verset-30"))
        #expect(!out.contains("<texte>"))
    }

    /// L'espace doit séparer **deux signes**. Une espace de bordure appartient
    /// aux guillemets, pas à la citation.
    @Test("une espace de bordure ne fait pas une phrase")
    func espaceDeBordure() {
        #expect(Observability.redact("clé \" data-corpus-json \" absente")
            .contains("data-corpus-json"))
    }

    /// Et la garde tient toujours dans l'autre sens : une vraie phrase entre
    /// guillemets droits disparaît.
    @Test("une phrase entre guillemets droits disparaît encore")
    func phraseEntreGuillemetsDroits() {
        let out = Observability.redact("échec \"la note que j'avais écrite hier\"")
        #expect(out == "échec <texte>")
    }
}

