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

    // MARK: - Les mouvements nommés après coup
    //
    // **Aucune valeur n'a changé en les nommant**, et c'est la condition du
    // geste : chacune avait été réglée à l'œil sur l'appareil, et les
    // remplacer par un ressort voisin aurait modifié le ressenti sans qu'un
    // seul test rougisse. ==Systématiser, ce n'est pas uniformiser== — c'est
    // donner un nom à ce qui existe, pour qu'on sache où le retrouver.
    //
    // Relevées le 22 septembre 2026, en auditant les valeurs posées hors du
    // design system à la demande de l'auteur.

    /// **La barre d'actions qui se pose** sous le verset désigné.
    ///
    /// Assez court pour suivre le doigt, assez long pour qu'on voie d'où la
    /// barre vient. C'est ce qui restait de délai perçu après que les 54 ms du
    /// chemin eurent été mesurés : l'animation elle-même.
    public static let barreDActions = Animation.snappy(duration: 0.14)

    /// **La carte qu'on relâche** — elle reprend sa place d'où le doigt l'a
    /// laissée.
    public static let retourDeCarte = Animation.spring(response: 0.3, dampingFraction: 0.8)

    /// **Le pli qui s'arme**, sous le doigt, quand le glissement franchit son
    /// seuil. Le plus court de tous : c'est un état, pas un déplacement.
    public static let armementDuPli = Animation.easeOut(duration: 0.09)

    /// **Le pli qui renonce** — le geste n'est pas allé assez loin, la page
    /// revient. Plus amorti que `ressort` : rien n'a abouti, rien ne rebondit.
    public static let renoncementDuPli = Animation.spring(
        response: 0.32, dampingFraction: 0.86)

    /// **La page suivante qui entre**, une fois le pli accompli.
    public static let entreeDePage = Animation.easeOut(duration: 0.20)

    /// **L'aperçu du partage** qui se recompose quand une option change.
    public static let apercuDePartage = Animation.snappy(duration: 0.16)

    /// **L'ouverture de l'app qui se retire** — le seul mouvement long de
    /// l'app, et il n'a lieu qu'une fois par lancement.
    public static let fermetureDeLOuverture = Animation.easeOut(duration: 0.45)

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
