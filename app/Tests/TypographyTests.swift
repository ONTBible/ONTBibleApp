import ONTDesignSystem
import ONTKit
import SwiftUI
import Testing
import UIKit

/// Les fontes embarquées.
///
/// Une fonte absente d'`UIAppFonts` ne fait rien planter : iOS retombe
/// silencieusement sur la fonte système, et on ne s'en aperçoit qu'en
/// comparant deux captures d'écran. Ces tests sont là pour que l'oubli soit
/// bruyant.
struct TypographyTests {
    @Test("les sept fontes proposées répondent toutes", arguments: ReadingFont.allCases)
    func everyOfferedFont(_ font: ReadingFont) {
        // Sept entrées dans un réglage, sept fontes qui doivent exister. Une
        // seule absente et le lecteur choisit un nom qui ne change rien.
        #expect(ONTFonts.isAvailable(font), "\(font.label) ne répond pas")
    }

    @Test("l'hébreu a sa fonte")
    func hebrewFace() {
        #expect(ONTFonts.hebrewAvailable)
    }

    @Test("chaque famille embarquée a ses trois coupes", arguments: ReadingFont.allCases)
    func threeFaces(_ font: ReadingFont) throws {
        // Georgia mise à part : c'est le système qui la fournit, on ne
        // contrôle pas ses fichiers.
        guard font != .georgia else { return }
        for coupe in ["Regular", "Italic", "SemiBold"] {
            let court = ONTFonts.family(font).replacingOccurrences(of: " ", with: "")
            let nom = "\(court)-\(coupe)"
            let fonte = try #require(UIFont(name: nom, size: 20), "\(nom) absente")
            // La famille doit être commune aux trois, sinon iOS les voit comme
            // trois inconnues et `.italic()` retombe sur une pente simulée.
            #expect(fonte.familyName == ONTFonts.family(font), "\(nom) → \(fonte.familyName)")
        }
    }

    @Test("l'italique est une vraie coupe, pas une pente simulée")
    func realItalic() throws {
        // Le piège : si seule la romaine est embarquée, la famille se résout
        // quand même et le moteur incline les glyphes à la main. Le texte
        // reste lisible, donc rien ne signale l'erreur — sauf l'angle, qui
        // est nul dans une fausse italique parce qu'aucune coupe italique
        // n'a été trouvée.
        let italique = try #require(UIFont(name: "Literata-Italic", size: 20))
        #expect(italique.fontDescriptor.symbolicTraits.contains(.traitItalic))
        #expect(italique.familyName == "Literata")
    }

    @Test("le défaut est bien la fonte par défaut")
    func defaultFont() {
        #expect(ReadingPreferences.default.bodyFont == .literata)
        #expect(ONTFonts.body == ONTFonts.family(.literata))
    }

    @Test("un réglage enregistré avant l'arrivée du champ se relit")
    func decodesLegacyPreferences() throws {
        // Le champ `bodyFont` est arrivé après la première version. Un lecteur
        // qui avait déjà réglé sa taille ne doit pas tout perdre au décodage.
        let ancien = Data(#"{"showGloss":false,"showLevel3":true,"textSize":22,"lineSpacing":0.7,"theme":"dark"}"#.utf8)
        let lu = try JSONDecoder().decode(ReadingPreferences.self, from: ancien)
        #expect(lu.bodyFont == .literata)
        #expect(lu.textSize == 22)
        #expect(lu.showGloss == false)
        #expect(lu.theme == .dark)
    }

    // MARK: - La sélection

    private func makeVerse() throws -> Verse {
        // `Verse` n'expose pas d'initialiseur : on passe par le décodage, ce
        // qui a l'avantage d'éprouver aussi le format que produit le pipeline.
        try JSONDecoder().decode(
            Verse.self,
            from: Data(#"{"n":1,"nodes":[{"t":"text","v":"Quand Elohim commença"}]}"#.utf8)
        )
    }

    @Test("un verset sélectionné porte le pointillé")
    func selectionUnderlines() throws {
        let verse = try makeVerse()
        let theme = ONTTheme()
        let composed = ONTTextRenderer.compose(verse: verse, theme: theme, underlined: true)

        let styles = composed.runs.compactMap(\.underlineStyle)
        #expect(!styles.isEmpty, "aucun soulignement posé")
        // Un trait plein serait le soulignement d'un lien, pas la marque de
        // sélection : c'est le motif en pointillé qui distingue les deux.
        #expect(styles.allSatisfy { $0 != .single }, "le trait doit être en pointillé")
    }

    @Test("un verset non sélectionné n'a rien sous le texte")
    func noUnderlineByDefault() throws {
        let verse = try makeVerse()
        let composed = ONTTextRenderer.compose(verse: verse, theme: ONTTheme())

        #expect(composed.runs.allSatisfy { $0.underlineStyle == nil })
    }

    @Test("le numéro de verset reste hors du pointillé")
    func numberIsNotUnderlined() throws {
        // Il est en exposant : souligné, son trait flotterait au-dessus de
        // celui de la ligne.
        let verse = try makeVerse()
        let composed = ONTTextRenderer.compose(verse: verse, theme: ONTTheme(), underlined: true)

        let premier = try #require(composed.runs.first)
        #expect(premier.underlineStyle == nil)
    }

    @Test("les chiffres du corps sont alignés, pas elzéviriens")
    func liningFigures() throws {
        // La raison du changement de fonte. En Georgia les chiffres sont
        // elzéviriens : le « 3 » et le « 9 » descendent sous la ligne de
        // base, le « 1 » monte à la hauteur d'x. Sur un texte qui affiche un
        // numéro tous les trente mots, ça se voit.
        //
        // Le critère n'est pas l'égalité stricte : une ronde déborde toujours
        // un peu au-delà d'une plate, c'est une correction optique et non un
        // défaut. Un chiffre elzévirien, lui, descend d'environ un cinquième
        // du corps — deux ordres de grandeur au-dessus du débord.
        let corps: CGFloat = 100
        let fonte = CTFontCreateWithName("Literata-Regular" as CFString, corps, nil)

        var caracteres = Array("0123456789".utf16)
        var glyphes = [CGGlyph](repeating: 0, count: caracteres.count)
        #expect(CTFontGetGlyphsForCharacters(fonte, &caracteres, &glyphes, caracteres.count))

        var boites = [CGRect](repeating: .zero, count: glyphes.count)
        CTFontGetBoundingRectsForGlyphs(fonte, .horizontal, &glyphes, &boites, glyphes.count)

        let sommets = boites.map(\.maxY)
        let ecart = try #require(sommets.max()) - (try #require(sommets.min()))
        #expect(ecart < corps * 0.05, "sommets relevés : \(sommets)")

        let plusBas = try #require(boites.map(\.minY).min())
        #expect(plusBas > -corps * 0.05, "le plus bas descend à \(plusBas)")
    }
}

/// Les images embarquées.
struct AssetTests {
    @Test("la montagne du logo est dans le bundle")
    func mountainIsBundled() {
        // Elle a manqué une fois : `Image(_:bundle:)` ne cherche que dans un
        // catalogue d'assets, et SwiftPM s'était contenté de copier le PNG à
        // côté. Rien ne plantait, la place restait vide.
        #expect(ONTMountain.isAvailable)
    }
}

/// Le troisième niveau de marquage — le terme important.
struct ImportantTermTests {
    private func nodes(_ json: String) throws -> [Inline] {
        try JSONDecoder().decode([Inline].self, from: Data(json.utf8))
    }

    @Test("un terme important se décode")
    func decodes() throws {
        let n = try nodes(#"[{"t":"important","children":[{"t":"text","v":"« Jour »"}]}]"#)
        guard case .important(let enfants) = n.first else {
            Issue.record("nœud non reconnu : \(String(describing: n.first))")
            return
        }
        #expect(enfants.count == 1)
    }

    @Test("il porte le violet, et pas l'or")
    func wearsViolet() throws {
        let n = try nodes(#"[{"t":"important","children":[{"t":"text","v":"Sarah"}]}]"#)
        let theme = ONTTheme()
        let composed = ONTTextRenderer.compose(n, theme: theme)

        let couleurs = composed.runs.compactMap(\.foregroundColor)
        #expect(couleurs.contains(ONTColors.important(theme.mode)))
        #expect(!couleurs.contains(ONTColors.accent(theme.mode)), "l'or est réservé aux intraduisibles")
    }

    @Test("il ne se touche pas")
    func hasNoLink() throws {
        // Le cœur de la distinction : un intraduisible ouvre une fiche, un
        // terme important n'en a pas. Un mot qui répond au doigt sans rien
        // avoir à dire est pire qu'un mot qui ne répond pas.
        let n = try nodes(#"[{"t":"important","children":[{"t":"text","v":"« Nuit »"}]}]"#)
        let composed = ONTTextRenderer.compose(n, theme: ONTTheme())
        #expect(composed.runs.allSatisfy { $0.link == nil })
    }

    @Test("un intraduisible, lui, se touche toujours")
    func termStillLinks() throws {
        let n = try nodes(#"[{"t":"term","v":"Elohim","lemma":"elohim"}]"#)
        let composed = ONTTextRenderer.compose(n, theme: ONTTheme())
        #expect(composed.runs.contains { $0.link != nil })
    }

    @Test("il survit à l'extinction des niveaux")
    func survivesLevelToggles() throws {
        // Il appartient au corps, pas à l'appareil critique : éteindre les
        // gloses ne doit pas l'emporter.
        let n = try nodes(#"[{"t":"important","children":[{"t":"text","v":"« Terre »"}]}]"#)
        var prefs = ReadingPreferences.default
        prefs.showGloss = false
        prefs.showLevel3 = false
        let composed = ONTTextRenderer.compose(n, theme: ONTTheme(preferences: prefs))
        #expect(String(composed.characters).contains("Terre"))
    }
}
