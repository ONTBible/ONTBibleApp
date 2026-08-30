import ONTDesignSystem
import ONTKit
import SwiftUI

/// L'onglet Lexique — tout le glossaire, consultable de bout en bout.
///
/// Deux populations, et la distinction compte : les **intraduisibles** (§2.5)
/// restent en hébreu dans le corps du texte et se touchent à la lecture ; le
/// **vocabulaire fixé** (§3) est traduit — *bara* → « orchestrer » — donc
/// invisible au toucher, mais il porte l'essentiel de l'ontologie
/// fonctionnelle et mérite d'être feuilletable.
public struct LexiconTab: View {
    @Environment(LexiconModel.self) private var model
    @Environment(\.ontTheme) private var theme

    @State private var search = ""
    @State private var scope: LexiconModel.Scope = .tagged
    @State private var selected: LemmaSelection?

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollViewReader { defilement in
            List {
                Section {
                    EmptyView()
                } header: {
                    // En-tête de section plutôt que `safeAreaInset` : une
                    // `List` simple épingle ses en-têtes, et le grand titre
                    // de navigation reste visible — ce que l'insert écrasait.
                    ONTSegments(
                        selection: $scope,
                        segments: LexiconModel.Scope.allCases.map { ($0, $0.rawValue) }
                    )
                    .padding(.vertical, 6)
                    .textCase(nil)
                    .listRowInsets(.init(top: 0, leading: 16, bottom: 0, trailing: 16))
                }

                // **Une section par lettre**, et non une seule liste plate.
                //
                // Le rail a besoin d'une cible pour chaque lettre, et les
                // en-têtes de section en font une que `scrollTo` sait viser.
                // Ils rendent en prime l'index lisible à VoiceOver, qui
                // parcourt les sections — ce que le rail, lui, ne peut pas
                // offrir à un doigt glissé.
                ForEach(tranches) { tranche in
                    Section {
                        ForEach(tranche.entrees) { entry in
                            Button {
                                selected = LemmaSelection(entry.lemma)
                            } label: {
                                EntryRow(entry: entry)
                                    // Toute la rangée répond, pas seulement les
                                    // lettres : un `HStack` ne définit aucune
                                    // forme tactile, seul le dessin des glyphes
                                    // est touché.
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .ontRow()
                        }
                    } header: {
                        Text(tranche.lettre)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(theme.accent)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .id(tranche.lettre)
                }
            }
            .listStyle(.plain)
            // **La liste recule pour le rail.**
            //
            // Sans ça les compteurs de la colonne de droite viennent toucher
            // les lettres — relevé à l'écran : « 214 » à deux points du « D ».
            // Le rail se pose *par-dessus* la liste ; c'est donc à la liste de
            // lui céder la place, pas au rail de se serrer.
            .safeAreaPadding(.trailing, railVisible ? 20 : 0)
            // **Le rail ne paraît qu'à la liste entière.**
            //
            // Sur un résultat de recherche il mentirait : ses lettres
            // porteraient sur le lexique complet, la liste sur autre chose.
            // Et sous vingt entrées il ne sert à rien — le pouce en fait
            // autant en défilant.
            .overlay(alignment: .trailing) {
                if railVisible {
                    ONTRailDeLettres(lettres: tranches.map(\.lettre)) { lettre in
                        // Sans animation : un saut d'index doit être
                        // instantané. Animé, le pouce descend plus vite que la
                        // liste et l'on vise une lettre qu'on a déjà passée.
                        defilement.scrollTo(lettre, anchor: .top)
                    }
                    .padding(.trailing, 2)
                }
            }
            .ontScreen()
            .navigationTitle("Lexique")
            .searchable(
                text: $search,
                prompt: "Un terme, un mot français, de l'hébreu…"
            )
            .sheet(item: $selected) { selection in
                TermSheet(lemma: selection.id)
            }
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            }
        }
        .ontColumn()
    }

    private var filtered: [GlossaryEntry] {
        model.filtered(scope: scope, search: search)
    }

    /// Le rail ne paraît qu'à la liste entière, et seulement si elle est assez
    /// longue pour qu'un pouce y gagne quelque chose.
    ///
    /// Sur un résultat de recherche il mentirait : ses lettres porteraient sur
    /// le lexique complet, la liste sur autre chose.
    private var railVisible: Bool {
        search.isEmpty && tranches.count > 1 && filtered.count >= 20
    }

    /// Les entrées découpées par lettre, dans l'ordre où le modèle les rend.
    private var tranches: [TrancheAlphabetique<GlossaryEntry>] {
        IndexAlphabetique.trancher(filtered) { $0.title }
    }
}

private struct EntryRow: View {
    @Environment(\.ontTheme) private var theme

    let entry: GlossaryEntry

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(entry.tagged ? ONTColors.brandInk(theme.mode) : theme.ink)

                if let rendering = entry.rendering, rendering != entry.title {
                    Text(rendering)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if let hebrew = entry.hebrew {
                Text(hebrew)
                    .font(.custom(ONTFonts.hebrew, size: 21))
                    .foregroundStyle(.secondary)
            }

            if entry.count > 0 {
                Text("\(entry.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 28, alignment: .trailing)
            }
        }
        .padding(.vertical, 3)
        .contentShape(.rect)
    }
}
