import SwiftUI

/// Le champ de recherche d'une carte — capsule, loupe, focus d'office.
///
/// **Pourquoi il existe alors que `.searchable` existe.** `.searchable` est un
/// vœu adressé à la barre d'outils la plus proche ; dans une surimpression du
/// Mac, c'est celle de la **fenêtre** — le champ de la carte de recherche est
/// allé s'asseoir en haut à droite de l'écran, hors de la carte qui contenait
/// tout le reste. Mesuré sur capture, le 3 septembre 2026. Sur iOS, où la
/// feuille du système donne au vœu la bonne barre, `.searchable` reste le bon
/// choix — ce champ est celui des cartes du Mac.
public struct ONTChampDeRecherche: View {
    @Binding private var texte: String
    private let invite: String

    @Environment(\.ontTheme) private var theme
    @FocusState private var vise: Bool
    private var espace = ONTSpacing()

    public init(_ texte: Binding<String>, invite: String) {
        _texte = texte
        self.invite = invite
    }

    public var body: some View {
        HStack(spacing: espace.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.ink.opacity(0.45))
            TextField(invite, text: $texte)
                .textFieldStyle(.plain)
                .font(ONTUI.body)
                .foregroundStyle(theme.ink)
                .focused($vise)
            if !texte.isEmpty {
                Button {
                    texte = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.ink.opacity(0.35))
                }
                .buttonStyle(.ontPresse)
            }
        }
        .padding(.horizontal, espace.m)
        .padding(.vertical, espace.s)
        .background(theme.surface, in: .capsule)
        // On vient ici pour taper : le champ prend le clavier tout seul, comme
        // la barre de l'iPhone quand la feuille monte.
        .defaultFocus($vise, true)
        .task { vise = true }
    }
}
