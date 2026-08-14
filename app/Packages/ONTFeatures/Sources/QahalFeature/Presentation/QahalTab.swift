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
                .padding(20)
            }
            .background(theme.background)
            .navigationTitle("Qahal")
            .task { model.pick() }
        }
    }

    private var comingSoon: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("À venir")
                .font(.caption.smallCaps())
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
                            .font(.caption)
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
            .font(.caption)
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
    @Environment(\.ontTheme) private var theme
    /// La jumelle de la pastille du widget, qui suit le curseur des réglages :
    /// figée, celle-ci se serait mise à rétrécir à côté de son propre verset.
    private var echelle = ONTScaled()

    let chapter: Chapter
    let verse: Verse

    var body: some View {
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

    private var shareText: String {
        let body = verse.nodes.plainText()
            .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return """
            \(body)

            — \(chapter.title):\(verse.n), La Bible ONT
            """
    }
}
