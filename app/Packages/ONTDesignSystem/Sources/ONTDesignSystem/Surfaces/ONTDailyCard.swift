import ONTKit
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// La carte du verset du jour — bordeaux et or.
///
/// Une seule définition pour deux hôtes : l'onglet Qahal et le widget de
/// l'écran d'accueil. Ils vivent dans des processus différents et n'ont aucun
/// moyen de se parler, donc la seule façon qu'ils se ressemblent est de
/// partager ce code-ci. Deux implémentations « à peu près pareilles »
/// dériveraient à la première retouche.
///
/// Le bordeaux ne suit **pas** l'apparence du système, contrairement au reste
/// de l'app. C'est délibéré : sur un écran d'accueil, une carte qui prend la
/// couleur de l'OS ressemble à toutes les autres. Celle-ci porte les couleurs
/// du logo, et c'est à ça qu'on la reconnaît d'un coup d'œil.
public struct ONTDailyCard<Footer: View>: View {
    /// Les proportions de la carte.
    ///
    /// Trois tailles seulement, et un rapport constant entre elles : le
    /// verset domine, le renvoi le suit à la moitié, l'intitulé s'efface. Une
    /// carte où les trois font la même taille n'a pas de hiérarchie, et l'œil
    /// ne sait pas par où commencer.
    public enum Size {
        case small, medium, large

        var caption: CGFloat { self == .small ? 10 : (self == .medium ? 11 : 13) }
        var body: CGFloat { self == .small ? 14 : (self == .medium ? 16 : 21) }
        var reference: CGFloat { self == .small ? 11 : (self == .medium ? 13 : 15) }
        /// L'interligne **ajouté** — et c'est là qu'est le piège :
        /// `.lineSpacing` ne fixe pas la hauteur de ligne, il s'ajoute à
        /// l'interligne naturel de la fonte, qui vaut déjà environ 1,35 fois
        /// le corps pour Literata.
        ///
        /// Une valeur proportionnelle au corps — 30 % — portait le pas à 1,6
        /// fois le corps : un texte qui flotte. Mesuré sur le widget de
        /// YouVersion, le pas est à 1,37. On n'ajoute donc que deux points,
        /// juste de quoi aérer sans délier.
        var leading: CGFloat { self == .small ? 1 : 2 }
        var gap: CGFloat { self == .small ? 8 : (self == .medium ? 12 : 18) }
        var padding: CGFloat { self == .small ? 4 : 6 }
        /// La montagne est plus haute que le texte de l'intitulé, et il le
        /// faut : à la taille des lettres, ses crêtes de gauche deviennent
        /// une bavure illisible. Vérifié à l'échelle réelle — 10 pt donne une
        /// bouillie, 14 pt est limite, 18 pt tient.
        var mark: CGFloat { self == .small ? 16 : (self == .medium ? 18 : 21) }
    }

    private let text: AttributedString
    private let reference: String
    private let size: Size
    private let footer: Footer

    public init(
        text: AttributedString,
        reference: String,
        size: Size,
        @ViewBuilder footer: () -> Footer = { EmptyView() }
    ) {
        self.text = text
        self.reference = reference
        self.size = size
        self.footer = footer()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: size.gap) {
            HStack(spacing: 7) {
                ONTMountain(height: size.mark)
                // En capitales, avec l'interlettrage qui va avec : sans lui,
                // des capitales se collent et se lisent moins bien qu'un
                // bas-de-casse. Essayé sans, puis avec un seul « J » — les
                // capitales tiennent mieux la ligne à côté de la montagne, qui
                // est un dessin et non un caractère.
                Text("Verset du jour")
                    .font(.system(size: size.caption, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(ONTColors.gold)

            Text(text)
                .lineSpacing(size.leading)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Le renvoi est **gras**, pas italique : c'est une étiquette qu'on
            // repère, pas une citation dans une citation.
            Text(reference)
                .font(.system(size: size.reference, weight: .semibold))
                .foregroundStyle(ONTColors.gold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            footer
        }
        .padding(size.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Le bouton de partage, en pastille — celui de YouVersion.
///
/// Un `Link` et non un `Button` : dans un widget, seul un lien crée une cible
/// tactile distincte du reste de la carte. Un bouton demanderait un `AppIntent`,
/// qui ne sait pas présenter une feuille de partage.
///
/// ## Un aplat translucide, et non un or plein
///
/// En mode teinté — le fond translucide de l'écran d'accueil — iOS ne conserve
/// que la **luminance** : le clair devient opaque, le sombre transparent. Une
/// pastille or pleine portant un texte bordeaux se réduisait donc à un aplat
/// blanc muet, le texte disparaissant dans son propre bouton.
///
/// Le remède n'est pas de traiter les deux modes séparément, mais de cesser
/// de reposer sur du sombre-sur-clair : un voile d'or à faible opacité,
/// surmonté d'un texte d'or plein. Le texte reste l'élément le plus clair
/// dans les deux rendus, donc toujours lisible — et il n'y a plus qu'une
/// seule écriture à tenir.
public struct ONTDailySharePill: View {
    private let destination: URL
    private let size: CGFloat

    public init(destination: URL, size: CGFloat = 14) {
        self.destination = destination
        self.size = size
    }

    public var body: some View {
        Link(destination: destination) {
            Text("Partager")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(ONTColors.gold)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(ONTColors.gold.opacity(0.18)))
                .contentShape(.capsule)
        }
    }
}

extension ONTDailyCard where Footer == AnyView {
    /// La carte telle que la compose un widget.
    ///
    /// Le texte y arrive déjà mis en forme : un widget n'a pas d'arbre
    /// d'inline à sa disposition, seulement le vivier plat.
    public static func widget(verse: DailyVerse, size: Size) -> some View {
        var texte = AttributedString(verse.text)
        texte.font = .custom(ONTFonts.body, size: size.body)
        texte.foregroundColor = ONTColors.gold

        // Pas de pastille sur le petit carré : elle mangerait deux lignes de
        // verset sur les quatre disponibles. Toucher la carte suffit.
        let partage: URL? = size == .small
            ? nil
            : URL(string: "ont://share/\(verse.bookId)/\(verse.chapterId)?v=\(verse.verse)")

        return ONTDailyCard(text: texte, reference: verse.reference, size: size) {
            AnyView(
                Group {
                    if let partage {
                        ONTDailySharePill(destination: partage, size: size.reference)
                    }
                }
            )
        }
    }
}


/// La montagne du logo.
///
/// En mode gabarit plutôt qu'avec sa couleur d'origine : elle prend ainsi la
/// teinte de son hôte. Elle est or sur le bordeaux de la carte, mais rien
/// n'oblige à ce qu'elle le reste ailleurs.
///
/// Elle vit dans un **catalogue d'assets** du paquet, et pas en fichier posé à
/// côté. `Image(_:bundle:)` ne sait chercher que dans un catalogue : un PNG
/// simplement copié par SwiftPM ne se trouve pas, et l'échec est silencieux —
/// rien ne plante, la place reste vide. C'est ce qui est arrivé la première
/// fois, et c'est pourquoi `isAvailable` existe.
public struct ONTMountain: View {
    private let height: CGFloat

    public init(height: CGFloat) {
        self.height = height
    }

    /// Vrai si la montagne est bien dans le bundle du paquet.
    ///
    /// Même garde que pour les fontes : une ressource absente ne fait rien
    /// planter, elle laisse un trou que personne ne remarque avant de
    /// comparer deux captures d'écran.
    public static var isAvailable: Bool {
        #if canImport(UIKit)
        UIImage(named: "montagne", in: .module, with: nil) != nil
        #else
        true
        #endif
    }

    public var body: some View {
        Image("montagne", bundle: .module)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
            .accessibilityHidden(true)
    }
}
