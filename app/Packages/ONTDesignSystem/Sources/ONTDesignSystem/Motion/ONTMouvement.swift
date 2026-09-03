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
    public static let ressort = Animation.spring(response: 0.38, dampingFraction: 0.8)

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
}
