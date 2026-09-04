#if os(macOS)
    import AppKit
#endif
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
            // Le trackpad marque l'enfoncement — le doigt sent ce que l'œil
            // voit céder.
            .onChange(of: configuration.isPressed) { _, presse in
                if presse { ONTHaptique.tic() }
            }
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

// MARK: - La carte de ligne

/// La rangée du Mac — une carte qui survole et s'enfonce, pas une ligne de
/// tableau.
///
/// C'est la forme choisie par l'auteur pour la refonte (3 septembre 2026) :
/// « cartes par ligne » plutôt que groupes arrondis — celle des deux qui porte
/// la micro-animation, chaque rangée répondant pour elle-même. Sur iOS, le
/// modificateur ne fait rien : la `List` du système a déjà sa voix.
///
/// À poser sur le **label** d'un bouton de rangée ; `ontLigneNue()` se pose sur
/// la rangée elle-même pour éteindre la chrome de `List` que la carte remplace.
public struct ONTCarteDeLigne: ViewModifier {
    @Environment(\.ontTheme) private var theme
    private var espace = ONTSpacing()

    public func body(content: Content) -> some View {
        #if os(macOS)
            content
                .padding(.horizontal, espace.m)
                .padding(.vertical, espace.s + 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface, in: .rect(cornerRadius: 12))
                .ontSurvol(dans: RoundedRectangle(cornerRadius: 12))
                // De bord à bord — le vide entre le libellé et le compte
                // répond comme le reste. C'est la leçon du sommaire.
                .contentShape(.rect(cornerRadius: 12))
        #else
            content
        #endif
    }
}

/// Éteint la chrome de `List` autour d'une rangée-carte du Mac.
public struct ONTLigneNue: ViewModifier {
    private var espace = ONTSpacing()

    public func body(content: Content) -> some View {
        #if os(macOS)
            content
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 3, leading: espace.m, bottom: 3, trailing: espace.m))
        #else
            content
        #endif
    }
}

extension View {
    public func ontCarteDeLigne() -> some View { modifier(ONTCarteDeLigne()) }
    public func ontLigneNue() -> some View { modifier(ONTLigneNue()) }

    /// La rangée d'une liste de cartes — nue sur le Mac, `ontRow` sur iOS.
    ///
    /// Un seul appel, parce que les empiler ne marche pas : deux
    /// `listRowBackground` posés sur la même rangée, c'est **l'intérieur** qui
    /// gagne — mesuré sur capture, le `clear` extérieur n'éteignait pas la
    /// surface d'`ontRow`, et les cartes se noyaient dans un bloc.
    @ViewBuilder
    public func ontLigneDeCarte() -> some View {
        #if os(macOS)
            modifier(ONTLigneNue())
        #else
            ontRow()
        #endif
    }
}

extension View {
    /// La liste qui porte des cartes de ligne.
    ///
    /// Sur le Mac, le style groupé peint ses blocs de section derrière les
    /// cartes, qui s'y noient — mesuré sur capture : les rangées se lisaient
    /// comme avant, en plus espacé. `.plain` retire le décor du système et
    /// laisse chaque carte porter sa propre surface. Sur iOS, le style groupé
    /// reste ce que la plateforme attend.
    public func ontListeDeCartes() -> some View {
        #if os(macOS)
            return listStyle(.plain)
        #else
            return listStyle(ONTPlacement.listeGroupee)
        #endif
    }
}

// MARK: - Les haptiques de l'interface

/// Le trackpad répond — trois crans, comme le glissement de page en a déjà.
///
/// `ChapterSwipe` porte les siens depuis le premier jour (armement, tourne,
/// renoncement) ; le reste de l'interface était muet, et l'auteur l'a redit :
/// « ajoute aussi des haptic feedback ». Trois gestes nommés, pour ne plus
/// choisir un motif à chaque appel :
///
/// - `tic()` — un bouton pressé, une case cochée ;
/// - `cran()` — un pli qui s'ouvre, un segment qui change : quelque chose
///   s'est aligné ;
/// - `palier()` — une carte qui s'ouvre ou se ferme : on a changé d'étage.
///
/// Sur iOS le fichier ne fait rien : le système y donne déjà ses retours, et
/// les doubler ferait vibrer deux fois.
public enum ONTHaptique {
    #if os(macOS)
        @MainActor
        public static func tic() {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }

        @MainActor
        public static func cran() {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }

        @MainActor
        public static func palier() {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    #else
        @MainActor public static func tic() {}
        @MainActor public static func cran() {}
        @MainActor public static func palier() {}
    #endif
}

// MARK: - Le verre liquide

extension View {
    /// Le verre du système sur un élément de chrome — et rien sur le texte.
    ///
    /// Sur macOS 26 c'est le vrai verre (`glassEffect`), avec son bord qui
    /// prend la lumière ; en dessous, la matière fine du système fait le même
    /// office sans le lensing. Sur iOS, rien : la plateforme pose déjà le sien
    /// là où il va.
    ///
    /// Réservé à ce qui **flotte au-dessus du contenu** — pastille, segments,
    /// poignées. Du verre sous un paragraphe, c'est un texte qui nage.
    @ViewBuilder
    public func ontVerre(dans forme: some Shape) -> some View {
        #if os(macOS)
            if #available(macOS 26.0, *) {
                glassEffect(.regular, in: forme)
            } else {
                background(.ultraThinMaterial, in: forme)
            }
        #else
            self
        #endif
    }
}
