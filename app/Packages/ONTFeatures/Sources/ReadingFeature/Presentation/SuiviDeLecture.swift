import SwiftUI

/// Ce que la liseuse sait de l'endroit où le lecteur en est.
///
/// ## Pourquoi une classe, et pourquoi elle n'est pas observable
///
/// Elle est écrite à chaque verset qui entre ou sort de l'écran, c'est-à-dire
/// des dizaines de fois par seconde pendant un défilement. Observable, elle
/// redéclencherait le corps de la liseuse à chaque fois — pour un
/// renseignement dont l'affichage n'a aucun besoin. C'est une ardoise, pas un
/// état de vue.
///
/// ## Le défaut qu'elle corrige
///
/// La position était écrite **directement** au modèle, sur changement de
/// visibilité. Or la visibilité change aussi quand la vue arrive et quand elle
/// part : pendant qu'une unité se retire, sa liste se défait et les lignes du
/// haut se signalent visibles une dernière fois. La position enregistrée
/// redevenait « verset 1 », et le défaut ne se voyait qu'à la visite suivante —
/// la première marchait, la seconde ramenait en haut du chapitre.
///
/// Relevé sur l'appareil, dans `lecteur.json` : `"verse": 1` après une lecture
/// qui s'était arrêtée bien plus bas.
///
/// Deux gardes s'y sont succédé et n'ont pas tenu : éteindre le suivi pendant
/// la restauration, puis l'éteindre aussi à la disparition. Toutes deux
/// supposaient de connaître l'**ordre** dans lequel SwiftUI émet ses
/// événements. On ne le connaît pas, et il n'est pas garanti.
///
/// ## Le signal qu'on écoute désormais
///
/// Non plus « une ligne est apparue », mais « le lecteur a fait défiler, et il
/// s'est arrêté ». Une apparition ni une disparition ne produisent ce
/// signal-là : le défaut disparaît sans qu'on ait à deviner un ordre.
@MainActor
final class SuiviDeLecture {
    /// Les versets présents à l'écran. Le plus petit est celui du haut.
    private var visibles: Set<Int> = []
    /// Vrai dès que le doigt a touché la page.
    private var aDefile = false

    func entre(_ verset: Int) { visibles.insert(verset) }
    func sort(_ verset: Int) { visibles.remove(verset) }
    func defile() { aDefile = true }

    /// Le verset à retenir — `nil` tant que le lecteur n'a rien fait défiler.
    ///
    /// Ouvrir une unité, la lire sans bouger et la quitter ne déplace donc pas
    /// la position : elle reste là où la restauration l'avait posée, ce qui est
    /// exactement ce qu'on veut.
    func aRetenir() -> Int? {
        guard aDefile else { return nil }
        return visibles.min()
    }

    /// À l'ouverture d'une autre unité.
    func recommence() {
        visibles.removeAll()
        aDefile = false
    }
}

private struct SuiviDeLectureKey: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue = SuiviDeLecture()
}

extension EnvironmentValues {
    /// L'ardoise du suivi de lecture.
    ///
    /// Passée par l'environnement pour n'avoir pas à la faire traverser cinq
    /// signatures de vues qui n'en font rien d'autre que la transmettre. Elle
    /// n'est pas observable, donc la lire ne crée aucune dépendance.
    var ontSuivi: SuiviDeLecture {
        get { self[SuiviDeLectureKey.self] }
        set { self[SuiviDeLectureKey.self] = newValue }
    }
}
