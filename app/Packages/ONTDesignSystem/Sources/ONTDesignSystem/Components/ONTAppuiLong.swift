#if canImport(UIKit)
import SwiftUI
import ONTKit
import UIKit

/// **Un appui long qui survit à une zone défilante.**
///
/// ## Le défaut, et pourquoi le simulateur ne pouvait pas le montrer
///
/// L'auteur : « c'est bizarre, le long press fonctionne sur le sim mais pas
/// sur mon iPhone ».
///
/// `LongPressGesture` de SwiftUI abandonne dès que le doigt s'écarte de
/// `maximumDistance`, qui vaut **10 points** par défaut — lu dans l'interface
/// du SDK. Le simulateur est piloté par un pointeur qui ne bouge pas : le
/// geste y passe toujours. Un doigt tremble, et dans une liste la zone
/// défilante remporte l'arbitrage.
///
/// Le SDK nomme d'ailleurs cette différence : `GestureInputKinds` distingue
/// `directTouch` de `pointer`. **Le simulateur n'est pas un appareil plus
/// petit, c'est un appareil sans main** — et les gestes sont précisément ce
/// qu'il ne sait pas éprouver.
///
/// ## Pourquoi ce pont plutôt qu'une tolérance plus large
///
/// Élargir `maximumDistance` traite le symptôme : le geste reste un
/// concurrent de la zone défilante, et l'un des deux perd. Le forum
/// d'Apple et la communauté convergent sur le même remède, et c'est celui
/// qu'Apple a fini par offrir en iOS 18 — `UIGestureRecognizerRepresentable`,
/// qui fait entrer un vrai reconnaisseur d'UIKit dans l'arbitrage.
///
/// `UILongPressGestureRecognizer` sait de naissance cohabiter avec un
/// `UIScrollView` : il échoue si le défilement démarre vraiment, et gagne
/// sinon. On ne départage plus deux gestes, on laisse le système le faire.
///
/// `cancelsTouchesInView = false` pour que les liens du verset — les
/// intraduisibles, les Shemot, les renvois — gardent leur toucher.
@available(iOS 18.0, *)
public struct ONTAppuiLong: UIGestureRecognizerRepresentable {
    private let duree: TimeInterval
    /// **La position locale de l'appui**, et non seulement le fait qu'il ait
    /// eu lieu.
    ///
    /// En prose continue, les versets coulent dans un seul paragraphe : il n'y
    /// a pas de vue par verset à qui accrocher le geste. Savoir *où* le doigt
    /// s'est posé est la seule façon de savoir *lequel* il désigne.
    private let action: (CGPoint) -> Void

    public init(duree: TimeInterval = 0.4, action: @escaping (CGPoint) -> Void) {
        self.duree = duree
        self.action = action
    }

    /// **Un reconnaisseur qui dit quand le doigt se pose.**
    ///
    /// `.began` d'un appui long n'arrive qu'après sa durée minimale ; il ne
    /// peut donc pas dater le contact. `touchesBegan`, lui, est appelé dès que
    /// UIKit remet le toucher au reconnaisseur — c'est le premier instant que
    /// l'app puisse connaître.
    ///
    /// C'est la balise qui manquait pour savoir si les 146 ms relevées entre
    /// l'appui du banc et `lien-recu` sont dans l'app ou dans le banc.
    private final class ReconnaisseurBalise: UILongPressGestureRecognizer {
        /// **Le retour du contact — la cinquième sensation.**
        ///
        /// Les quatre autres disent ce qui **est arrivé** : on entre en
        /// sélection, on étend, on sort, la feuille se lève. Celle-ci dit
        /// autre chose, et c'est la seule dans ce cas : *« je t'ai senti »*.
        /// Elle répond au doigt avant que l'app sache quoi que ce soit — quatre
        /// dixièmes de seconde pendant lesquels rien ne disait au lecteur que
        /// son appui avait commencé à compter.
        ///
        /// `.soft` et faible, parce qu'elle se déclenche **à chaque contact**
        /// sur le texte, y compris celui qui deviendra un défilement : à cet
        /// instant rien ne distingue les deux, et attendre pour le savoir
        /// reviendrait à ne plus répondre au contact. Une sensation douce
        /// passe alors pour la texture de la page ; une franche serait du
        /// bruit.
        ///
        /// Préparé d'avance : `prepare()` réveille le moteur haptique, sans
        /// quoi la première sensation d'une session arrive avec des dizaines
        /// de millisecondes de retard — exactement là où elle doit être vive.
        private let contact = UIImpactFeedbackGenerator(style: .soft)

        override func reset() {
            super.reset()
            contact.prepare()
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            ONTBalises.instant("doigt-pose")
            contact.impactOccurred(intensity: 0.4)
            super.touchesBegan(touches, with: event)
        }
    }

    public func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let r = ReconnaisseurBalise()
        r.minimumPressDuration = duree
        // La tolérance d'UIKit, et non celle de SwiftUI : elle joue **après**
        // l'arbitrage, pas contre lui.
        r.allowableMovement = 24
        r.cancelsTouchesInView = false
        r.delaysTouchesBegan = false
        r.delaysTouchesEnded = false
        return r
    }

    public func handleUIGestureRecognizerAction(
        _ recognizer: UILongPressGestureRecognizer, context: Context
    ) {
        // **`.began` et non `.ended`.** Un appui long se répond dès qu'il est
        // reconnu : attendre le relèvement ferait patienter le lecteur, doigt
        // posé, sans rien lui dire.
        guard recognizer.state == .began else { return }
        // **On agit tout de suite, dans le rappel.**
        //
        // Le premier jet reportait d'un tour de boucle — `Task { @MainActor }`
        // — au motif que ce rappel arrive hors du cycle de rendu de SwiftUI.
        // Mesuré sur l'appareil : le report **empêche** la feuille de s'ouvrir,
        // là où l'appel immédiat la laisse passer. L'explication était
        // plausible et fausse, et c'est la mesure qui l'a dit.
        action(context.converter.localLocation)

    }
}

#endif

import SwiftUI

extension View {
    /// Pose un appui long qui ne se dispute pas avec le défilement.
    ///
    /// **L'extension vit hors du `#if`**, et il le faut : ce paquet compile
    /// aussi pour macOS, où `canImport(UIKit)` est faux. Enfermée dans le bloc,
    /// la méthode disparaissait pour la moitié des cibles — et la liseuse du
    /// Mac cessait de compiler sur un geste qu'elle n'emploie même pas.
    ///
    /// Là où le pont n'existe pas, on retombe sur le geste de SwiftUI : il
    /// vaut mieux un appui long capricieux que pas d'appui long du tout.
    public func ontAppuiLong(
        duree: TimeInterval = 0.4, action: @escaping (CGPoint) -> Void
    ) -> some View {
        #if canImport(UIKit)
            if #available(iOS 18.0, *) {
                return AnyView(gesture(ONTAppuiLong(duree: duree, action: action)))
            }
        #endif
        return AnyView(modifier(AppuiLongAvecCurseur(duree: duree, action: action)))
    }
}

/// **Le repli, avec la position que la plateforme sait donner.**
///
/// `LongPressGesture` ne rend pas de position — le premier repli rendait
/// `.zero`, et son commentaire disait « le centre ». Deux fois faux : `.zero`
/// est l'origine, et en prose continue `versetA(0)` désignait donc **le
/// premier verset du bloc**, où que l'appui tombe. Un clic maintenu au verset
/// 28 ouvrait la source du verset 1, sans un mot.
///
/// Or le Mac connaît la position mieux qu'UIKit : **le curseur est suivi en
/// continu** — c'est déjà le mécanisme du survol des termes. On la mémorise au
/// passage et on la rend à l'appui. Sur un iPad d'avant iOS 18, le pointeur
/// nourrit le même survol ; au doigt il n'y a pas de survol, et l'on retombe
/// sur `.zero` — l'état d'avant, pas pire que lui.
private struct AppuiLongAvecCurseur: ViewModifier {
    let duree: TimeInterval
    let action: (CGPoint) -> Void
    @State private var curseur: CGPoint = .zero

    func body(content: Content) -> some View {
        content
            .onContinuousHover(coordinateSpace: .local) { phase in
                if case .active(let point) = phase { curseur = point }
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: duree, maximumDistance: 60)
                    .onEnded { _ in action(curseur) }
            )
    }
}
