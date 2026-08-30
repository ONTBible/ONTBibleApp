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

    /// La hauteur d'une feuille, quand la plateforme en propose une.
    ///
    /// Sur le Mac, une feuille se dimensionne d'elle-même ; le paramètre est
    /// donc ignoré plutôt que traduit en une fenêtre de taille fixe, qui
    /// contraindrait ce qu'iOS laisse libre.
    public func ontHauteurDeFeuille(_ fractions: Set<PresentationDetent>) -> some View {
        #if os(iOS)
            return presentationDetents(fractions)
        #else
            return self
        #endif
    }

    /// Cache la barre d'état, là où il y en a une.
    ///
    /// Le Mac n'en a pas : sa barre de menus appartient au système et une app
    /// ne la masque que si elle passe en plein écran, ce qu'une liseuse ne
    /// fait pas de sa propre initiative.
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
