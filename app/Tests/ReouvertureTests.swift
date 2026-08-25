import Foundation
import ONTData
import ONTKit
import Testing

/// Ce qu'un lecteur retrouve en rouvrant l'app.
///
/// Le défaut que ces épreuves couvrent ne se voit **ni au mappage ni en
/// mémoire** : tout fonctionne tant que l'app tourne, et la perte n'apparaît
/// qu'à la réouverture. C'est exactement ce qui est arrivé sur Android le
/// 25 août 2026 — le réglage « Le français reçu » se basculait, l'écran
/// suivait, et il disparaissait à la fermeture, parce que le DTO de
/// persistance, écrit à la main, ne portait pas le champ.
///
/// Ici la question est plus large que le réglage : **un fichier écrit par une
/// version antérieure doit se relire sans rien perdre.** C'est la situation de
/// tout lecteur qui met l'app à jour — son fichier ignore ce qu'on vient
/// d'ajouter, et il doit prendre le défaut sans emporter le reste.
@Suite("Fermer et rouvrir")
struct ReouvertureTests {
    private func dossier() -> URL {
        URL.temporaryDirectory.appending(path: UUID().uuidString)
    }

    private func surlignage(verse: Int = 19) -> Highlight {
        Highlight(
            bookId: "bereshit",
            chapterId: "bereshit-18",
            verse: verse,
            color: .gold,
            note: "tsedaqah umishpat"
        )
    }

    /// Écrit un `lecteur.json` à la main, tel qu'une version antérieure
    /// l'aurait laissé, et rend le magasin qui le relit.
    private func magasin(depuis json: String) throws -> FileReaderStore {
        let d = dossier()
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: d.appending(path: "lecteur.json"))
        return FileReaderStore(directory: d, name: "lecteur.json")
    }

    @Test("un réglage basculé survit à la fermeture")
    func preferencesSurviveReopening() {
        let d = dossier()
        var reglages = ReadingPreferences.default
        reglages.french = false
        FileReaderStore(directory: d, name: "lecteur.json").preferences = reglages

        let rouvert = FileReaderStore(directory: d, name: "lecteur.json")
        #expect(rouvert.preferences.french == false, "le registre choisi doit être relu")
    }

    @Test("un surlignage et une position survivent à la fermeture")
    func highlightsAndPositionSurviveReopening() {
        let d = dossier()
        let premier = FileReaderStore(directory: d, name: "lecteur.json")
        premier.save(surlignage())
        premier.remember(
            ReadingPosition(
                bookId: "bereshit",
                chapterId: "bereshit-18",
                chapterTitle: "Bereshit 18",
                verse: 19
            )
        )

        let rouvert = FileReaderStore(directory: d, name: "lecteur.json")
        #expect(rouvert.all().count == 1)
        #expect(rouvert.position?.chapterId == "bereshit-18")
    }

    /// **L'épreuve qui compte.** Un fichier d'avant l'ajout des réglages ne
    /// porte pas la clé `preferences`. S'il ne se relit pas, ce n'est pas un
    /// réglage qui est perdu : ce sont **tous les surlignages du lecteur**,
    /// silencieusement, à la première ouverture de la nouvelle version.
    @Test("un fichier sans la clé des réglages garde ses surlignages")
    func olderFileWithoutPreferencesKeepsHighlights() throws {
        let magasin = try magasin(depuis: """
        {
          "highlights": [{
            "id": "\(UUID().uuidString)",
            "bookId": "bereshit",
            "chapterId": "bereshit-18",
            "verse": 19,
            "color": "gold",
            "updatedAt": 0
          }]
        }
        """)
        #expect(magasin.all().count == 1, "le surlignage d'avant doit survivre")
        #expect(
            magasin.preferences.french == ReadingPreferences.default.french,
            "et les réglages absents doivent prendre leur défaut"
        )
    }

    /// Le pendant de l'épreuve précédente à l'intérieur des réglages : la clé
    /// `french` a été ajoutée le 24 août 2026. Un fichier plus ancien ne la
    /// porte pas, et cela ne doit effacer aucun autre réglage.
    @Test("une clé de réglage absente prend son défaut sans emporter les autres")
    func missingPreferenceKeyFallsBackWithoutLosingSiblings() throws {
        let magasin = try magasin(depuis: """
        {
          "highlights": [],
          "preferences": { "showGloss": false, "textSize": 24.0 }
        }
        """)
        #expect(magasin.preferences.french == ReadingPreferences.default.french)
        #expect(magasin.preferences.showGloss == false, "ce qui était écrit doit rester")
        #expect(magasin.preferences.textSize == 24.0)
    }

    /// Ce qui reste quand le fichier n'est pas seulement d'une autre version,
    /// mais **illisible** — disque plein pendant l'écriture, sauvegarde
    /// tronquée. Repartir vide est le bon comportement ; écraser ensuite
    /// transformerait la lecture ratée en perte définitive.
    @Test("un fichier illisible est mis de côté, pas écrasé")
    func unreadableFileIsSetAsideRatherThanOverwritten() throws {
        let d = dossier()
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let abime = "{ \"highlights\": [ ceci n'est pas du JSON"
        try Data(abime.utf8).write(to: d.appending(path: "lecteur.json"))

        let magasin = FileReaderStore(directory: d, name: "lecteur.json")
        #expect(magasin.all().isEmpty, "l'app doit s'ouvrir plutôt que refuser")

        // Et l'écriture suivante ne doit rien avoir emporté.
        magasin.save(surlignage())
        let ecarte = d.appending(path: "lecteur.illisible.json")
        #expect(
            FileManager.default.fileExists(atPath: ecarte.path),
            "le fichier qu'on n'a pas su lire doit rester récupérable"
        )
        #expect(try String(contentsOf: ecarte, encoding: .utf8) == abime)
    }

    /// L'autre sens : un fichier écrit par une version **plus récente** que
    /// l'app qui le relit. Il arrive à qui rétrograde, et à qui restaure une
    /// sauvegarde. La clé inconnue doit être ignorée, pas fatale.
    @Test("une clé inconnue est ignorée, pas fatale")
    func unknownKeyIsIgnored() throws {
        let magasin = try magasin(depuis: """
        {
          "highlights": [],
          "preferences": { "french": false, "cequonnapasencoreinvente": 7 },
          "cequonnapasencoreinventenonplus": true
        }
        """)
        #expect(magasin.preferences.french == false)
    }
}
