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
    /// Comment la présentation veut être refermée, quand ce n'est pas
    /// SwiftUI qui l'a présentée — la carte du Mac, par exemple.
    @Environment(\.ontFermer) private var fermer

    var spacing = ONTSpacing()

    public init() {}

    @Environment(\.ontTheme) private var theme

    public var body: some View {
        @Bindable var model = model

        NavigationStack {
            List {
                #if os(macOS)
                    // **Le champ vit dans la carte, pas dans la fenêtre.**
                    //
                    // `.searchable` est un vœu adressé à la barre d'outils la
                    // plus proche — et dans la surimpression du Mac, c'est
                    // celle de la *fenêtre* : le champ est allé s'asseoir en
                    // haut à droite de l'écran, hors de la carte qui contenait
                    // tout le reste. Mesuré sur capture. Ici, un champ posé où
                    // l'œil est déjà.
                    Section {
                        ONTChampDeRecherche($model.query, invite: "Un mot, un intraduisible, ou de l'hébreu")
                            .listRowInsets(.init(top: 6, leading: 16, bottom: 2, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                #endif
                Section {
                    // La portée de recherche est un choix qu'on révise en
                    // lisant les résultats : elle reste à l'écran.
                    ONTSegments(
                        selection: $model.scope,
                        segments: SearchScope.allCases.map { ($0, $0.rawValue) }
                    )
                    .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .ontRow()
                }

                if !model.hits.isEmpty {
                    Section(header: Text("\(model.hits.count) passage\(model.hits.count > 1 ? "s" : "")").font(ONTUI.enteteDeListe)) {
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
            .ontTitreCompact()
            .rechercheDeLaPlateforme(texte: $model.query)
            .toolbar {
                // Seulement quand la présentation n'a pas sa propre croix — la
                // carte du Mac en pose une, et un `NavigationStack` dans une
                // surimpression projette sa barre d'outils dans la barre de
                // titre de la fenêtre. Le « Fermer » irait s'y asseoir, loin de
                // ce qu'il ferme. Voir `ONTFermeture`.
                if fermer == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fermer") { dismiss() }
                    }
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

extension View {
    /// `.searchable` là où il atteint la bonne barre — c'est-à-dire pas sur le
    /// Mac, où la carte porte déjà son champ.
    @ViewBuilder
    fileprivate func rechercheDeLaPlateforme(texte: Binding<String>) -> some View {
        #if os(macOS)
            self
        #else
            searchable(
                text: texte,
                placement: ONTPlacement.recherche,
                prompt: "Un mot, un intraduisible, ou de l'hébreu"
            )
        #endif
    }
}

private struct HitRow: View {
    @Environment(\.ontTheme) private var theme

    let hit: SearchHit
    let title: String
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(reference)
                    .font(ONTUI.caption.monospaced())
                    .foregroundStyle(ONTColors.accent(theme.mode))
                if hit.level == .gloss {
                    StatusPill("glose", tint: .gray)
                }
            }
            Text(highlighted).font(ONTUI.callout).lineLimit(3)
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

        // L'or **voilé** et non plein : à 45 % sur un fond clair il surligne,
        // mais sur la nuit il devient un aplat lumineux sous une encre claire,
        // c'est-à-dire un trou blanc. Sur fond sombre on marque par l'encre —
        // l'accent doré sur le texte lui-même — plutôt que par un fond.
        if theme.mode.isDark {
            text[lower..<upper].foregroundColor = ONTColors.accent(theme.mode)
        } else {
            text[lower..<upper].backgroundColor = ONTColors.gold.opacity(0.45)
        }
        text[lower..<upper].font = .callout.bold()
        return text
    }
}

private struct Hints: View {
    @Environment(\.ontTheme) private var theme
    var spacing = ONTSpacing()

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
            Text(example).font(ONTUI.body.weight(.medium)).foregroundStyle(ONTColors.brandInk(theme.mode))
            Text(explanation).font(ONTUI.caption).foregroundStyle(.secondary)
        }
    }
}
