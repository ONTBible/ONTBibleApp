import ONTKit
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// L'image d'un passage, telle qu'elle part dans une conversation.
///
/// ## Ce qu'elle montre, et ce qu'elle tait
///
/// Le **corps de la traduction seul**. Ni gloses, ni translittérations, ni
/// hébreu — l'appareil critique appartient à la liseuse, où il est
/// consultable et attribué. Sorti de là, il devient une affirmation sans
/// recours, illisible pour qui ne connaît pas le projet.
///
/// La carte porte donc le renvoi et le nom de la traduction : une image qui
/// circule doit dire d'où elle vient, sinon elle finit citée de travers.
public struct ONTVerseCard: View {
    /// Le côté du carré, en points. Rendu à l'échelle 1, cela fait 1080 px —
    /// la taille que toutes les messageries acceptent sans recompresser.
    public static let side: CGFloat = 1080

    private let text: AttributedString
    private let reference: String
    private let size: CGFloat
    private let theme: ONTTheme

    public init(text: AttributedString, reference: String, size: CGFloat, theme: ONTTheme) {
        self.text = text
        self.reference = reference
        self.size = size
        self.theme = theme
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            Text(text)
                .lineSpacing(size * 0.42)
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(ONTUI.ligneDeListe)

            Spacer(minLength: 0)

            Rectangle()
                .fill(ONTColors.gold)
                .frame(height: 3)
                .padding(.bottom, 34)

            HStack(alignment: .lastTextBaseline, spacing: 24) {
                Text(reference)
                    .font(.custom(ONTFonts.family(theme.preferences.bodyFont), size: 40))
                    .foregroundStyle(ONTColors.accent(theme.mode))
                Spacer(minLength: 0)
                Text("La Bible ONT")
                    .font(.custom(ONTFonts.display, size: 38))
                    .foregroundStyle(theme.ink.opacity(0.55))
            }
        }
        .padding(90)
        .frame(width: Self.side, height: Self.side)
        .background(theme.background)
    }
}

/// La fabrique d'images de partage.
public enum ONTShareImage {
    /// Le corps décroît quand le passage s'allonge.
    ///
    /// Sans ça, cinq versets débordent du carré et l'image part tronquée. Les
    /// paliers sont grossiers volontairement : une taille calculée au
    /// caractère près donnerait des images qui ne se ressemblent pas d'un
    /// partage à l'autre.
    public static func size(forLength length: Int) -> CGFloat {
        switch length {
        case ..<120: 78
        case ..<260: 62
        case ..<460: 50
        case ..<760: 40
        default: 32
        }
    }

    /// Rend la carte en image.
    ///
    /// `@MainActor` obligé : `ImageRenderer` traverse une hiérarchie SwiftUI,
    /// ce qui n'a de sens que sur le fil principal.
    @MainActor
    public static func render(
        verses: [Verse],
        reference: String,
        theme: ONTTheme
    ) -> ONTImage? {
        // La taille se décide sur le texte nu, avant composition : c'est elle
        // qui fixe le thème avec lequel on compose. L'inverse serait circulaire.
        let plain = verses.map { $0.nodes.plainText() }.joined(separator: " ")
        let corps = size(forLength: plain.count)

        // Un thème à la taille de la carte. `scaledTextSize` porte toute la
        // typographie : les intraduisibles, l'or, l'italique suivent.
        var carte = theme
        carte.scaledTextSize = corps

        // Une seule coulée de texte, versets séparés d'une espace : les numéros
        // hacheraient une citation courte sans rien apporter, puisque le renvoi
        // est déjà en bas de la carte.
        var body = AttributedString()
        for (index, verse) in verses.enumerated() {
            if index > 0 { body += AttributedString(" ") }
            body += ONTTextRenderer.composeBare(verse.nodes, theme: carte)
        }

        let renderer = ImageRenderer(
            content: ONTVerseCard(
                text: body,
                reference: reference,
                size: corps,
                theme: carte
            )
        )
        // 1080 pt × 1 = 1080 px. Rendre à 3× donnerait un fichier de douze
        // mégaoctets que les messageries recompresseraient de toute façon.
        renderer.scale = 1
        renderer.isOpaque = true
        #if canImport(UIKit)
            return renderer.uiImage
        #else
            return renderer.nsImage
        #endif
    }
}
