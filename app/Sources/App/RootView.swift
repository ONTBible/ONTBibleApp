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
        .sheet(item: $router.openedLemma) { selection in
            TermSheet(lemma: selection.id)
        }
    }
}

