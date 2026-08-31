import ONTDesignSystem
import ONTKit
import ReadingFeature
import SwiftUI

/// Tout ce que le lecteur a marqué, rassemblé.
///
/// **Par livre, dans l'ordre du corpus, et non par date.** On cherche « ce que
/// j'ai marqué dans *Bereshit* », jamais « ce que j'ai marqué mardi » : un
/// classement chronologique disperse un même livre sur toute la liste, et deux
/// séances de lecture du même chapitre s'y retrouvent aux deux bouts. La date
/// reste sur chaque ligne — elle situe, elle ne classe pas.
///
/// **La couleur est un filet à gauche, jamais un fond.** Dans la page de
/// lecture le fond a du sens : il marque le verset *dans* son texte. En liste,
/// cinq fonds colorés à la file font une bande dessinée, et le texte devient
/// illisible sur trois d'entre eux. Le filet dit la même chose et laisse le
/// verset se lire.
public struct MesSurlignages: View {
    @Environment(ReadingModel.self) private var reading
    @Environment(Router.self) private var router
    @Environment(\.ontTheme) private var theme

    /// La couleur retenue, ou toutes.
    @State private var filtre: HighlightColor?

    public init() {}

    private var livres: [LivreSurligne] {
        let tous = reading.surlignagesParLivre()
        guard let filtre else { return tous }
        return tous.compactMap { livre in
            let gardes = livre.surlignages.filter { $0.surlignage.color == filtre }
            return gardes.isEmpty ? nil : LivreSurligne(livre: livre.livre, surlignages: gardes)
        }
    }

    private var couleurs: [(HighlightColor, Int)] {
        Surlignages.parCouleur(reading.surlignagesParLivre().flatMap { $0.surlignages }.map(\.surlignage))
    }

    private var total: Int { livres.reduce(0) { $0 + $1.surlignages.count } }

    public var body: some View {
        List {
            if couleurs.count > 1 {
                Section {
                    FiltreDeCouleur(couleurs: couleurs, choisie: $filtre)
                }
                .ontRow()
            }

            ForEach(livres) { livre in
                Section {
                    ForEach(livre.surlignages) { situe in
                        Button {
                            router.open(
                                book: situe.surlignage.bookId,
                                chapter: situe.surlignage.chapterId,
                                verse: situe.surlignage.verse)
                        } label: {
                            LigneDeSurlignage(situe: situe)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    EnTeteDeLivre(livre: livre.livre)
                }
                .ontRow()
            }

            if livres.isEmpty {
                Section {
                    Rien(filtre: filtre)
                }
                .ontRow()
            }
        }
        .navigationTitle("Surlignages")
        .ontTitreCompact()
        // Le décompte est **dans** la barre et non en tête de liste : il suit le
        // filtre, et une ligne de total qui monte et descend avec lui ferait
        // sauter toute la liste à chaque changement.
        .toolbar {
            ToolbarItem(placement: ONTPlacement.principale) {
                Text("\(total)")
                    .font(ONTUI.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(total) surlignages")
            }
        }
        .ontScreen()
    }
}

// MARK: - Les pièces

private struct EnTeteDeLivre: View {
    @Environment(ReadingModel.self) private var model
    let livre: BookOutline

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(livre.title)
                .font(ONTUI.ligneDeListe)
            // Le second nom suit le registre, comme partout ailleurs.
            if let second = Registre.second(
                french: livre.french, glose: livre.glose,
                francaisRecu: model.preferences.french)
            {
                Text(second)
                    .font(ONTUI.caption2)
                    .foregroundStyle(.tertiary)
                    .textCase(nil)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

private struct LigneDeSurlignage: View {
    @Environment(\.ontTheme) private var theme
    let situe: SurlignageSitue

    private var date: String {
        situe.surlignage.updatedAt.formatted(.dateTime.day().month(.abbreviated).year())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Le filet. `Capsule` et non `Rectangle` : ses bouts arrondis le
            // rapprochent du trait d'un marqueur, et l'éloignent d'une bordure
            // de tableau.
            Capsule()
                .fill(ONTColors.highlight(situe.surlignage.color, theme.mode))
                .frame(width: 4)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(situe.renvoi)
                        .font(ONTUI.caption.weight(.medium))
                        .foregroundStyle(theme.accent)
                    Spacer()
                    Text(date)
                        .font(ONTUI.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(situe.texte)
                    .font(ONTUI.callout)
                    .foregroundStyle(theme.ink)
                    // Trois lignes : de quoi reconnaître le verset sans que la
                    // liste devienne une lecture. Le toucher mène au texte
                    // entier, qui est le bon endroit pour le lire.
                    .lineLimit(3)
                if let note = situe.surlignage.note, !note.isEmpty {
                    Text(note)
                        .font(ONTUI.footnote.italic())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        // Une seule annonce pour la ligne entière : sans ça VoiceOver lit le
        // renvoi, la date, le texte et la note comme quatre éléments à parcourir
        // un à un.
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ouvre le passage")
    }
}

private struct FiltreDeCouleur: View {
    let couleurs: [(HighlightColor, Int)]
    @Binding var choisie: HighlightColor?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Pastille(titre: "Tout", couleur: nil, actif: choisie == nil) { choisie = nil }
                ForEach(couleurs, id: \.0) { couleur, n in
                    Pastille(
                        titre: "\(couleur.label) \(n)", couleur: couleur,
                        actif: choisie == couleur
                    ) {
                        // Retoucher la couleur active la retire : sans ça, on
                        // ne revient à « tout » qu'en visant une pastille
                        // précise, alors qu'on vient de toucher celle-ci.
                        choisie = choisie == couleur ? nil : couleur
                    }
                }
            }
            .padding(.vertical, 2)
        }
        // Le défilement horizontal ne doit pas manger la marge de la ligne.
        .scrollClipDisabled()
    }
}

private struct Pastille: View {
    @Environment(\.ontTheme) private var theme
    let titre: String
    let couleur: HighlightColor?
    let actif: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let couleur {
                    Circle()
                        .fill(ONTColors.highlight(couleur, theme.mode))
                        .frame(width: 9, height: 9)
                }
                Text(titre).font(ONTUI.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(
                    actif ? theme.accent.opacity(0.16) : theme.ink.opacity(0.06))
            )
            .overlay(
                Capsule().stroke(actif ? theme.accent : .clear, lineWidth: 1)
            )
            .foregroundStyle(actif ? theme.accent : theme.ink)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(actif ? [.isButton, .isSelected] : .isButton)
    }
}

private struct Rien: View {
    let filtre: HighlightColor?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // **Deux vides différents, deux phrases différentes.** « Aucun
            // surlignage » sous un filtre actif ferait croire qu'on n'a jamais
            // rien marqué, alors qu'on vient d'en cacher.
            if let filtre {
                Text("Rien en \(filtre.label.lowercased())")
                    .font(ONTUI.callout.weight(.medium))
                Text("Touchez « Tout » pour revoir les autres couleurs.")
                    .font(ONTUI.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Aucun surlignage")
                    .font(ONTUI.callout.weight(.medium))
                Text(
                    "Touchez un verset pendant la lecture, puis choisissez une "
                        + "couleur. Ce que vous marquez se retrouve ici."
                )
                .font(ONTUI.footnote)
                .foregroundStyle(.secondary)
                    .font(ONTUI.ligneDeListe)
            }
        }
        .padding(.vertical, 6)
    }
}
