import ONTDesignSystem
import ONTKit
import SwiftUI

/// La recherche dans le corpus.
///
/// Trois choses qu'une liseuse ordinaire ne peut pas faire, et qui viennent
/// directement de la structure du texte ONT :
///
/// - **chercher par niveau** — dans le corps, dans les gloses, ou partout ;
/// - **chercher en hébreu sans les voyelles** — taper חסד trouve חֶסֶד, parce
///   que l'index porte la forme dénudée de son niqqud ;
/// - **chercher par intraduisible** — « chesed » remonte aussi les passages
///   où le terme ne paraît qu'en hébreu.
public struct SearchView: View {
    @Environment(SearchModel.self) private var model
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    private var spacing: ONTSpacing { ONTSpacing() }

    public init() {}

    @Environment(\.ontTheme) private var theme

    public var body: some View {
        @Bindable var model = model

        NavigationStack {
            List {
                Section {
                    // La portée de recherche est un choix qu'on révise en
                    // lisant les résultats : elle reste à l'écran.
                    Picker("Portée", selection: $model.scope) {
                        ForEach(SearchScope.allCases, id: \.self) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .ontRow()
                }

                if !model.hits.isEmpty {
                    Section("\(model.hits.count) passage\(model.hits.count > 1 ? "s" : "")") {
                        ForEach(model.hits) { hit in
                            Button { open(hit) } label: {
                                HitRow(hit: hit, title: model.bookTitle(hit.record.bookId),
                                       query: model.query)
                                    // Toute la rangée répond : viser un mot du
                                    // résultat pour l'ouvrir serait un jeu
                                    // d'adresse.
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .ontRow()
                        }
                    }
                }
            }
            .listStyle(.plain)
            .ontScreen()
            .navigationTitle("Rechercher")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $model.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Un mot, un intraduisible, ou de l'hébreu"
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .overlay {
                if model.query.count >= 2, model.hits.isEmpty {
                    ContentUnavailableView.search(text: model.query)
                } else if model.query.count < 2 {
                    Hints()
                }
            }
        }
    }

    private func open(_ hit: SearchHit) {
        router.open(
            book: hit.record.bookId,
            chapter: hit.record.chapterId,
            verse: hit.record.verse
        )
        dismiss()
    }
}

private struct HitRow: View {
    let hit: SearchHit
    let title: String
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(reference)
                    .font(.caption.monospaced())
                    .foregroundStyle(ONTColors.goldDeep)
                if hit.level == .gloss {
                    StatusPill("glose", tint: .gray)
                }
            }
            Text(highlighted).font(.callout).lineLimit(3)
        }
        .padding(.vertical, 3)
        .contentShape(.rect)
    }

    private var reference: String {
        let unit = hit.record.chapterId
            .replacingOccurrences(of: "\(hit.record.bookId)-", with: "")
        guard let verse = hit.record.verse else { return "\(title) \(unit)" }
        return "\(title) \(unit):\(verse)"
    }

    /// Met la correspondance en évidence dans l'extrait.
    ///
    /// On cherche directement dans l'extrait non plié, en demandant à
    /// `range(of:options:)` d'ignorer casse et diacritiques : convertir des
    /// positions d'une chaîne pliée vers l'originale serait fragile, le
    /// pliage ne préservant pas toujours le nombre de caractères.
    private var highlighted: AttributedString {
        var text = AttributedString(hit.snippet)
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard needle.count >= 2 else { return text }

        guard
            let found = hit.snippet.range(
                of: needle,
                options: [.caseInsensitive, .diacriticInsensitive]
            ),
            let lower = AttributedString.Index(found.lowerBound, within: text),
            let upper = AttributedString.Index(found.upperBound, within: text)
        else { return text }

        text[lower..<upper].backgroundColor = ONTColors.gold.opacity(0.45)
        text[lower..<upper].font = .callout.bold()
        return text
    }
}

private struct Hints: View {
    private var spacing: ONTSpacing { ONTSpacing() }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing.l) {
            hint("chesed", "un intraduisible — trouve aussi les passages en hébreu seul")
            hint("חסד", "de l'hébreu sans voyelles — trouve le texte vocalisé")
            hint("alliance", "un mot français du corps de la traduction")
            hint("temple cosmique", "une expression, plutôt dans les gloses")
        }
        .padding(spacing.xxl)
    }

    private func hint(_ example: String, _ explanation: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(example).font(.body.weight(.medium)).foregroundStyle(ONTColors.burgundy)
            Text(explanation).font(.caption).foregroundStyle(.secondary)
        }
    }
}
