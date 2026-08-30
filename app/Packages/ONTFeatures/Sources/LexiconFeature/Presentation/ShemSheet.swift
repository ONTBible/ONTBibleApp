import ONTDesignSystem
import ONTKit
import SwiftUI

/// La fiche d'un **Shem** — un porteur de nom.
///
/// **Plus sobre que celle d'un intraduisible, et c'est voulu.** Une fiche de
/// concept porte des repères qu'un nom propre n'a pas : la traduction arrêtée,
/// les formes dérivées, la règle de balisage, le décompte des gloses. Les
/// afficher vides ferait un écran qui promet ce qu'il n'a pas.
///
/// Ce qu'elle porte, elle, est sa **structure** : quatre à six mouvements — la
/// racine, le porteur, ce qu'il fait ailleurs dans le corpus, ce que son nom
/// porte après lui, et les renvois. D'où les titres de section, que les fiches
/// d'intraduisibles n'ont pas.
public struct ShemSheet: View {
    @Environment(\.ontTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    /// Posé par la présentation quand ce n'est pas une feuille — voir
    /// `ONTFermeture`. `dismiss` ne ferme ni un panneau latéral ni un
    /// aperçu en surimpression.
    @Environment(\.ontFermer) private var fermer

    let lemma: String
    private let shemot: any ShemotRepository

    public init(lemma: String, shemot: any ShemotRepository) {
        self.lemma = lemma
        self.shemot = shemot
    }

    private var entree: ShemEntry? {
        try? shemot.entries().first { $0.lemma == lemma }
    }

    public var body: some View {
        NavigationStack {
            List {
                if let entree {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entree.title)
                                .font(.custom(ONTFonts.display, size: ONTUI.points(26)))
                                // La terre brûlée, la même qu'en lecture : le
                                // lecteur doit reconnaître la couleur qu'il
                                // vient de toucher.
                                .foregroundStyle(ONTColors.shem(theme.mode))
                            Text("Nom propre")
                                .font(ONTUI.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                    .ontRow()

                    Section("Ce que son nom porte") {
                        if entree.sansDefinition {
                            // Même garde que pour un intraduisible : un écran
                            // qui montre un en-tête et rien dessous a l'air
                            // complet.
                            Text(
                                "Ce nom est balisé dans le texte, mais sa fiche "
                                    + "n'est pas encore écrite."
                            )
                            .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(entree.definition.enumerated()), id: \.offset) {
                                _, block in
                                BlocDeFiche(block: block)
                            }
                        }
                    }
                    .ontRow()
                } else {
                    Section {
                        // Un lemme qu'aucune fiche ne porte : le corpus et
                        // `shemot.json` ont divergé. On le **dit**, plutôt que
                        // d'ouvrir une feuille vide dont personne ne saurait
                        // qu'elle a échoué.
                        ContentUnavailableView(
                            "Fiche introuvable",
                            systemImage: "questionmark.circle",
                            description: Text(
                                "Le nom « \(lemma) » est balisé dans le texte, "
                                    + "mais aucune fiche ne lui correspond."
                            )
                        )
                    }
                    .ontRow()
                }
            }
            .listStyle(.plain)
            .ontScreen()
            .ontTitreCompact()
            .toolbar {
                // Voir `TermSheet` : quand la présentation porte sa propre
                // croix, un second « Fermer » part se poser dans la barre de
                // titre de la fenêtre, loin de ce qu'il ferme.
                if fermer == nil {
                    ToolbarItem(placement: ONTPlacement.principale) {
                        Button("Fermer") { dismiss() }
                    }
                }
            }
        }
        .ontHauteurDeFeuille([.medium, .large])
    }
}
