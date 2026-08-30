import ONTDesignSystem
import ONTKit
import SwiftUI

/// **Qahal** (קָהָל) — l'assemblée. La part communautaire.
///
/// Le nom est cohérent avec le corpus : la *Kenesset* est le rassemblement des
/// **textes**, le *Qahal* celui des **lecteurs**.
///
/// Structure posée, sans serveur : le verset du jour est tiré localement, et
/// tout ce qui suppose d'autres lecteurs est annoncé sans être simulé — un
/// faux fil d'activité donnerait une idée fausse de ce qui existe.
public struct QahalTab: View {
    @Environment(QahalModel.self) private var model
    @Environment(\.ontTheme) private var theme

    /// La marge de la page. Nommée parce qu'elle sert deux fois : le rembourrage
    /// de la colonne, et la largeur qu'il faut lui ajouter pour que la carte
    /// **dedans** fasse exactement sa mesure.
    private let marge: CGFloat = 20

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if let verseOfTheDay = model.verseOfTheDay {
                        VerseOfTheDayCard(
                            chapter: verseOfTheDay.chapter,
                            verse: verseOfTheDay.verse
                        )
                    }

                    comingSoon
                }
                .padding(marge)
                // Les cartes gardent la mesure qu'elles ont sur iPhone. La
                // colonne de la page fait 850 ; y étaler la carte du verset la
                // transformait en bande, et le verset ne tenait plus que sur
                // deux lignes traversant l'écran.
                .frame(maxWidth: ONTLayout.cardWidth + 2 * marge)
                // Centrées dans la colonne. Le grand titre, lui, reste à la
                // marge — c'est la barre de navigation qui le place, pas nous.
                // Les deux alignements ne se rejoignent donc pas, et c'est
                // assumé : une carte étroite posée à gauche d'une page large
                // pend dans le vide, alors qu'au centre elle tient.
                .frame(maxWidth: .infinity)
            }
            // La règle du design system : tout écran de premier niveau le
            // porte. Le Qahal ne l'avait pas — il posait son fond à la main.
            .ontScreen()
            .navigationTitle("Qahal")
            .task { model.pick() }
        }
        .ontColumn()
    }

    private var comingSoon: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("À venir")
                .font(ONTUI.caption.smallCaps())
                .foregroundStyle(.secondary)

            ForEach(
                [
                    ("heart.text.square", "Ce que le Qahal a retenu", "les versets les plus repris"),
                    ("bubble.left.and.text.bubble.right", "Échanges", "commenter un passage"),
                    ("book.pages", "Parcours", "lire le corpus à plusieurs"),
                ],
                id: \.0
            ) { icon, title, subtitle in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                        Text(subtitle)
                            .font(ONTUI.caption)
                            .foregroundStyle(.tertiary)
                    }
                } icon: {
                    Image(systemName: icon)
                        .foregroundStyle(ONTColors.accent(theme.mode))
                }
            }
            .foregroundStyle(.secondary)

            Text(
                "Ces fonctions demandent un serveur. La lecture, elle, fonctionne "
                    + "entièrement hors ligne."
            )
            .font(ONTUI.caption)
            .foregroundStyle(.tertiary)
            .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
    }

}

/// La carte du verset du jour, dans le Qahal.
///
/// Le rendu appartient à `ONTDailyCard`, partagée avec le widget de l'écran
/// d'accueil — c'est ce qui garantit que les deux se ressemblent. Ce qui reste
/// ici est ce que le widget ne peut pas faire : composer le verset depuis son
/// arbre d'inline, avec les intraduisibles en or.
private struct VerseOfTheDayCard: View {
    @Environment(Router.self) private var router
    @Environment(\.ontTheme) private var theme
    /// La jumelle de la pastille du widget, qui suit le curseur des réglages :
    /// figée, celle-ci se serait mise à rétrécir à côté de son propre verset.
    var echelle = ONTScaled()

    let chapter: Chapter
    let verse: Verse

    var body: some View {
        // **La carte mène au texte.**
        //
        // Elle donnait un verset sans dire d'où il venait — un fragment sans
        // son avant ni son après, alors que le renvoi était écrit dessus. Le
        // lecteur qui voulait la suite devait retrouver le passage à la main
        // dans l'onglet Bible.
        //
        // Le geste est celui de la recherche et du lien profond : `open` pose
        // l'onglet, le livre, l'unité, et désigne le verset — qui est déjà
        // surligné à l'arrivée.
        Button {
            router.open(book: chapter.bookId, chapter: chapter.id, verse: verse.n)
        } label: {
            carte
        }
        // `.plain` et non un style par défaut : la carte porte déjà sa peau,
        // et un bouton système la repeindrait.
        .buttonStyle(.plain)
        .accessibilityHint("Ouvre le passage dans la Bible")
    }

    private var carte: some View {
        BurgundyCard {
            ONTDailyCard(
                text: ONTTextRenderer.composeBare(
                    verse.nodes, theme: theme, ink: ONTColors.gold
                ),
                reference: "\(chapter.title):\(verse.n)",
                size: .large
            ) {
                ShareLink(item: shareText) {
                    // Le même traitement que la pastille du widget, pour que
                    // les deux cartes restent jumelles : un voile d'or, un
                    // texte d'or plein.
                    Text("Partager")
                        .font(.system(size: echelle(14), weight: .semibold))
                        .foregroundStyle(ONTColors.gold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(ONTColors.gold.opacity(0.18)))
                        .contentShape(.capsule)
                }
            }
        }
    }

    /// Les réglages viennent du **thème**, et non d'un modèle de lecture.
    ///
    /// `ONTTheme` porte déjà les préférences et traverse tout l'écran ;
    /// importer `ReadingFeature` ici pour cinq booléens créerait une
    /// dépendance entre deux features qui n'ont rien d'autre à se dire.
    private var reglages: ReglagesDePartage { theme.preferences.partage }

    /// **Le même compositeur que la liseuse**, et donc les mêmes réglages.
    ///
    /// Cette carte écrivait sa propre forme, en dur. Deux endroits qui
    /// composent un partage finissent par n'en avoir qu'un seul de juste : les
    /// bascules auraient valu pour un passage lu et pas pour le verset du jour,
    /// et personne n'aurait su pourquoi.
    ///
    /// `plainText()` replie déjà ses espaces — retours à la ligne préservés,
    /// ponctuation française respectée.
    private var shareText: String {
        Partage.composer(
            [Partage.Morceau(numero: verse.n, texte: verse.nodes.plainText())],
            reference: "\(chapter.title):\(verse.n)",
            reglages: reglages
        )
    }
}
