import SwiftUI

/// Ce que les deux plateformes ne nomment pas pareil.
///
/// ## Pourquoi ici, et pas trente `#if` dans les vues
///
/// Le portage macOS bute sur une trentaine de points, et pas un seul n'est un
/// désaccord de conception : ce sont des modificateurs SwiftUI qu'iOS a et que
/// le Mac n'a pas, ou l'inverse. Semés dans les vues, ils feraient trente
/// endroits à retoucher le jour où une troisième plateforme arrive, et trente
/// occasions d'en oublier un.
///
/// Rassemblés ici, ils forment ce que le reste du code doit savoir de la
/// plateforme : **rien**. Une vue déclare son intention — « ce titre est
/// compact », « ce bouton est l'action principale » — et le design system la
/// traduit.
///
/// C'est la même règle que pour les couleurs : une vue ne demande jamais « le
/// thème est-il sombre ? », elle demande `ONTColors.ink(theme)`.
///
/// ## Ce qui n'est pas ici, délibérément
///
/// Les différences qui **sont** des choix — une barre d'onglets en bas contre
/// une barre latérale, une feuille contre une fenêtre — n'ont rien à faire dans
/// un adaptateur. Elles se décident, et le code doit montrer qu'on a décidé.
extension View {
    /// Un titre de barre compact — sans effet sur le Mac, qui n'a pas de
    /// grand titre à réduire.
    public func ontTitreCompact() -> some View {
        #if os(iOS)
            return navigationBarTitleDisplayMode(.inline)
        #else
            return self
        #endif
    }

    /// La taille d'une feuille de lecture.
    ///
    /// **Sur le Mac, ne rien faire ne suffit pas.** Une feuille macOS se
    /// dimensionne sur l'idéal de son contenu, et un `List` n'en propose aucun :
    /// la fiche d'un Shem s'affichait en bandeau — titre, sous-titre, un
    /// intertitre, et rien de ses vingt-six blocs.
    ///
    /// `presentationSizing(.page)` demande une feuille de la taille d'une page,
    /// ce qu'une fiche est. Borné par `available` et non par le plancher du
    /// paquet : celui-ci reste à macOS 14, que d'autres cibles emploient, et le
    /// monter entier pour une feuille exclurait des machines pour rien.
    ///
    /// ## Ce que ce défaut a coûté, et pourquoi c'est écrit ici
    ///
    /// Je l'ai cru corrigé, puis inexistant, puis réel — deux revirements.
    /// L'`osascript quit` n'aboutissait pas contre une feuille modale ouverte,
    /// donc `open` rattachait la fenêtre du processus déjà en place : quatre
    /// correctifs mesurés sur un binaire vieux de vingt minutes, tous jugés
    /// sans effet. Puis un lancement enfin propre a montré la fiche entière —
    /// et j'en ai conclu qu'il n'y avait rien à corriger, en oubliant que ce
    /// lancement-là portait **aussi** les correctifs.
    ///
    /// La leçon tient en une ligne : **une capture identique au pixel près à
    /// travers plusieurs changements de code n'est pas un défaut tenace, c'est
    /// un instrument mort** — et quand l'instrument revit, il faut refaire les
    /// mesures, pas relire les anciennes.
    ///
    /// Pour tuer l'app entre deux essais : `pkill -x ONTMac`, jamais
    /// `osascript quit`.
    public func ontHauteurDeFeuille(_ fractions: Set<PresentationDetent>) -> some View {
        #if os(iOS)
            return AnyView(presentationDetents(fractions))
        #else
            if #available(macOS 15.0, *) {
                return AnyView(presentationSizing(.page))
            }
            return AnyView(frame(minWidth: 560, minHeight: 460))
        #endif
    }

    /// Cache la barre d'état, là où il y en a une.
    ///
    /// Le Mac n'en a pas : sa barre de menus appartient au système et une app
    /// ne la masque que si elle passe en plein écran, ce qu'une liseuse ne fait
    /// pas de sa propre initiative.
    public func ontSansBarreDEtat(_ cachee: Bool) -> some View {
        #if os(iOS)
            return statusBarHidden(cachee)
        #else
            return self
        #endif
    }

    /// Pas de capitale automatique — un clavier logiciel seulement.
    public func ontSansCapitaleAutomatique() -> some View {
        #if os(iOS)
            return textInputAutocapitalization(.never)
        #else
            return self
        #endif
    }
}

/// Où va un bouton de barre d'outils.
///
/// `topBarLeading` et `topBarTrailing` n'existent pas sur le Mac. Les
/// placements **sémantiques** — action principale, annulation — existent
/// partout et disent en plus ce que le bouton *fait*, ce que « à droite » ne
/// dit pas.
public enum ONTPlacement {
    /// L'action que la barre sert — à droite sur iOS, à sa place sur le Mac.
    public static var principale: ToolbarItemPlacement {
        #if os(iOS)
            .topBarTrailing
        #else
            .primaryAction
        #endif
    }

    /// Le style d'une liste de réglages ou de sommaire.
    ///
    /// `insetGrouped` est le style d'iOS — des groupes détachés, arrondis, sur
    /// un fond. Le Mac n'en dispose pas ; `inset` en est le plus proche et
    /// garde les marges qui séparent les groupes.
    public static var listeGroupee: some ListStyle {
        #if os(iOS)
            .insetGrouped
        #else
            .inset
        #endif
    }

    /// Où se pose le champ de recherche.
    ///
    /// iOS le veut **toujours visible** — sur un téléphone, une barre qui
    /// apparaît au défilement est une barre qu'on cherche. Le Mac n'a pas
    /// cette notion et place le champ dans sa barre d'outils.
    public static var recherche: SearchFieldPlacement {
        #if os(iOS)
            .navigationBarDrawer(displayMode: .always)
        #else
            .toolbar
        #endif
    }

    /// Fermer, annuler, revenir.
    public static var retrait: ToolbarItemPlacement {
        #if os(iOS)
            .topBarLeading
        #else
            .cancellationAction
        #endif
    }
}
