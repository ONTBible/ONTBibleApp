import OSLog

/// **Les balises du chemin de la sélection**, pour Instruments.
///
/// ## Pourquoi elles existent
///
/// Trois bancs successifs ont buté sur le même plancher, vers 500 ms, et pour
/// la même raison : `XCUITest` ne rend la main qu'une fois l'app **au repos**.
/// Un chronomètre posé dehors mesure donc toujours la fin du mouvement, quel
/// que soit le nom qu'on lui donne — j'ai cru deux fois mesurer le début.
///
/// Une balise, elle, est posée **dans** le chemin. Elle ne demande rien à
/// personne et n'attend aucun repos : elle dit à quel instant l'app est passée
/// là. Quatre balises donnent trois durées, et l'on sait enfin **laquelle**
/// coûte au lieu de déplacer un total qu'on ne sait pas décomposer.
///
/// ## Ce qu'elles coûtent
///
/// Rien tant qu'Instruments n'écoute pas : `OSSignposter` teste
/// `signpostsEnabled` et sort. Elles restent donc dans le code livré, et c'est
/// mieux ainsi — une instrumentation qu'on repose à chaque enquête est une
/// instrumentation qu'on reposera de travers.
///
/// ## Comment lire
///
/// ```text
/// xcrun xctrace record --template 'os_signpost' \
///   --device <udid> --attach ONT --output selection.trace
/// ```
///
/// Puis toucher un verset. Les balises paraissent sous la catégorie
/// `selection-du-verset`, dans l'ordre du chemin :
///
/// ```text
/// lien-recu         le routeur a reconnu ont://verse/<n>
/// selection-posee   l'ensemble des versets désignés a changé
/// composition       la chaîne d'un morceau est refaite   (intervalle)
/// corps-evalue      SwiftUI a réévalué le corps d'un morceau
/// ```
public enum ONTBalises {
    public static let sujet = OSSignposter(
        subsystem: "com.labibleont.ONT", category: "selection-du-verset"
    )

    /// Un instant du chemin — pas une durée.
    public static func instant(_ nom: StaticString) {
        sujet.emitEvent(nom)
    }

    /// Une durée, ouverte et refermée autour du travail.
    public static func durant<T>(_ nom: StaticString, _ travail: () throws -> T) rethrows -> T {
        let etat = sujet.beginInterval(nom)
        defer { sujet.endInterval(nom, etat) }
        return try travail()
    }
}
