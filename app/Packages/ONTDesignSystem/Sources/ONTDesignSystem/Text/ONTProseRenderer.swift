import ONTKit
import SwiftUI

/// Le numéro de verset, porté par les **glyphes** et non par le texte.
///
/// C'est la pièce qui permet tout le reste : au moment du dessin, chaque
/// fragment sait de quel verset il vient, sans qu'on ait eu à réécrire quoi que
/// ce soit dans la chaîne composée.
/// La marque du **numéro** de verset.
///
/// Elle ne porte aucune valeur : sa seule présence dit « ce fragment est un
/// numéro, ne le souligne pas ». Le numéro est en exposant, et un pointillé
/// tracé sous la ligne ne le rejoint pas — il faisait un décroché à chaque
/// début de verset.
public struct ONTNumeroDeVerset: TextAttribute {
    public init() {}
}

public struct ONTVerseAttribute: TextAttribute {
    public let n: Int
    public init(n: Int) { self.n = n }
}

/// Le rendu d'un bloc de prose — estompage et désignation, au **dessin**.
///
/// ## Le problème qu'il résout
///
/// En prose continue, un bloc est une section entière dans un seul `Text`.
/// Désigner un verset y changeait deux choses dans la chaîne composée : un
/// soulignement sur le verset choisi, une couleur plus pâle sur les autres.
/// Aucune des deux ne déplace un glyphe — mais SwiftUI n'a aucun moyen de le
/// savoir. Une chaîne différente, c'est une **mise en page** différente, et il
/// refaisait donc celle de toute la section à chaque appui. Mesuré :
///
///     un seul verset, ce que refait le mode blocs      0,9 ms
///     un bloc de prose de trente versets              31,3 ms
///
/// Trente-cinq fois le coût, par construction, et le doigt le sentait.
///
/// ## Ce qu'il fait à la place
///
/// La chaîne composée ne parle plus de sélection du tout : elle est **stable**
/// tant que le texte et les surlignages ne bougent pas. La mise en page a donc
/// lieu une fois. Ce moteur reçoit la sélection et repeint — il baisse
/// l'opacité de ce qui n'est pas désigné, et trace le pointillé sous ce qui
/// l'est. Changer de sélection ne coûte plus qu'un dessin.
public struct ONTProseRenderer: TextRenderer, Equatable {
    /// Les versets désignés **de ce bloc**.
    private let selection: Set<Int>
    /// Vrai dès qu'une sélection existe, ici ou dans un autre bloc — c'est ce
    /// qui fait qu'un bloc entier s'efface quand on désigne ailleurs.
    private let uneSelectionExiste: Bool
    private let estompe: Double
    private let trait: Color
    /// Le corps du texte, qui donne l'échelle du pointillé.
    private let corps: CGFloat

    public init(
        selection: Set<Int>,
        uneSelectionExiste: Bool,
        estompe: Double,
        trait: Color,
        corps: CGFloat
    ) {
        self.selection = selection
        self.uneSelectionExiste = uneSelectionExiste
        self.estompe = estompe
        self.trait = trait
        self.corps = corps
    }

    public func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for ligne in layout {
            for piece in ligne {
                let numero = piece[ONTVerseAttribute.self]?.n
                let designe = numero.map(selection.contains) ?? false

                // Une copie du contexte par fragment : `opacity` s'applique à
                // tout ce qu'on dessine ensuite, et il ne faut pas qu'elle
                // déborde sur le fragment suivant.
                var couche = context
                if uneSelectionExiste && !designe {
                    couche.opacity = estompe
                }
                couche.draw(piece)

                // Le numéro est désigné comme le reste — il s'affiche donc à
                // pleine encre — mais il n'est pas souligné.
                if designe, piece[ONTNumeroDeVerset.self] == nil {
                    souligner(piece, sous: ligne, dans: &context)
                }
            }
        }
    }

    /// Le pointillé de désignation.
    ///
    /// Tracé plutôt que posé en attribut, pour la même raison que le reste :
    /// un `underlineStyle` dans la chaîne la ferait changer, donc remettre en
    /// page. Il suit les retours à la ligne sans effort, puisqu'on le trace
    /// fragment par fragment et qu'un fragment ne franchit jamais une ligne.
    ///
    /// **Proportionnel au corps**, et non en points fixes. Le premier jet
    /// traçait un trait d'un point avec des tirets d'un demi : invisible, et
    /// d'autant plus que le lecteur monte sa taille de texte — c'est-à-dire
    /// exactement quand il a besoin de voir ce qu'il a désigné.
    private func souligner(
        _ piece: Text.Layout.Run,
        sous ligne: Text.Layout.Line,
        dans context: inout GraphicsContext
    ) {
        let bornes = piece.typographicBounds
        let epaisseur = max(2, corps * 0.15)
        // La hauteur vient de la **ligne**, pas du fragment.
        //
        // Chaque fragment porte les métriques de sa fonte, et un verset en
        // mêle plusieurs : le corps, l'italique de la translittération,
        // l'hébreu. Pris fragment par fragment, le pointillé montait et
        // descendait au fil du balisage — il plongeait sous l'hébreu et
        // remontait après, ce qui se lit comme un défaut et non comme un trait.
        //
        // La ligne, elle, n'a qu'une assise. Le pointillé la suit et reste
        // droit d'un bout à l'autre, quoi que le verset contienne.
        let assise = ligne.typographicBounds
        let hauteur = assise.rect.maxY - assise.descent * 0.1
        var chemin = Path()
        chemin.move(to: CGPoint(x: bornes.rect.minX, y: hauteur))
        chemin.addLine(to: CGPoint(x: bornes.rect.maxX, y: hauteur))
        context.stroke(
            chemin,
            with: .color(trait),
            // Un point rond, un blanc de deux fois sa largeur : à moins, le
            // pointillé se lit comme un trait plein.
            style: StrokeStyle(
                lineWidth: epaisseur,
                lineCap: .round,
                dash: [0.01, epaisseur * 1.9]
            )
        )
    }
}
