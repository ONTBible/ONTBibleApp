import SwiftUI

/// Les ressorts de l'interface — ce que l'iPhone donne d'office et que le Mac
/// n'avait nulle part.
///
/// ## Le constat, sur planche-contact
///
/// Quatorze vues du Mac capturées côte à côte avec l'iPad, le 3 septembre
/// 2026 : tout ce qui bougeait sur le Mac bougeait en `easeOut` de 0,12 à
/// 0,18 s — une rampe qui freine et s'arrête net. Sur l'iPhone, la feuille
/// monte, dépasse d'un rien, se pose ; la barre répond sous le doigt. La même
/// app, deux tempéraments — et c'est le mouvement, plus que les formes, qui
/// faisait dire « rigide ».
///
/// ## Pourquoi des jetons, et pas des valeurs posées sur place
///
/// Un `easeOut(duration:)` écrit dans une vue est une décision que personne ne
/// revoit. Trois ressorts nommés, choisis une fois, font que le prochain écran
/// bouge comme les autres sans y penser — et qu'un changement de tempérament
/// se fait ici, en une ligne, pas en vingt.
///
/// Les amortissements restent au-dessus de 0,7 : en dessous, une liseuse
/// tremble. On veut une étoffe, pas un jouet.
public enum ONTMouvement {
    /// Le ressort courant — état qui change, sélection qui se pose.
    ///
    /// 0,74 d'amortissement : le dépassement se voit. C'est la signature que
    /// l'auteur a choisie le 3 septembre 2026 — « rebond assumé » — contre la
    /// retenue de Craft, proposée et écartée.
    public static let ressort = Animation.spring(response: 0.38, dampingFraction: 0.74)

    /// Le vif — survol, petits témoins, ce qui doit répondre sous le curseur.
    ///
    /// Plus court que `ressort` : un survol qui traîne donne une app qui rame,
    /// c'est la mesure déjà faite sur la barre latérale.
    public static let ressortVif = Animation.spring(response: 0.25, dampingFraction: 0.78)

    /// L'arrivée d'une carte ou d'une feuille — le dépassement se voit, un peu.
    ///
    /// C'est le geste de l'iPhone : la feuille monte légèrement au-delà de sa
    /// place et s'y dépose. L'amortissement à 0,72 est ce « un peu » : à 0,8 le
    /// dépassement disparaît, à 0,6 la carte gigote.
    public static let arrivee = Animation.spring(response: 0.42, dampingFraction: 0.72)

    /// L'apparition d'un petit élément — une case de grille, une pastille.
    ///
    /// Plus détendu encore que `arrivee` : à cette taille, le rebond est ce
    /// qui rend l'élément *vivant* plutôt que posé là.
    public static let pop = Animation.spring(response: 0.32, dampingFraction: 0.66)

    /// La cascade — le même ressort, décalé par l'indice de l'élément.
    ///
    /// C'est l'orchestration de Craft : les éléments d'un écran n'arrivent pas
    /// tous en même temps, ils se suivent de peu. Le pas est court (28 ms) et
    /// **borné** : au-delà du douzième, tout arrive ensemble — une grille de
    /// soixante-dix cases n'a pas à se déplier pendant deux secondes.
    public static func cascade(_ indice: Int, base: Animation = pop) -> Animation {
        base.delay(Double(min(indice, 12)) * 0.028)
    }
}
