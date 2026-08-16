import LexiconFeature
import ONTDesignSystem
import ONTKit
import QahalFeature
import ReadingFeature
import SearchFeature
import SwiftUI
import YouFeature

/// La racine de l'app.
///
/// Quatre onglets. **Qahal** (קָהָל — l'assemblée) porte la part
/// communautaire ; **Bible** la lecture ; **Lexique** les intraduisibles ;
/// **Vous** le compte.
///
/// La `TabView` d'iOS 26 rend le Liquid Glass nativement — c'est ce qu'on ne
/// pouvait pas obtenir sans passer par SwiftUI.
struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(ReadingModel.self) private var reading
    @Environment(Composition.self) private var composition

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.tab) {
            Tab("Qahal", systemImage: "person.2.fill", value: Router.TabID.qahal) {
                QahalTab()
            }
            Tab("Bible", systemImage: "book.closed.fill", value: Router.TabID.bible) {
                BibleTab { SearchView() }
            }
            Tab("Lexique", systemImage: "character.book.closed.fill", value: Router.TabID.lexicon) {
                LexiconTab()
            }
            Tab("Vous", systemImage: "person.crop.circle.fill", value: Router.TabID.you) {
                YouTab { schedule in
                    // Le seul endroit qui connaît `UserNotifications`. La
                    // feature ne fait que dire « le lecteur a changé d'avis ».
                    guard schedule.enabled else {
                        await DailyVerseNotifications.reschedule(schedule, pool: composition.dailyPool)
                        return true
                    }
                    guard await DailyVerseNotifications.requestAuthorization() else { return false }
                    await DailyVerseNotifications.reschedule(schedule, pool: composition.dailyPool)
                    return true
                }
            }
        }
        // Le thème découle des réglages du lecteur, et suit Dynamic Type.
        .ontTheme(from: reading.preferences)
        // Jost dans les barres de navigation, comme le site. Une seule fois, à
        // la racine : le proxy d'apparence d'UIKit est global, l'appliquer plus
        // bas le ferait poser autant de fois qu'il y a d'écrans.
        .ontNavigationChrome()
        .preferredColorScheme(reading.preferences.theme.isDark ? .dark : .light)
        // Toucher un intraduisible n'ouvre pas une page : ça soulève une fiche
        // par-dessus la lecture, qu'on referme sans perdre sa place.
        .environment(\.openURL, OpenURLAction { url in
            router.open(url) ? .handled : .systemAction
        })
        .onOpenURL { router.open($0) }
        // ## Le thème est reposé **dans** la feuille, et il le faut
        //
        // Une feuille hérite de l'environnement de l'endroit où elle est
        // déclarée. Déclarée ici, au-dessus de `.ontTheme`, elle partait avec le
        // thème **par défaut** et le schéma **du système** : fond parchemin sous
        // des listes gris sombre, encre sombre sur fond sombre. Illisible, et
        // invisible à la relecture — le code disait bien `.ontTheme`, il le
        // disait juste à un rang que la feuille ne voyait pas.
        //
        // On a essayé de tout envelopper en remontant le thème au-dessus de la
        // feuille. Ça règle la feuille, et ça casse le reste : mesuré, le
        // parchemin sortait alors à (78,77,74) au lieu de (250,245,235), soit
        // trente pour cent de sa clarté. Un `preferredColorScheme` posé au
        // sommet ne se comporte pas comme un posé sous les onglets.
        //
        // On repose donc le thème là où il manque, plutôt que de déplacer celui
        // qui marche.
        .sheet(item: $router.openedLemma) { selection in
            TermSheet(lemma: selection.id)
                .ontTheme(from: reading.preferences)
                .preferredColorScheme(reading.preferences.theme.isDark ? .dark : .light)
        }
    }
}

