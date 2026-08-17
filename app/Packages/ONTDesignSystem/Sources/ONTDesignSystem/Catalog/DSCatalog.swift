import ONTKit
import SwiftUI

/// Le catalogue du design system.
///
/// Documentation vivante : chaque jeton et chaque composant a sa section ici.
/// **Un composant ajouté sans sa ligne de catalogue est un composant qu'on
/// oubliera** — ajoutez-la dans le même commit.
///
/// Accessible depuis l'onglet « Vous » en build de développement, et
/// directement dans le canevas d'aperçu de Xcode.
public struct DSCatalog: View {
    public init() {}

    public var body: some View {
        List {
            Section("Jetons") {
                NavigationLink("Couleurs", destination: CatalogColors())
                NavigationLink("Typographie", destination: CatalogTypography())
                NavigationLink("Espacement et rayons", destination: CatalogMetrics())
            }
            Section("Composants") {
                NavigationLink("Surfaces", destination: CatalogSurfaces())
                NavigationLink("Fond d'écran", destination: CatalogScreen())
                NavigationLink("Rendu du texte ONT", destination: CatalogText())
            }
            Section("Contrôle") {
                NavigationLink("Fontes embarquées", destination: CatalogFonts())
            }
        }
        .ontScreen()
        .navigationTitle("Design system")
    }
}

/// La règle du fond d'écran, démontrée.
struct CatalogScreen: View {
    var body: some View {
        List {
            Section {
                Text("Cet écran porte `.ontScreen()`.")
                Text("Chaque ligne porte `.ontRow()`.")
            } header: {
                Text("Ce que vous voyez")
            } footer: {
                Text(
                    "Sans ces deux modificateurs, une List impose son propre fond système "
                        + "et l'écran cesse de ressembler au reste de l'app. C'est le défaut "
                        + "qui rendait les quatre onglets dissemblables malgré le design system."
                )
            }
            .ontRow()
        }
        .ontScreen()
        .navigationTitle("Fond d'écran")
    }
}

// MARK: - Couleurs

struct CatalogColors: View {
    var spacing = ONTSpacing()

    var body: some View {
        List {
            Section("Marque — relevées sur le combination mark") {
                swatch("burgundy", ONTColors.burgundy)
                swatch("gold", ONTColors.gold)
                swatch("goldDeep", ONTColors.goldDeep)
            }
            ForEach(ReadingTheme.allCases, id: \.self) { theme in
                Section("Lecture — \(theme.label)") {
                    swatch("background", ONTColors.background(theme))
                    swatch("surface", ONTColors.surface(theme))
                    swatch("ink", ONTColors.ink(theme))
                    swatch("accent", ONTColors.accent(theme))
                    swatch("separator", ONTColors.separator(theme))
                }
            }
            Section("Surlignage") {
                ForEach(HighlightColor.allCases, id: \.self) { color in
                    swatch(color.label, ONTColors.highlight(color))
                }
            }
        }
        .navigationTitle("Couleurs")
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        HStack(spacing: spacing.m) {
            RoundedRectangle(cornerRadius: ONTRadius.highlight)
                .fill(color)
                .frame(width: 44, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: ONTRadius.highlight)
                        .stroke(.quaternary)
                )
            Text(name).font(.callout.monospaced())
        }
    }
}

// MARK: - Typographie

struct CatalogTypography: View {
    @Environment(\.ontTheme) private var theme

    var body: some View {
        List {
            Section("Les six styles, adossés aux niveaux du texte (§2.1)") {
                row("display", "Bereshit 18", theme.type.display)
                row("heading", "L'Annonce de Yitshaq", theme.type.heading)
                row("corpus", "et il était assis à l'entrée de la tente", theme.type.corpus)
                row("term", "chesed", theme.type.term)
                row("gloss", "niphal de ra'ah — mode de la révélation", theme.type.gloss)
                row("translit", "vayera elav YHWH", theme.type.translit)
                row("hebrew", "וַיֵּרָא אֵלָיו יְהוָה", theme.type.hebrew)
            }
        }
        .navigationTitle("Typographie")
    }

    private func row(_ name: String, _ sample: String, _ style: ONTTextStyle) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.caption.monospaced()).foregroundStyle(.tertiary)
            Text(sample).font(style.font).foregroundStyle(style.color)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Métriques

struct CatalogMetrics: View {
    var spacing = ONTSpacing()

    var body: some View {
        List {
            Section {
                bar("xs", spacing.xs)
                bar("s", spacing.s)
                bar("m", spacing.m)
                bar("l", spacing.l)
                bar("page", spacing.page)
                bar("xl", spacing.xl)
                bar("xxl", spacing.xxl)
            } header: {
                Text("Espacement")
            } footer: {
                Text(
                    "Ces valeurs suivent Dynamic Type : elles grandissent avec le réglage "
                        + "système de taille de police. Changez-le dans Réglages pour les voir bouger."
                )
            }
        }
        .navigationTitle("Espacement")
    }

    private func bar(_ name: String, _ value: CGFloat) -> some View {
        HStack {
            Text(name).font(.callout.monospaced()).frame(width: 52, alignment: .leading)
            Rectangle().fill(ONTColors.goldDeep).frame(width: value, height: 14)
            Text("\(Int(value)) pt").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Surfaces

struct CatalogSurfaces: View {
    var spacing = ONTSpacing()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing.xl) {
                BurgundyCard {
                    VStack(alignment: .leading, spacing: spacing.s) {
                        SectionCaption("Verset du jour", tint: ONTColors.gold)
                        Text("Et il advint, et demeura conformément à ce qui avait été formulé.")
                    }
                }
                QuietBlock {
                    Text("Un bloc secondaire, en retrait.")
                }
                HStack(spacing: spacing.s) {
                    StatusPill("brouillon")
                    StatusPill("glose", tint: .gray)
                }
                GoldRule()
            }
            .padding(spacing.page)
        }
        .navigationTitle("Surfaces")
    }
}

// MARK: - Rendu du texte

struct CatalogText: View {
    @Environment(\.ontTheme) private var theme

    /// *Bereshit* 18:1, reconstitué à la main — le catalogue ne doit pas
    /// dépendre du corpus embarqué.
    private var sample: [Inline] {
        [
            .term("YHWH", lemma: "yhwh"),
            .text(" se laissa voir "),
            .translit("vayera elav YHWH", hebrew: "וַיֵּרָא אֵלָיו יְהוָה"),
            .text(" "),
            .gloss([
                .text("niphal de "),
                .emphasis([.text("ra'ah")]),
                .text(" — l'initiative appartient à "),
                .term("YHWH", lemma: "yhwh"),
                .text("."),
            ]),
            .text(" par lui."),
        ]
    }

    var body: some View {
        List {
            Section("Les trois niveaux") {
                Text(ONTTextRenderer.compose(sample, theme: theme))
            }
            Section("Corps seul — gloses et hébreu éteints") {
                Text(ONTTextRenderer.composeBare(sample, theme: theme))
            }
        }
        .navigationTitle("Texte ONT")
    }
}

// MARK: - Contrôle des fontes

struct CatalogFonts: View {
    var body: some View {
        List {
            LabeledContent("Ezra SIL (hébreu)") {
                Label(
                    ONTFonts.hebrewAvailable ? "embarquée" : "ABSENTE",
                    systemImage: ONTFonts.hebrewAvailable ? "checkmark.circle" : "xmark.octagon"
                )
                .foregroundStyle(ONTFonts.hebrewAvailable ? .green : .red)
            }
            LabeledContent("Literata (corps)") {
                Label(
                    ONTFonts.bodyAvailable ? "trois coupes" : "COUPES MANQUANTES",
                    systemImage: ONTFonts.bodyAvailable ? "checkmark.circle" : "xmark.octagon"
                )
                .foregroundStyle(ONTFonts.bodyAvailable ? .green : .red)
            }
            Section {
                Text("אֵשֶׁת חַיִל מִי יִמְצָא")
                    .font(.custom(ONTFonts.hebrew, size: 34))
            } header: {
                Text("Échantillon vocalisé")
            } footer: {
                Text(
                    "Si les points-voyelles se décrochent des consonnes, la fonte n'est pas "
                        + "chargée et l'hébreu retombe sur une fonte système."
                )
            }
        }
        .navigationTitle("Fontes")
    }
}

#Preview {
    NavigationStack { DSCatalog() }
        .ontTheme(from: .default)
}
