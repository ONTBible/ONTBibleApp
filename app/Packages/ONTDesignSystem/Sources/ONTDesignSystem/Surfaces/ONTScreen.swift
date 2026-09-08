import ONTKit
import SwiftUI

/// L'écran type de l'ONT.
///
/// Sans ce modificateur, chaque écran hérite du fond que lui impose son
/// conteneur : une `List` groupée pose un gris système, une `List` simple pose
/// du blanc, et un `ScrollView` laisse passer le fond de la fenêtre. Le
/// résultat, ce sont quatre onglets qui ne se ressemblent pas — alors même
/// qu'un design system est en place.
///
/// `scrollContentBackground(.hidden)` est la clé : c'est le seul moyen de
/// retirer le fond qu'une `List` ou un `Form` dessine par-dessus le nôtre.
///
/// **Tout écran de premier niveau doit l'appliquer.** C'est la règle qui
/// garantit que l'app a une seule couleur de peau.
public struct ONTScreenModifier: ViewModifier {
    @Environment(\.ontTheme) private var theme

    public func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            // **Un interrupteur, et non une case à cocher.**
            //
            // Sur le Mac, un `Toggle` rend une *case à cocher* dans une `List`
            // et un *interrupteur* dans un `Form` en style groupé. Les réglages
            // de lecture passent par `ontFormulaire()`, donc par le second ;
            // « Le français reçu » et « Synchroniser mes annotations » vivent
            // dans une `List`, donc par le premier. Deux réglages du même écran,
            // deux commandes différentes, sans que personne l'ait décidé.
            //
            // C'est l'interrupteur qu'on garde : c'est ce que rend l'iPhone, et
            // ce que rend déjà la moitié des réglages ici. Posé au point unique
            // par lequel tous les écrans passent, pour la même raison que le
            // grain plus bas — ailleurs, il manquerait quelque part.
            //
            // Le style se transmet par l'environnement : un `Form` groupé le
            // rendait déjà, rien n'y change.
            .ontInterrupteurs()
            // Le grain de la nuit se pose ici, et **seulement** ici : c'est le
            // point unique par lequel passe le fond de tous les écrans, donc le
            // seul endroit où il ne peut ni manquer quelque part, ni se
            // superposer à lui-même et doubler son opacité.
            .background {
                theme.background
                    .overlay(ONTGrain(theme: theme.mode))
                    .ignoresSafeArea()
            }
    }
}

/// La colonne de l'app — bornée en largeur, centrée, sur un fond qui reste plein.
///
/// Sur iPhone, elle ne fait rien : l'écran est plus étroit que la borne. Sur
/// iPad, elle est ce qui empêche l'app de s'étirer d'un bord à l'autre — une
/// carte de verset large de mille points, une liste dont les valeurs partent si
/// loin à droite qu'on ne sait plus à quelle ligne elles appartiennent.
///
/// ## Posée **autour** de la pile de navigation, et pas dedans
///
/// Le grand titre appartient à la barre de navigation. Borner seulement le
/// contenu laissait « Qahal » collé à la marge pendant que la carte se centrait
/// deux cents points plus loin : deux alignements pour une même page, ce qui se
/// lit comme un défaut. En bornant la pile entière, le titre suit sa page.
///
/// ## Les marges reçoivent le même fond que la colonne, grain compris
///
/// Il faut peindre de part et d'autre, sinon l'iPad montre le gris du système.
/// Et il faut y mettre le grain : mesuré, des marges plates sortaient à
/// (24, 9, 13) contre (27, 12, 16) au centre — trois points d'écart, un liseré
/// visible sur toute la hauteur.
///
/// Ça ne double pas le grain de la colonne, contrairement à ce que la mise en
/// garde d'`ONTScreenModifier` laisse craindre : le fond que l'écran pose
/// **dedans** est opaque, donc il couvre celui-ci au lieu de s'y ajouter. Ce
/// qu'on peint ici ne se voit que là où rien d'autre ne passe.
///
/// La peinture ne peut d'ailleurs pas venir d'ici : posée au-dehors, elle est
/// recouverte par le fond que la pile de navigation dessine pour elle-même —
/// une colonne noire entre deux marges aubergine. Chaque onglet garde donc son
/// `ontScreen()`.
public struct ONTColumnModifier: ViewModifier {
    @Environment(\.ontTheme) private var theme

    /// Faux quand l'écran a besoin de toute la largeur — voir `ontColumn(bornee:)`.
    let bornee: Bool

    public init(bornee: Bool = true) {
        self.bornee = bornee
    }

    public func body(content: Content) -> some View {
        content
            .frame(maxWidth: bornee ? ONTLayout.pageWidth : .infinity)
            .frame(maxWidth: .infinity)
            .background {
                theme.background
                    .overlay(ONTGrain(theme: theme.mode))
                    .ignoresSafeArea()
            }
    }
}

/// La ligne de liste type — surface du thème, séparateur du thème.
public struct ONTRowModifier: ViewModifier {
    @Environment(\.ontTheme) private var theme
    private var spacing = ONTSpacing()

    public func body(content: Content) -> some View {
        content
            .listRowBackground(theme.surface)
            .listRowSeparatorTint(theme.separator)
            // **Les marges d'une rangée, sur le Mac.**
            //
            // iOS les donne avec `insetGrouped` — des groupes détachés, dont le
            // contenu respire. Le Mac n'a pas ce style ; `inset`, son plus
            // proche, en pose beaucoup moins, et le texte d'une fiche venait
            // toucher les deux bords de la feuille.
            //
            // Ce n'est pas une coquetterie : une colonne de lecture sans marge
            // fatigue, et l'œil perd sa ligne au retour. C'est la même raison
            // qui donne à la fenêtre une largeur minimale.
            //
            // On les pose sur la **rangée** plutôt que sur la feuille : chaque
            // écran qui emploie `ontRow` en profite, et un futur écran de
            // réglages n'aura pas à y penser.
            #if os(macOS)
                .listRowInsets(
                    EdgeInsets(
                        top: spacing.m, leading: spacing.page,
                        bottom: spacing.m, trailing: spacing.page))
            #endif
    }
}

private struct ONTListeDeProseModifier: ViewModifier {
    private var spacing = ONTSpacing()

    func body(content: Content) -> some View {
        #if os(macOS)
            // Le Mac reçoit déjà la gouttière par `ontRow`, et sa carte a ses
            // propres marges. En ajouter une seconde la creuserait.
            content.listStyle(.plain)
        #else
            content
                .listStyle(.plain)
                .safeAreaPadding(.horizontal, spacing.page)
        #endif
    }
}

extension View {
    /// Une liste de prose — une fiche, une feuille, des résultats.
    ///
    /// ## Le défaut que ça ferme, relevé à l'écran le 8 septembre 2026
    ///
    /// La feuille de prononciation touchait les deux bords, pendant que celle
    /// de lecture respirait. Les deux sont des `List` ; l'écart tient au
    /// **style** : un `Form` groupé porte les marges du système, un
    /// `.listStyle(.plain)` n'en porte aucune.
    ///
    /// L'intention était déjà écrite — `ontRow` pose `spacing.page` de chaque
    /// côté « pour que chaque écran qui l'emploie en profite, sans y penser ».
    /// **Elle s'arrêtait au Mac.** Sur iOS on comptait sur les marges du
    /// système, et elles n'existent que pour les styles groupés.
    ///
    /// ## Pourquoi ici et pas sur la rangée
    ///
    /// Une rangée ne connaît pas le style de sa liste. Poser la gouttière sur
    /// `ontRow` la **doublerait** dans les réglages, qui sont un `Form` groupé
    /// et reçoivent déjà celle du système. C'est là que le style se choisit,
    /// donc c'est là que sa conséquence s'écrit.
    ///
    /// `safeAreaPadding` plutôt que `padding` : le défilement continue de
    /// passer sous la marge, donc le texte glisse jusqu'au bord au lieu de
    /// s'arrêter net — c'est ce que fait une page de lecture.
    public func ontListeDeProse() -> some View {
        modifier(ONTListeDeProseModifier())
    }

    /// Une liste **d'index** — on la parcourt, on ne la lit pas.
    ///
    /// Le Lexique en est une : trois cents entrées, un rail de lettres collé au
    /// bord droit. La gouttière de lecture y serait un contresens — elle
    /// décollerait le rail du bord, c'est-à-dire de l'endroit précis où le
    /// pouce va le chercher.
    ///
    /// **Nommée plutôt qu'exemptée.** Une liste sans gouttière est soit un
    /// index, soit un oubli, et rien ne les distingue à la lecture d'un
    /// `.listStyle(.plain)` nu. Ce nom-là dit lequel des deux, et c'est ce qui
    /// permet au contrôle d'interdire la forme nue sans tenir de liste
    /// d'exceptions — une liste d'exceptions vieillit, un nom non.
    public func ontListeDIndex() -> some View {
        listStyle(.plain)
    }

    /// Le fond de l'app, y compris sous une `List` ou un `Form`.
    public func ontScreen() -> some View { modifier(ONTScreenModifier()) }

    /// La surface d'une ligne de liste.
    public func ontRow() -> some View { modifier(ONTRowModifier()) }

    /// Les `Toggle` en interrupteurs, là où la plateforme en ferait des cases.
    ///
    /// Sur iOS il n'y a rien à faire : un `Toggle` y est déjà un interrupteur,
    /// partout. Le `#if` porte donc sur ce que **le système** rend, jamais sur
    /// ce que le réglage veut dire.
    public func ontInterrupteurs() -> some View {
        #if os(macOS)
            return toggleStyle(.switch)
        #else
            return self
        #endif
    }

    /// La colonne de l'app — à poser autour de la pile de navigation d'un onglet.
    ///
    /// ## `bornee: false` — la lecture, et elle seule
    ///
    /// La borne s'applique à la **pile entière**, pour que le grand titre suive
    /// sa page. Elle décide donc aussi de la largeur de la liseuse, qui est
    /// posée dans cette pile — et c'est ce qui faisait commencer le pli du
    /// glissement à 91 points du bord de l'iPad, jamais à l'extrémité : la page
    /// qu'on soulève s'arrêtait là, et rien de ce qu'on dessine dedans ne peut
    /// en sortir. Mesuré : la zone qui bouge pendant le geste partait de
    /// x = 91 pt sur un écran de 1032.
    ///
    /// Élargir le pli au-delà de la page ne mène nulle part — la pile de
    /// navigation rogne ce qui dépasse. C'est donc **la borne qui se déplace** :
    /// l'écran de lecture prend toute la largeur, et la mesure du texte est
    /// tenue plus bas, par `ParchmentPage`, qui borne déjà la colonne à
    /// `readingWidth`. Le texte ne bouge pas d'un point : centré dans 850 ou
    /// dans 1032, une colonne de 700 tombe au même endroit.
    public func ontColumn(bornee: Bool = true) -> some View {
        modifier(ONTColumnModifier(bornee: bornee))
    }
}
