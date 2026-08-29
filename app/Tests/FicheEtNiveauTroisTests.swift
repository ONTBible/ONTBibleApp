import ONTDesignSystem
import ONTKit
import Testing

/// Ce qu'une fiche perd quand le lecteur éteint le niveau 3.
///
/// Le réglage vaut pour la **surface de lecture**, où l'hébreu à côté de chaque
/// intraduisible encombrerait le fil. Une fiche est l'endroit où l'on vient
/// précisément pour voir le mot — et son en-tête montre déjà l'hébreu sans
/// condition, pendant que sa prose le perdait. Cent une translittérations et
/// sept passages hébreux, sur cent huit fiches.
@MainActor
struct FicheEtNiveauTroisTests {
    private var noeuds: [Inline] {
        [
            .text("La racine "),
            .translit("chanakh", hebrew: "חָנַךְ"),
            .text(" dit l'inauguration."),
        ]
    }

    private func theme(niveau3: Bool) -> ONTTheme {
        var reglages = ReadingPreferences.default
        reglages.showLevel3 = niveau3
        return ONTTheme(preferences: reglages)
    }

    /// Ce que la surface de lecture fait, et qui est correct **pour elle**.
    @Test("en lecture, le niveau 3 éteint retire l'hébreu")
    func enLecture() {
        let rendu = String(
            ONTTextRenderer.compose(noeuds, theme: theme(niveau3: false)).characters)
        #expect(!rendu.contains("חָנַךְ"))
        #expect(!rendu.contains("chanakh"))
    }

    /// Ce qu'une fiche doit faire, et qu'elle ne faisait pas.
    @Test("dans une fiche, l'hébreu reste même niveau 3 éteint")
    func dansUneFiche() {
        let rendu = String(
            ONTTextRenderer.composeFiche(noeuds, theme: theme(niveau3: false)).characters)
        #expect(rendu.contains("חָנַךְ"), "la fiche a perdu son hébreu : « \(rendu) »")
        #expect(rendu.contains("chanakh"))
    }

    /// Et la glose reste au choix du lecteur : c'est une voix du texte, pas le
    /// sujet de la fiche.
    @Test("la fiche ne force pas la glose")
    func laGloseResteAuChoix() {
        let avecGlose: [Inline] = [.text("le mot "), .gloss([.text("ce qu'il veut dire")])]
        var eteinte = theme(niveau3: false)
        eteinte.preferences.showGloss = false

        let rendu = String(ONTTextRenderer.composeFiche(avecGlose, theme: eteinte).characters)
        #expect(!rendu.contains("ce qu'il veut dire"))
    }
}
