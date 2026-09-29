import Foundation
import Sentry
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


/// **Ce qui part, et pas seulement ce qu'on expurge.**
///
/// Les épreuves d'à côté nourrissent `redact` directement : elles mesurent la
/// qualité de l'expurgation. Aucune ne mesurait son **périmètre**, et c'est là
/// que le défaut vivait — trois champs nommés sur une enveloppe qui en porte
/// une dizaine, et les trois nommés étaient précisément ceux qu'on écrit
/// soi-même, donc les moins exposés.
///
/// `crumb.data` est le plus chargé de tous : le SDK y range les URL réseau et
/// les noms d'écran, sans qu'aucun appelant ne le demande. Il n'était pas
/// touché.
@Suite("L'enveloppe qui part chez Sentry")
struct EnveloppeExpurgeeTests {
    private let citation = "valeur inattendue \"ce passage me bouleverse\""

    private func evenement() -> Event {
        let e = Event(level: .error)
        e.message = SentryMessage(formatted: citation)
        return e
    }

    @Test("le fil d'Ariane porte ses données, et elles sont expurgées")
    func lesDonneesDuFilDAriane() {
        let e = evenement()
        let miette = Breadcrumb(level: .info, category: "app")
        miette.message = citation
        miette.data = ["url": citation, "profond": ["liste": [citation]]]
        e.breadcrumbs = [miette]

        let sorti = Observability.expurger(e)
        let data = sorti.breadcrumbs?.first?.data

        #expect(data?["url"] as? String != citation)
        let profond = data?["profond"] as? [String: Any]
        let liste = profond?["liste"] as? [Any]
        #expect(liste?.first as? String != citation, "le sac imbriqué n'est pas descendu")
    }

    @Test("extra, tags, transaction et empreinte sont expurgés")
    func lesAutresChamps() {
        let e = evenement()
        e.extra = ["note": citation]
        e.tags = ["unite": citation]
        e.transaction = citation
        e.fingerprint = [citation]

        let sorti = Observability.expurger(e)

        #expect(sorti.extra?["note"] as? String != citation)
        #expect(sorti.tags?["unite"] != citation)
        #expect(sorti.transaction != citation)
        #expect(sorti.fingerprint?.first != citation)
    }

    /// **Les clés survivent.** Elles nomment le champ, elles ne le contiennent
    /// pas — et une clé expurgée rendrait le rapport illisible sans rien
    /// protéger de plus.
    @Test("les clés ne sont pas expurgées")
    func lesClesSurvivent() {
        let e = evenement()
        e.extra = ["note": citation]

        #expect(Observability.expurger(e).extra?.keys.contains("note") == true)
    }

    /// Ce qui n'est pas du texte traverse tel quel : le convertir pour le faire
    /// passer par `redact` l'abîmerait sans rien protéger.
    @Test("un nombre traverse intact")
    func unNombreTraverse() {
        let e = evenement()
        e.extra = ["octets": 4192, "actif": true]

        let sorti = Observability.expurger(e)
        #expect(sorti.extra?["octets"] as? Int == 4192)
        #expect(sorti.extra?["actif"] as? Bool == true)
    }
}

/// Qui a le droit de parler à Sentry.
///
/// ## Ce que ces épreuves mesurent, et pourquoi elles ne pouvaient pas exister
/// ## avant
///
/// `start()` lit son monde — `#if DEBUG`, l'environnement du processus — et
/// rien de tout ça ne se pose depuis un test. La décision a donc été sortie
/// dans `doitRemonter(debug:sousXCTest:arguments:)`, qui prend son monde en
/// paramètre.
///
/// **Elles rougissent contre le code d'avant.** Celui-ci ne consultait que
/// `isRunningUnderXCTest` : un build Debug remontait sans condition, et les
/// deux premières épreuves ci-dessous échouaient.
struct RemonteeAutoriseeTests {
    /// Les chaînes sont écrites à la main, et pas lues depuis `portesDeDebug`.
    /// Une épreuve qui lirait la constante mesurerait la constante contre
    /// elle-même — elle resterait verte si on vidait la liste.
    @Test("un build Debug ordinaire ne remonte rien")
    func debugSeTait() {
        #expect(
            Observability.doitRemonter(debug: true, sousXCTest: false, arguments: ["ONT"])
                == false)
    }

    @Test("`-sentry-en-debug` rallume la remontée pour ce lancement")
    func laPorteExplicite() {
        #expect(
            Observability.doitRemonter(
                debug: true, sousXCTest: false, arguments: ["ONT", "-sentry-en-debug"]))
    }

    /// L'épreuve de bout en bout de la chaîne de remontée passe par là : sans
    /// cette porte, `-corpus-absent` lèverait bien son erreur et le tableau de
    /// bord resterait vide, sans que rien échoue.
    @Test("`-corpus-absent` rallume la remontée — sinon il n'éprouve plus rien")
    func laPorteDeLEpreuve() {
        #expect(
            Observability.doitRemonter(
                debug: true, sousXCTest: false, arguments: ["ONT", "-corpus-absent"]))
    }

    @Test("un build Release remonte, sans avoir besoin d'argument")
    func releaseRemonte() {
        #expect(Observability.doitRemonter(debug: false, sousXCTest: false, arguments: ["ONT"]))
    }

    /// XCTest l'emporte sur tout : la cible de test est hébergée par l'app,
    /// donc `Bundle.main` porte le vrai DSN.
    @Test("sous XCTest, aucune porte ne rouvre la remontée")
    func xctestFermeToutesLesPortes() {
        for argument in ["-corpus-absent", "-sentry-en-debug"] {
            #expect(
                Observability.doitRemonter(
                    debug: true, sousXCTest: true, arguments: ["ONT", argument]) == false)
            #expect(
                Observability.doitRemonter(
                    debug: false, sousXCTest: true, arguments: ["ONT", argument]) == false)
        }
    }

    /// Un argument voisin ne doit pas ouvrir : la comparaison est exacte, pas
    /// un préfixe.
    @Test("un argument qui ressemble à une porte n'en est pas une")
    func pasDeCorrespondanceApproximative() {
        #expect(
            Observability.doitRemonter(
                debug: true, sousXCTest: false, arguments: ["ONT", "-sentry-en-debug-verbeux"])
                == false)
    }
}
