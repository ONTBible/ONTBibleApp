import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// La fonte des barres de navigation — Jost, comme le site.
///
/// ## Pourquoi ce n'est pas un `.font()` quelque part
///
/// Un titre de navigation n'est pas une vue qu'on peut styler : `.navigationTitle`
/// prend une chaîne, et c'est `UIKit` qui la compose. Le seul point d'entrée
/// est le proxy d'apparence — d'où ce détour, qui n'a pas d'équivalent SwiftUI.
///
/// ## Ce qui est repris du site, et ce qui ne l'est pas
///
/// La webapp emploie **Jost** pour « titres, navigation, capitales » et
/// Literata pour le reste. L'app suivait déjà la seconde moitié de la règle et
/// pas la première : ses barres étaient en fonte système.
///
/// En revanche `ONTFonts.display` reste **Frank Ruhl Libre** — les titres
/// d'unité et les intitulés de section n'y touchent pas. C'est une divergence
/// assumée entre les deux supports, pas un oubli : le site est une vitrine et
/// l'app une liseuse. Changer aussi `display` reviendrait à redessiner chaque
/// page de lecture, ce qui est une autre décision.
///
/// ## Le Dynamic Type, que le proxy ne donne pas
///
/// `UIFont(name:size:)` rend une fonte à taille **fixe** : posée telle quelle
/// dans une apparence, elle ignorerait « Taille du texte ». On la passe donc
/// par `UIFontMetrics`, et on réapplique quand le réglage bouge — le proxy est
/// lu à la construction d'une barre, il ne se remet pas à jour tout seul.
public struct ONTNavigationChrome: ViewModifier {
    @Environment(\.dynamicTypeSize) private var taille

    public init() {}

    public func body(content: Content) -> some View {
        content
            #if canImport(UIKit)
            .onAppear { Self.appliquer() }
            .onChange(of: taille) { _, _ in Self.appliquer() }
            #endif
    }

    #if canImport(UIKit)
    /// Vrai si Jost répond. Même garde que pour les autres fontes : une
    /// ressource absente retombe en silence sur la fonte système, et on ne s'en
    /// aperçoit qu'en comparant deux captures.
    public static var isAvailable: Bool {
        UIFont(name: coupeTitre, size: 17) != nil
    }

    private static let coupeTitre = "Jost-SemiBold"

    private static func appliquer() {
        // Jost absente : on ne pose rien plutôt que d'écraser l'apparence
        // système par une apparence à moitié configurée.
        guard
            let inline = UIFont(name: coupeTitre, size: 17),
            let grand = UIFont(name: coupeTitre, size: 34)
        else { return }

        let titre = UIFontMetrics(forTextStyle: .headline).scaledFont(for: inline)
        let grandTitre = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: grand)

        // La **fonte seulement**. Pas de couleur : celle du système suit déjà
        // le jeu de couleurs que `preferredColorScheme` impose depuis le thème,
        // et la figer ici la ferait diverger à chaque nouveau thème.
        let attributs: [NSAttributedString.Key: Any] = [.font: titre]
        let attributsGrands: [NSAttributedString.Key: Any] = [.font: grandTitre]

        // Les fonds restent **ceux du système**, et c'est le point.
        //
        // Avant ce fichier, l'app ne touchait pas aux barres — vérifié dans le
        // dépôt. Le système en donne deux : opaque et floutée quand le contenu
        // passe dessous, transparente tant qu'on n'a pas défilé. C'est ce flou
        // qui **camoufle** le texte derrière les boutons, et c'est lui qui
        // donne à la lecture son bord haut ouvert.
        //
        // Rendre les trois transparentes supprime le flou : le texte vient
        // alors percuter les boutons au lieu de se fondre. Essayé, et c'était
        // une fausse piste — le contenu qui refusait de monter jusqu'en haut
        // venait d'un `GeometryReader` posé ailleurs, pas d'ici.
        //
        // On ne pose donc que la **fonte**, sur les fonds du système.
        let posee = UINavigationBarAppearance()
        posee.configureWithDefaultBackground()
        posee.titleTextAttributes = attributs
        posee.largeTitleTextAttributes = attributsGrands

        let auBord = UINavigationBarAppearance()
        auBord.configureWithTransparentBackground()
        auBord.titleTextAttributes = attributs
        auBord.largeTitleTextAttributes = attributsGrands

        let barre = UINavigationBar.appearance()
        barre.standardAppearance = posee
        barre.compactAppearance = posee
        barre.scrollEdgeAppearance = auBord

        // Les barres **déjà construites** ne relisent pas le proxy : sans ce
        // rappel, changer la taille du texte ne prendrait effet qu'au prochain
        // écran ouvert, et l'écran courant garderait l'ancienne.
        rafraichirLesBarresVivantes()
    }

    private static func rafraichirLesBarresVivantes() {
        for scene in UIApplication.shared.connectedScenes {
            guard let scene = scene as? UIWindowScene else { continue }
            for fenetre in scene.windows {
                rafraichir(depuis: fenetre)
            }
        }
    }

    private static func rafraichir(depuis vue: UIView) {
        if let barre = vue as? UINavigationBar {
            let proxy = UINavigationBar.appearance()
            barre.standardAppearance = proxy.standardAppearance
            barre.compactAppearance = proxy.compactAppearance
            barre.scrollEdgeAppearance = proxy.scrollEdgeAppearance
        }
        for enfant in vue.subviews { rafraichir(depuis: enfant) }
    }
    #endif
}

extension View {
    /// Pose la fonte des barres de navigation. À appliquer une fois, à la racine.
    public func ontNavigationChrome() -> some View { modifier(ONTNavigationChrome()) }
}
