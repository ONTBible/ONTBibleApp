import SwiftUI

/// La marque d'un mot qui ouvre une fiche — terme ou shem.
///
/// Posée par `ONTTextRenderer` sur les runs cliquables. **Une clé
/// d'`AttributedString`, rien de plus** : la première version la faisait aussi
/// `TextAttribute` en espérant qu'elle voyage jusqu'au `Text.Layout` — elle ne
/// voyage pas, et l'épreuve de pixels l'a montré du premier coup : sonde et
/// repos rendaient la même image. Le chemin qui marche est en dessous — des
/// plages de caractères, extraites de la chaîne et passées au rendu comme de
/// simples données.
public struct MarqueDeTerme: AttributedStringKey {
    public typealias Value = Bool
    public static let name = "ONTMarqueDeTerme"
}

extension ONTTextRenderer {
    /// Les plages de caractères marquées comme termes, dans la chaîne **finale**.
    ///
    /// À appeler sur ce qui part réellement dans `Text` — donc **après**
    /// `cesuree(_:)`, qui insère des césures et décale tout : des plages
    /// extraites avant elle voileraient le mot d'à côté.
    public static func plagesDeTermes(_ chaine: AttributedString) -> [Range<Int>] {
        var plages: [Range<Int>] = []
        for run in chaine.runs where run[MarqueDeTerme.self] == true {
            let debut = chaine.characters.distance(
                from: chaine.startIndex, to: run.range.lowerBound)
            let longueur = chaine.characters.distance(
                from: run.range.lowerBound, to: run.range.upperBound)
            plages.append(debut..<(debut + longueur))
        }
        return plages
    }
}

#if os(macOS)

    /// Le voile sous le mot que le curseur touche.
    ///
    /// SwiftUI ne donne aucun survol par mot dans un `Text` — c'est le rendu
    /// lui-même qui le fait : le point du curseur descend dans le
    /// `TextRenderer`, chaque run du layout expose les **indices de
    /// caractères** qu'il dessine, et celui qui recoupe une plage marquée sous
    /// le curseur reçoit son voile. Pas de relayout, pas d'état par mot : du
    /// dessin.
    @available(macOS 15.0, *)
    private struct RenduDeSurvol: TextRenderer {
        let point: CGPoint?
        let plages: [Range<Int>]
        let teinte: Color
        /// Voile **tous** les runs marqués, sans curseur — le mode de
        /// l'épreuve, qui ne peut pas simuler un survol.
        var sonde = false

        func draw(layout: Text.Layout, in contexte: inout GraphicsContext) {
            // `CharacterIndex` est opaque — pas d'`Int` public — mais
            // `Strideable` : le plus petit index du layout **est** le
            // caractère zéro, et `distance(to:)` rend chaque index absolu.
            // Le minimum, et non le premier run : l'hébreu en RTL réordonne
            // les runs visuellement, le premier n'est pas toujours le début.
            let origine = layout
                .flatMap { $0 }
                .flatMap(\.characterIndices)
                .min()
            for ligne in layout {
                for run in ligne {
                    if let origine, estMarque(run, depuis: origine),
                        sonde
                            || point.map({
                                run.typographicBounds.rect.insetBy(dx: -2, dy: -1).contains($0)
                            }) == true
                    {
                        let boite = run.typographicBounds.rect.insetBy(dx: -3, dy: -1)
                        contexte.fill(
                            Path(roundedRect: boite, cornerRadius: 4),
                            with: .color(teinte))
                    }
                    contexte.draw(run)
                }
            }
        }

        private func estMarque(
            _ run: Text.Layout.Run, depuis origine: Text.Layout.CharacterIndex
        ) -> Bool {
            run.characterIndices.contains { indice in
                let absolu = origine.distance(to: indice)
                return plages.contains { $0.contains(absolu) }
            }
        }
    }

    private struct SurvolDesTermes: ViewModifier {
        @Environment(\.ontTheme) private var theme
        @State private var point: CGPoint?
        let plages: [Range<Int>]
        var sonde = false

        @ViewBuilder
        func body(content: Content) -> some View {
            if #available(macOS 15.0, *), !plages.isEmpty {
                content
                    .textRenderer(
                        RenduDeSurvol(
                            point: point, plages: plages,
                            teinte: theme.accent.opacity(0.16), sonde: sonde))
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        switch phase {
                        case .active(let ou): point = ou
                        case .ended: point = nil
                        }
                    }
            } else {
                content
            }
        }
    }

#endif

extension View {
    /// Le survol des intraduisibles, là où le texte est court.
    ///
    /// `texte` est la chaîne **finale** — celle du `Text`, césures comprises :
    /// les plages en sont extraites ici. **Pas sur la prose continue** : chaque
    /// mouvement du curseur redessine le `Text` entier ; sur un verset en bloc
    /// c'est quelques lignes — sur le chapitre d'un seul tenant, ce serait tout
    /// le canon de performance redessiné au pixel de souris.
    ///
    /// `sonde` voile tous les runs marqués sans curseur — **pour l'épreuve
    /// seulement** : elle ne peut pas simuler un survol, et sans elle un
    /// mécanisme mort se lirait comme un survol au repos. Aucun écran ne doit
    /// le passer à vrai.
    @ViewBuilder
    public func ontSurvolDesTermes(_ texte: AttributedString, sonde: Bool = false) -> some View {
        #if os(macOS)
            modifier(
                SurvolDesTermes(plages: ONTTextRenderer.plagesDeTermes(texte), sonde: sonde))
        #else
            self
        #endif
    }
}
