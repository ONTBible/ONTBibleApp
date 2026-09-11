import ONTKit
import SwiftUI

/// **L'alerte du renvoi vers un livre non traduit — une définition, deux racines.**
///
/// Elle vivait écrite dans `RootView`, et seulement là : `RacineMac` ne liait
/// pas `livreIndisponible`, donc sur le Mac un renvoi vers un livre absent
/// posait la valeur et **rien ne s'affichait**. Le clic se lisait comme une
/// panne — l'échec silencieux, dans sa forme la plus littérale.
///
/// C'est le motif du 26 août, à l'identique : une règle recopiée — ou ici,
/// écrite dans une seule des deux vues qui la doivent — est une règle qu'un
/// écran finit par ne pas appliquer. Le remède est le même : elle vit ici,
/// une fois, et les deux racines l'appellent.
///
/// Une alerte et non une feuille : il n'y a rien à consulter, rien à faire
/// défiler, rien à comparer au texte. Une feuille promettrait un contenu et
/// n'en aurait pas — c'est exactement l'écueil du texte qui annonce ce qui
/// manque au lieu de l'implémenter.
///
/// `presenting:` plutôt qu'un booléen doublé d'une chaîne : les deux valeurs
/// ne peuvent pas se désynchroniser, et le titre lit le livre qui est
/// réellement présenté.
extension View {
    func alerteDuLivreIndisponible(_ router: Router) -> some View {
        alert(
            "Pas encore traduit",
            isPresented: Binding(
                get: { router.livreIndisponible != nil },
                set: { if !$0 { router.livreIndisponible = nil } }
            ),
            presenting: router.livreIndisponible
        ) { _ in
            Button("Fermer", role: .cancel) {}
        } message: { livre in
            Text(
                livre.isEmpty
                    ? "Ce passage n'est pas encore disponible dans l'ONT."
                    : "\(livre) n'est pas encore traduit. Le renvoi est là, le texte viendra."
            )
        }
    }
}
