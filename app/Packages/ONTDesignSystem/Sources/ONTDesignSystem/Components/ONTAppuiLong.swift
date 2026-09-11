#if canImport(UIKit)
import SwiftUI
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

    public func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let r = UILongPressGestureRecognizer()
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
        let ou = context.converter.localLocation
        // **Un tour de boucle avant d'agir, et c'est la clé de tout.**
        //
        // Mesuré le 11 septembre 2026, sur l'appareil : poser un état depuis ce
        // rappel ne présentait aucune feuille. Aucune erreur, aucun journal —
        // le silence. Trois corrections plausibles ont échoué avant qu'une
        // sonde ne tranche : ajouter *n'importe quel autre* changement d'état
        // dans le même rappel faisait soudain apparaître la feuille.
        //
        // Ce n'était donc pas le geste, ni la position, ni la profondeur de la
        // vue : c'est que ce rappel arrive **pendant** le traitement du toucher
        // par UIKit, hors du cycle de rendu de SwiftUI. La modification est
        // enregistrée et rien ne la relève ; le second changement ne corrigeait
        // rien, il réveillait le cycle.
        //
        // `Task { @MainActor }` rend la main à la boucle d'exécution, et
        // SwiftUI voit l'état changer dans un cycle à lui. Le point d'appel n'a
        // rien à savoir de tout ça — c'est exactement ce qu'un pont doit
        // absorber.
        Task { @MainActor in action(ou) }
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
        // Le repli ne connaît pas la position : il rend le centre, faute de
        // mieux. Mieux vaut désigner le verset du milieu que ne rien ouvrir.
        return AnyView(
            simultaneousGesture(
                LongPressGesture(minimumDuration: duree, maximumDistance: 60)
                    .onEnded { _ in action(.zero) }
            )
        )
    }
}
