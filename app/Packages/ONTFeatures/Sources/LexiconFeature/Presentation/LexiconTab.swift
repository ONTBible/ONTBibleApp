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
    @State private var nomChoisi: NomSelectionne?
    @State private var feuilleOuverte = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollViewReader { defilement in
            List {
                // **Le hero, entre le bascule et le premier mot.**
                //
                // Sa place n'est pas décorative : ce qu'il ouvre doit être lu
                // *avant* la première fiche, et une ligne de plus au milieu de
                // trois cent trente-quatre entrées ne serait jamais touchée.
                Section {
                    HeroDePrononciation { feuilleOuverte = true }
                        .listRowInsets(.init(top: 4, leading: 16, bottom: 10, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

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
                if scope.montreLesNoms {
                    // **Les Shemot ne passent pas par le même rang.**
                    //
                    // Un Shem n'est pas une entrée de glossaire : pas de forme
                    // rendue, pas d'hébreu de lemme, pas de familles de formes.
                    // Fabriquer une `GlossaryEntry` à partir de lui pour
                    // réutiliser la rangée mentirait sur le type, et le
                    // mensonge se paierait à la première colonne qu'on ajoute.
                    //
                    // Mais les **sections par lettre** sont les mêmes : c'est
                    // elles que le rail vise, et sans elles il disparaît.
                    ForEach(tranchesDeNoms) { tranche in
                        Section {
                            ForEach(Array(tranche.entrees.enumerated()), id: \.element.id) {
                                rang, nom in
                                Button {
                                    nomChoisi = NomSelectionne(nom.lemma)
                                } label: {
                                    RangeeDeNom(nom: nom)
                                        .contentShape(.rect)
                                        .ontCarteDeLigne()
                                }
                                .buttonStyle(.ontLigne)
                                .ontLigneDeCarte()
                                .ontApparition(rang)
                            }
                        } header: {
                            Text(tranche.lettre)
                                .font(ONTUI.footnote.weight(.semibold))
                                .foregroundStyle(theme.accent)
                                .accessibilityAddTraits(.isHeader)
                        }
                        .id(tranche.lettre)
                    }
                } else {
                ForEach(tranches) { tranche in
                    Section {
                        ForEach(Array(tranche.entrees.enumerated()), id: \.element.id) { rang, entry in
                            Button {
                                selected = LemmaSelection(entry.lemma)
                            } label: {
                                EntryRow(entry: entry)
                                    // Toute la rangée répond, pas seulement les
                                    // lettres : un `HStack` ne définit aucune
                                    // forme tactile, seul le dessin des glyphes
                                    // est touché.
                                    .contentShape(.rect)
                                    // La carte du Mac — survol, pression, bord
                                    // à bord. Inerte sur iOS.
                                    .ontCarteDeLigne()
                            }
                            .buttonStyle(.ontLigne)
                            .ontLigneDeCarte()
                            .ontApparition(rang)
                        }
                    } header: {
                        Text(tranche.lettre)
                            .font(ONTUI.footnote.weight(.semibold))
                            .foregroundStyle(theme.accent)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .id(tranche.lettre)
                }
                }
            }
            .ontListeDIndex()
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
                    ONTRailDeLettres(lettres: lettresDuRail) { lettre in
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
            .ontFeuille(objet: $selected) { selection in
                TermSheet(lemma: selection.id)
            }
            // La feuille des Shemot existe déjà, et c'est elle qu'il faut :
            // une fiche de nom propre a quatre à six mouvements là où une
            // fiche d'intraduisible est un bloc de définition.
            .ontFeuille(objet: $nomChoisi) { choix in
                ShemSheet(lemma: choix.id, shemot: model.depotDesNoms)
            }
            .ontFeuille(presentee: $feuilleOuverte, titre: "Prononciation") {
                FeuilleDePrononciationView(feuille: model.prononciation)
            }
            .overlay {
                if scope.montreLesNoms ? nomsFiltres.isEmpty : filtered.isEmpty {
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
        let sections = scope.montreLesNoms ? tranchesDeNoms.count : tranches.count
        let entrees = scope.montreLesNoms ? nomsFiltres.count : filtered.count
        return search.isEmpty && sections > 1 && entrees >= 20
    }

    /// Les entrées découpées par lettre, dans l'ordre où le modèle les rend.
    /// Les noms propres que la recherche laisse passer — vides hors du bascule
    /// des Shemot, pour que rien ne se calcule quand rien ne s'affiche.
    private var nomsFiltres: [ShemEntry] {
        scope.montreLesNoms ? model.nomsFiltres(search: search) : []
    }

    private var tranches: [TrancheAlphabetique<GlossaryEntry>] {
        IndexAlphabetique.trancher(filtered) { $0.title }
    }

    /// Les noms propres découpés par lettre, **par le même découpeur**.
    ///
    /// Ils l'étaient d'abord en liste plate, et le rail disparaissait sous le
    /// bascule des Shemot : il n'avait plus de cible à viser. Or c'est là qu'il
    /// sert le plus — deux cent soixante-treize noms contre soixante et un
    /// termes.
    private var tranchesDeNoms: [TrancheAlphabetique<ShemEntry>] {
        IndexAlphabetique.trancher(nomsFiltres) { $0.title }
    }

    /// Les lettres que le rail propose — celles de la liste **affichée**.
    ///
    /// Sans ça il porterait les lettres des termes pendant qu'on parcourt les
    /// noms : des cibles qui n'existent pas, et un saut qui ne saute nulle
    /// part.
    private var lettresDuRail: [String] {
        scope.montreLesNoms ? tranchesDeNoms.map(\.lettre) : tranches.map(\.lettre)
    }
}

private struct EntryRow: View {
    @Environment(\.ontTheme) private var theme

    let entry: GlossaryEntry

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(ONTUI.body.weight(.medium))
                    .foregroundStyle(entry.tagged ? ONTColors.brandInk(theme.mode) : theme.ink)

                if let rendering = entry.rendering, rendering != entry.title {
                    Text(rendering)
                        .font(ONTUI.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if let hebrew = entry.hebrew {
                Text(hebrew)
                    .font(.custom(ONTFonts.hebrew, size: ONTUI.points(21)))
                    .foregroundStyle(.secondary)
            }

            if entry.count > 0 {
                Text("\(entry.count)")
                    .font(ONTUI.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 28, alignment: .trailing)
            }
        }
        .padding(.vertical, 3)
        .contentShape(.rect)
    }
}

/// Le lemme d'un Shem choisi — `Identifiable` pour que la feuille se repose
/// quand on passe d'un nom à l'autre sans la refermer.
struct NomSelectionne: Identifiable {
    let id: String
    init(_ lemme: String) { id = lemme }
}

/// Une rangée de nom propre.
///
/// Plus dépouillée que celle d'un terme, et c'est le sujet : un Shem n'a ni
/// forme rendue ni famille de formes. Y afficher des colonnes vides ferait
/// croire à une fiche incomplète.
private struct RangeeDeNom: View {
    @Environment(\.ontTheme) private var theme
    let nom: ShemEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(nom.title)
                .font(ONTUI.body)
                .foregroundStyle(ONTColors.shem(theme.mode))
            Spacer(minLength: 0)
        }
    }
}
