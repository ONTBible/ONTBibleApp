import ONTDesignSystem
import ONTKit
import SwiftUI

/// La fiche d'un intraduisible — ce qui s'ouvre quand on en touche un.
///
/// C'est l'équivalent ONT de la fiche Strong, à ceci près que son contenu
/// n'est pas un dictionnaire tiers : c'est le glossaire du projet lui-même
/// (`CLAUDE.md` §2.5 et §3), dérivé à chaque build.
///
/// L'ordre suit ce qu'on cherche vraiment quand on s'arrête sur un mot : le
/// mot original, ce qu'il veut dire, **ce qu'il n'est pas** — la part la plus
/// utile, parce que tout le projet consiste à retirer les catégories
/// importées — puis où il paraît ailleurs.
public struct TermSheet: View {
    @Environment(LexiconModel.self) private var model
    @Environment(\.ontTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let lemma: String

    public init(lemma: String) { self.lemma = lemma }
    @State private var bodyOnly = true

    private var entry: GlossaryEntry? { model.entry(lemma) }

    public var body: some View {
        NavigationStack {
            Group {
                if let entry {
                    content(entry)
                } else {
                    ContentUnavailableView(
                        "Terme non documenté",
                        systemImage: "character.book.closed",
                        description: Text(
                            "« \(lemma) » est balisé dans le texte mais n'a pas encore "
                                + "d'entrée dans le glossaire."
                        )
                    )
                }
            }
            .ontScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ entry: GlossaryEntry) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    if let hebrew = entry.hebrew {
                        Text(hebrew)
                            .font(.custom(ONTFonts.hebrew, size: 40))
                    }
                    Text(entry.title)
                        .font(.custom(ONTFonts.display, size: 26))
                        .foregroundStyle(ONTColors.brandInk(theme.mode))

                    if let rendering = entry.rendering, rendering != entry.title {
                        Text(rendering)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    if !entry.tagged {
                        Label(
                            "Vocabulaire fixé — traduit dans le corps du texte",
                            systemImage: "text.quote"
                        )
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 6)
            }
            // ## Section par section, et pas une fois pour toutes
            //
            // `listRowBackground` s'adresse aux **lignes**. Posé sur le `Group`
            // qui entoure la liste, il ne change rien ; posé sur la `List`
            // elle-même, rien non plus — vérifié à l'écran deux fois, avec la
            // couleur mesurée au pixel. Seules les sections et les lignes
            // l'entendent, et c'est ainsi que `BibleTab` s'y prend depuis
            // toujours.
            .ontRow()

            Section("Ce qu'il signifie") {
                if entry.sansDefinition {
                    // **Le silence était pire que l'aveu.** Sans cette section,
                    // l'écran passait de l'en-tête aux repères sans rien entre
                    // les deux : il avait l'air complet, et le lecteur pouvait
                    // croire que c'était tout ce qu'il y avait à dire du mot.
                    //
                    // La phrase dit ce qui manque **et** ce qui reste vrai : le
                    // terme est bien de l'ONT, il est bien balisé, seule sa
                    // fiche n'est pas écrite.
                    Text(
                        "Ce terme est balisé dans le texte, mais sa définition "
                            + "n'est pas encore écrite."
                    )
                    .foregroundStyle(.secondary)
                } else if let definition = entry.definition {
                    ForEach(Array(definition.enumerated()), id: \.offset) { _, block in
                        BlocDeFiche(block: block)
                    }
                }
            }
            .ontRow()

            if let note = entry.taggingNote {
                Section("Règle de balisage") {
                    ForEach(Array(note.enumerated()), id: \.offset) { _, block in
                        BlocDeFiche(block: block)
                    }
                }
                .ontRow()
            }

            Section("Repères") {
                if let firstUse = entry.firstUse {
                    LabeledContent("Premier emploi", value: firstUse)
                }
                LabeledContent("Dans le corps", value: "\(entry.bodyCount)")
                LabeledContent("Dans les gloses", value: "\(entry.glossCount)")
                if entry.forms.count > 1 {
                    LabeledContent("Formes") {
                        Text(entry.forms.joined(separator: " · "))
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            .ontRow()

            occurrences(entry)
        }
    }

    @ViewBuilder
    private func occurrences(_ entry: GlossaryEntry) -> some View {
        let list = model.occurrences(entry.lemma, bodyOnly: bodyOnly)

        Section {
            if list.isEmpty {
                Text("Aucune occurrence dans le corpus rédigé à ce jour.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(list.prefix(60).enumerated()), id: \.offset) { _, occurrence in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(reference(occurrence))
                                .font(.caption.monospaced())
                                .foregroundStyle(ONTColors.accent(theme.mode))
                            if occurrence.level == .gloss {
                                Text("glose")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Text(occurrence.snippet)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                if list.count > 60 {
                    Text("… et \(list.count - 60) autres")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            // « Où ce mot est dans le texte » et « où on l'explique » sont deux
            // questions différentes — la fiche doit pouvoir poser l'une sans
            // l'autre.
            ONTSegments(
                selection: $bodyOnly,
                segments: [(true, "Dans le texte"), (false, "Tout")]
            )
            .textCase(nil)
        }
        .ontRow()
    }

    private func reference(_ occurrence: Occurrence) -> String {
        let unit = occurrence.chapterId
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: " 0 intro", with: " — intro")
        guard let verse = occurrence.verse else { return unit }
        return "\(unit):\(verse)"
    }
}
