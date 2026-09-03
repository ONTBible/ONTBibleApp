import SwiftUI

// MARK: - Une modale, rendue comme sa plateforme l'entend

/// ## Pourquoi une feuille du système ne convient pas au Mac
///
/// `.sheet` est juste sur l'iPhone : elle monte du bas, on la retire d'un doigt,
/// et le système l'habille. Sur le Mac elle donne autre chose — deux défauts
/// relevés à l'écran, et aucun n'est réparable depuis le contenu :
///
/// - **le bandeau du bas n'est pas à nous.** Un `ToolbarItem(.confirmationAction)`
///   posé dans une feuille du Mac descend dans une barre qu'AppKit dessine, en
///   gris du système, sous une carte qui porte l'aubergine. Rien ne le peint :
///   ni `presentationBackground`, ni le thème — la barre est hors de la vue.
/// - **le clic à côté ne ferme rien.** Une feuille du Mac est modale à sa
///   fenêtre, par construction : il n'existe pas d'API pour la refermer d'un
///   clic dehors. C'est une propriété de la présentation, pas un réglage.
///
/// D'où celle-ci : sur iOS on garde `.sheet` telle quelle, sur le Mac on dessine
/// la carte nous-mêmes, avec le voile qui la ferme et la chrome du projet.
///
/// ## Pourquoi la carte se rend à la racine, et non là où on l'appelle
///
/// Une surimpression posée à l'endroit de l'appel ne couvrirait que la vue qui
/// l'appelle — donc, dans un `NavigationSplitView`, la colonne de détail seule.
/// Le voile s'arrêterait au bord de la barre latérale, qui resterait allumée et
/// cliquable pendant qu'une modale est ouverte.
///
/// Les appels déposent donc leur contenu dans une pile que la racine porte, et
/// c'est la racine qui les dessine. `ONTFeuilles` est ce dépôt.
@Observable
@MainActor
public final class ONTFeuilles {
    /// Une modale posée, telle que la racine la retrouvera.
    struct Posee: Identifiable {
        let id: UUID
        let titre: String?
        let contenu: () -> AnyView
        let fermer: ONTFermeture
    }

    private(set) var posees: [Posee] = []

    /// Celle que la racine dessine.
    ///
    /// La **dernière** posée passe devant : une fiche ouverte par-dessus des
    /// réglages se lit dans cet ordre-là. Nommée plutôt qu'écrite au point de
    /// rendu, pour qu'une épreuve puisse porter sur le choix lui-même — un
    /// `.first` glissé là se lirait comme une modale qui ne s'ouvre pas.
    var aDessiner: Posee? { posees.last }

    public init() {}

    func poser(
        titre: String?, contenu: @escaping () -> AnyView, fermer: @escaping @MainActor () -> Void
    ) -> UUID {
        let id = UUID()
        posees.append(Posee(id: id, titre: titre, contenu: contenu, fermer: ONTFermeture(fermer)))
        return id
    }

    func retirer(_ id: UUID) {
        posees.removeAll { $0.id == id }
    }
}

extension View {
    /// La racine porte les modales que les vues déposent.
    ///
    /// À poser **une fois**, au plus haut : c'est ce qui donne au voile toute la
    /// fenêtre. Sans elle, `ontFeuille` retombe sur `.sheet` — donc sur une
    /// carte qui garde sa chrome mais perd le clic à côté, jamais sur rien.
    public func ontPorteLesFeuilles(_ feuilles: ONTFeuilles) -> some View {
        modifier(PorteLesFeuilles(feuilles: feuilles))
    }

    /// Une modale, présentée comme sa plateforme l'entend.
    ///
    /// `titre` n'est lu que sur le Mac, où la carte porte sa propre barre de
    /// tête. Sur iOS le contenu garde la sienne.
    public func ontFeuille<Contenu: View>(
        presentee: Binding<Bool>,
        titre: String? = nil,
        @ViewBuilder contenu: @escaping () -> Contenu
    ) -> some View {
        modifier(Feuille(presentee: presentee, titre: titre, contenu: contenu))
    }

    /// La même, pour une modale que son objet ouvre et ferme.
    public func ontFeuille<Objet: Identifiable, Contenu: View>(
        objet: Binding<Objet?>,
        titre: String? = nil,
        @ViewBuilder contenu: @escaping (Objet) -> Contenu
    ) -> some View {
        modifier(FeuilleDObjet(objet: objet, titre: titre, contenu: contenu))
    }

    /// La chrome qu'une feuille d'iOS doit porter, et que la carte du Mac porte
    /// déjà.
    ///
    /// **La pile et son bouton appartiennent à la présentation, pas au contenu**
    /// — la même vue de réglages est aussi *poussée* depuis « Vous », dans une
    /// pile qui existe déjà. Sur le Mac, les poser serait pire qu'inutile : un
    /// `NavigationStack` dans une surimpression projette sa barre d'outils dans
    /// la **barre de titre de la fenêtre**, et le bouton va s'asseoir tout en
    /// haut à droite, loin de la carte qu'il ferme.
    public func ontChromeDeFeuille(
        _ titre: String, fermer: @escaping () -> Void
    ) -> some View {
        #if os(macOS)
            return self
        #else
            return NavigationStack {
                self.toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(titre, action: fermer)
                    }
                }
            }
        #endif
    }
}

// MARK: - Le dépôt et son rendu

private struct PorteLesFeuilles: ViewModifier {
    let feuilles: ONTFeuilles

    func body(content: Content) -> some View {
        #if os(macOS)
            content
                .environment(feuilles)
                .overlay {
                    if let derniere = feuilles.aDessiner {
                        VoileEtCarte(
                            titre: derniere.titre, fermer: { derniere.fermer() },
                            contenu: derniere.contenu
                        )
                        .id(derniere.id)
                    }
                }
                .animation(.easeOut(duration: 0.16), value: feuilles.posees.count)
        #else
            content.environment(feuilles)
        #endif
    }
}

// MARK: - Le modificateur, des deux côtés

private struct Feuille<Contenu: View>: ViewModifier {
    @Binding var presentee: Bool
    let titre: String?
    @ViewBuilder let contenu: () -> Contenu

    #if os(macOS)
        @Environment(ONTFeuilles.self) private var depot: ONTFeuilles?
        @State private var jeton: UUID?
    #endif

    func body(content: Content) -> some View {
        #if os(macOS)
            if let depot {
                content
                    .onChange(of: presentee, initial: true) { _, ouverte in
                        accorder(depot, ouverte)
                    }
                    // Une vue qui disparaît avec sa modale ouverte la laisserait
                    // sur la fenêtre, sans plus personne pour la refermer.
                    .onDisappear {
                        if let j = jeton { depot.retirer(j); jeton = nil }
                    }
            } else {
                content.sheet(isPresented: $presentee) {
                    CarteDeFeuille(titre: titre, fermer: { presentee = false }, contenu: contenu)
                        .frame(minWidth: 620, minHeight: 520)
                }
            }
        #else
            content.sheet(isPresented: $presentee, content: contenu)
        #endif
    }

    #if os(macOS)
        private func accorder(_ depot: ONTFeuilles, _ ouverte: Bool) {
            if ouverte, jeton == nil {
                let bati = contenu
                jeton = depot.poser(titre: titre) { AnyView(bati()) } fermer: { presentee = false }
            } else if !ouverte, let j = jeton {
                depot.retirer(j)
                jeton = nil
            }
        }
    #endif
}

private struct FeuilleDObjet<Objet: Identifiable, Contenu: View>: ViewModifier {
    @Binding var objet: Objet?
    let titre: String?
    @ViewBuilder let contenu: (Objet) -> Contenu

    #if os(macOS)
        @Environment(ONTFeuilles.self) private var depot: ONTFeuilles?
        @State private var jeton: UUID?
        @State private var ouvert: Objet.ID?
    #endif

    func body(content: Content) -> some View {
        #if os(macOS)
            if let depot {
                content
                    // Sur l'identifiant et non sur l'objet : celui-ci n'est pas
                    // forcément `Equatable`, et c'est son identité qui décide si
                    // la carte doit changer de contenu.
                    .onChange(of: objet?.id, initial: true) { _, id in
                        accorder(depot, id)
                    }
                    .onDisappear {
                        if let j = jeton { depot.retirer(j); jeton = nil }
                    }
            } else {
                content.sheet(item: $objet) { choisi in
                    CarteDeFeuille(titre: titre, fermer: { objet = nil }) { contenu(choisi) }
                        .frame(minWidth: 620, minHeight: 520)
                }
            }
        #else
            content.sheet(item: $objet, content: contenu)
        #endif
    }

    #if os(macOS)
        private func accorder(_ depot: ONTFeuilles, _ id: Objet.ID?) {
            guard id != ouvert else { return }
            if let j = jeton { depot.retirer(j); jeton = nil }
            ouvert = id
            guard let choisi = objet else { return }
            let bati = contenu
            jeton = depot.poser(titre: titre) { AnyView(bati(choisi)) } fermer: { objet = nil }
        }
    #endif
}

// MARK: - La carte du Mac

#if os(macOS)

    /// Le voile, la carte, et de quoi la refermer de trois façons — le clic à
    /// côté, la croix, ⎋.
    private struct VoileEtCarte<Contenu: View>: View {
        let titre: String?
        let fermer: @MainActor () -> Void
        @ViewBuilder let contenu: () -> Contenu

        @Environment(\.ontTheme) private var theme

        var body: some View {
            ZStack {
                // Le voile assombrit sans effacer — on doit voir qu'on est
                // toujours dans son chapitre. Les mêmes valeurs que l'aperçu de
                // fiche, qui fait déjà ça sur cette fenêtre.
                Rectangle()
                    .fill(.black.opacity(theme.mode.isDark ? 0.46 : 0.24))
                    .ignoresSafeArea()
                    .onTapGesture(perform: fermer)
                    .transition(.opacity)

                GeometryReader { geo in
                    CarteDeFeuille(titre: titre, fermer: fermer, contenu: contenu)
                        .frame(
                            // Assez large pour qu'une glose tienne sur une
                            // ligne, borné pour qu'elle ne s'étale pas sur un
                            // grand écran : au-delà, l'œil perd le début de la
                            // ligne suivante.
                            width: min(max(geo.size.width * 0.66, 460), 860),
                            height: min(geo.size.height * 0.84, 900))
                        .background(theme.background, in: .rect(cornerRadius: ONTRadius.card))
                        .clipShape(.rect(cornerRadius: ONTRadius.card))
                        .overlay {
                            RoundedRectangle(cornerRadius: ONTRadius.card)
                                .strokeBorder(theme.separator, lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.28), radius: 30, y: 12)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
                .transition(.scale(scale: 0.97).combined(with: .opacity))
            }
            // ⎋ ferme aussi. Un bouton invisible, parce que `keyboardShortcut`
            // s'attache à une commande et qu'il n'y a pas de commande à montrer.
            .background {
                Button("", action: fermer)
                    .keyboardShortcut(.escape, modifiers: [])
                    .opacity(0)
            }
        }
    }

    /// La barre de tête et le contenu — ce que la surimpression et la feuille de
    /// secours partagent.
    ///
    /// Elle existe aussi pour la seconde, et c'est le point : même quand le
    /// dépôt manque et qu'on retombe sur `.sheet`, **le bandeau gris d'AppKit
    /// n'apparaît pas**. On perd le clic à côté, jamais la peau.
    private struct CarteDeFeuille<Contenu: View>: View {
        let titre: String?
        let fermer: @MainActor () -> Void
        @ViewBuilder let contenu: () -> Contenu

        @Environment(\.ontTheme) private var theme
        private var espace = ONTSpacing()

        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: espace.xs) {
                    if let titre {
                        Text(titre)
                            .font(.custom(ONTFonts.navigation, size: ONTUI.points(13)))
                            .foregroundStyle(theme.ink)
                    }
                    Spacer(minLength: 0)
                    BoutonDeFermeture(action: fermer)
                }
                .padding(.horizontal, espace.s)
                .padding(.vertical, espace.xs + 2)
                Divider()
                contenu()
                    // Le contenu porte souvent son propre « Fermer », et celui-ci
                    // appelle `dismiss` — qui ne ferme pas une surimpression. On
                    // lui dit donc comment, et il s'efface quand la présentation
                    // en a déjà un.
                    .environment(\.ontFermer, ONTFermeture(fermer))
            }
            .background(theme.background)
        }
    }

    /// La croix de la barre de tête — discrète au repos, marquée au survol.
    private struct BoutonDeFermeture: View {
        let action: @MainActor () -> Void

        @Environment(\.ontTheme) private var theme
        @State private var survolé = false
        private var échelle = ONTScaled()

        var body: some View {
            Button(action: action) {
                Image(systemName: "xmark")
                    .font(.system(size: échelle(12), weight: .medium))
                    .frame(width: échelle(26), height: échelle(26))
                    .foregroundStyle(survolé ? theme.ink : theme.ink.opacity(0.55))
                    .background(
                        survolé ? theme.ink.opacity(0.09) : .clear,
                        in: .rect(cornerRadius: ONTRadius.highlight))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Fermer")
            .accessibilityLabel("Fermer")
            .onHover { survolé = $0 }
            .animation(.easeOut(duration: 0.12), value: survolé)
        }
    }

#endif
