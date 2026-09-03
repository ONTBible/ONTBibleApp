import SwiftUI

// MARK: - Les états d'interaction

/// Ce qui se presse s'enfonce, ce qui se survole se teinte.
///
/// ## Le constat qui a créé ce fichier
///
/// Le 3 septembre 2026, il n'existait **aucun état de pression** dans toute
/// l'app du Mac : vingt-quatre `buttonStyle(.plain)`, et un clic qui ne
/// répondait rien entre l'enfoncement et l'action. Les survols, quand ils
/// existaient, étaient des aplats posés d'un coup. L'auteur — designer — a
/// demandé la micro-animation *partout*, « limite trop » ; c'est lui qui dira
/// trop.

/// Le style de tout ce qui se presse — l'échelle cède, l'encre se voile,
/// le ressort ramène.
///
/// `.plain` avec un corps : SwiftUI ne donne l'état de pression qu'à un
/// `ButtonStyle`, il n'y a pas d'`onPress` à poser après coup. D'où un style
/// et non un modificateur.
public struct ONTPresse: ButtonStyle {
    /// L'enfoncement. 0,97 pour une case ou une pastille ; une grande ligne
    /// bouge moins (0,985) — à sa taille, 3 % seraient une embardée.
    var echelle: CGFloat = 0.97

    public init(echelle: CGFloat = 0.97) { self.echelle = echelle }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? echelle : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(ONTMouvement.ressortVif, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == ONTPresse {
    /// Le raccourci du cas courant : `Button { … }.buttonStyle(.ontPresse)`.
    public static var ontPresse: ONTPresse { ONTPresse() }

    /// Pour une ligne large, qui s'enfonce à peine.
    public static var ontLigne: ONTPresse { ONTPresse(echelle: 0.985) }
}

/// Le survol d'une surface cliquable — le voile du thème, au ressort vif.
///
/// À poser sur le **contenu** d'une ligne ou d'une carte, avec la forme qui
/// est la sienne : le voile épouse la capsule ou le coin arrondi, il ne
/// déborde pas en rectangle.
public struct ONTSurvol: ViewModifier {
    let forme: AnyShape
    let souleve: Bool

    @Environment(\.ontTheme) private var theme
    @State private var survole = false

    public func body(content: Content) -> some View {
        content
            .background(survole ? theme.voileSurvol : .clear, in: forme)
            .scaleEffect(souleve && survole ? 1.012 : 1)
            .onHover { survole = $0 }
            .animation(ONTMouvement.ressortVif, value: survole)
    }
}

extension View {
    /// Le voile de survol, dans la forme donnée.
    ///
    /// `souleve` ajoute une levée d'un centième — pour les cartes et les
    /// cases, pas pour les longues lignes, qu'une levée ferait trembler.
    public func ontSurvol(
        dans forme: some Shape = RoundedRectangle(cornerRadius: 12), souleve: Bool = false
    ) -> some View {
        modifier(ONTSurvol(forme: AnyShape(forme), souleve: souleve))
    }
}

// MARK: - L'apparition en cascade

/// Un élément qui arrive un peu après son voisin — l'orchestration de Craft.
///
/// L'élément part huit points plus bas, à peine transparent, et remonte au
/// ressort `pop`, décalé par son indice. Sans mouvement d'entrée, un écran
/// *apparaît* ; avec, il *arrive*.
public struct ONTApparition: ViewModifier {
    let indice: Int

    @State private var visible = false

    public func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 8)
            .onAppear {
                withAnimation(ONTMouvement.cascade(indice)) { visible = true }
            }
    }
}

extension View {
    /// L'élément arrive en cascade, à son rang.
    public func ontApparition(_ indice: Int) -> some View {
        modifier(ONTApparition(indice: indice))
    }
}
