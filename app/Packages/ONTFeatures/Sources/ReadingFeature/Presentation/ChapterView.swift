import ONTDesignSystem
import ONTKit
import SwiftUI

/// L'identité d'un verset pour le défilement.
///
/// Un **type dédié**, et c'est tout l'intérêt : les blocs d'une unité sont
/// identifiés par leur rang, un entier. Un `.id(verse.n)` entier vivait donc
/// dans le même espace de noms, et `scrollTo(20)` atteignait le **bloc** n° 20
/// au lieu du **verset** 20 — soit, les intertitres s'intercalant, le verset
/// 14. Le défilement paraissait dérailler alors qu'il visait juste, mais autre
/// chose.
private struct VerseAnchor: Hashable {
    let n: Int
}

/// La lecture d'une unité ONT.
struct ChapterView: View {
    @Environment(ReadingModel.self) private var model
    @Environment(Router.self) private var router
    @Environment(\.ontTheme) private var theme

    private var spacing = ONTSpacing()

    @State private var showingSettings = false
    @State private var showingPicker = false
    @State private var noteTarget: VerseSelection?
    /// Les versets sélectionnés au doigt. État éphémère de la vue : une
    /// sélection ne survit pas au chapitre qu'on quitte, et n'a rien à faire
    /// dans le modèle ni sur le disque.
    @State private var selection: Set<Int> = []
    /// Posé par la pastille « Partager » du widget : l'ouverture enchaîne sur
    /// la feuille de partage sans un geste de plus.
    @State private var autoShare = false
    /// Le suivi de position, éteint tant que la restauration n'a pas eu lieu.
    @State private var tracking = false

    let chapter: Chapter

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ParchmentPage {
                    // `VStack` et non `LazyVStack`, à contre-courant de
                    // l'usage — et vérifié sur appareil, pas supposé.
                    //
                    // Une pile paresseuse ne construit pas les lignes hors
                    // champ, donc leur identité n'existe pas encore et
                    // `scrollTo` ne trouve rien : viser le verset 28 ne
                    // déplaçait la page d'aucun pixel. C'est la seconde moitié
                    // du défaut ; l'autre était la collision d'identités que
                    // `VerseAnchor` résout plus haut.
                    //
                    // Une unité fait quelques dizaines de versets, déjà tous
                    // décodés en mémoire. Les construire d'un coup coûte un
                    // cran au premier affichage et rend le défilement exact.
                    VStack(alignment: .leading, spacing: spacing.xl) {
                        header

                        ForEach(Array(chapter.blocks.enumerated()), id: \.offset) { _, block in
                            BlockView(
                                block: block,
                                chapter: chapter,
                                noteTarget: $noteTarget,
                                selection: $selection
                            )
                        }

                        if let footer = chapter.footer {
                            FooterView(footer: footer).opacity(dim)
                        }
                    }
                    // De la place sous le dernier verset : sinon la barre
                    // d'actions recouvre ce qu'on vient de sélectionner.
                    .padding(.bottom, selection.isEmpty ? 0 : 140)
                }
            }
            // `.task(id:)` et non `.onAppear` : la tâche est **annulée** quand
            // la vue disparaît, donc un défilement en cours ne poursuit pas
            // une page qu'on vient de quitter.
            .task(id: chapter.id) { await restore(using: proxy) }
            // Le cas que `.onAppear` ne couvre pas : demander un autre verset
            // de l'unité **déjà ouverte**. La vue n'apparaît pas une seconde
            // fois, donc rien ne se déclencherait.
            .onChange(of: router.pendingVerse) { _, vise in
                guard vise != nil else { return }
                Task { await restore(using: proxy) }
            }
        }
        // Éteint jusqu'à la restauration : sans ça, les premières lignes
        // écrasent la position avant qu'on ait pu la lire.
        .environment(\.ontTracking, tracking)
        .background(theme.background)
        .safeAreaInset(edge: .bottom) {
            if !selection.isEmpty {
                VerseActionBar(
                    chapter: chapter,
                    selection: $selection,
                    noteTarget: $noteTarget,
                    autoShare: $autoShare
                )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.22), value: selection.isEmpty)
        // Le titre central ne double plus la pastille : il ne sert qu'à
        // porter le renvoi pendant une sélection, comme dans Bible Strong.
        .navigationTitle(selection.isEmpty ? "" : reference)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // La pastille de renvoi, en haut à gauche — le geste de YouVersion
            // et de Bible Strong. Elle dit où l'on est **et** sert de porte :
            // sans elle, aller de Bereshit 1 à Bereshit 18 demande de remonter
            // à la table, replier, déplier, redescendre.
            ToolbarItem(placement: .topBarLeading) {
                Button { showingPicker = true } label: {
                    HStack(spacing: 4) {
                        Text(chapter.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(theme.ink.opacity(0.07)))
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Aller à un autre passage — actuellement \(chapter.title)")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Lecture", systemImage: "textformat.size") { showingSettings = true }
            }
        }
        .sheet(isPresented: $showingPicker) {
            ReferencePicker(current: chapter)
        }
        .sheet(isPresented: $showingSettings) {
            // `.large` en plus : l'aperçu occupe le haut de la feuille, et à
            // grande taille avec les gloses allumées, la mi-hauteur ne laisse
            // plus voir les réglages.
            ReadingSettingsSheet(chapter: chapter)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $noteTarget) { selection in
            NoteEditor(chapter: chapter, verse: selection.id)
        }
    }

    /// Rouvre à l'endroit voulu — le passage d'un lien reçu, un verset visé
    /// par la recherche, sinon là où la lecture s'était arrêtée.
    @MainActor
    private func restore(using proxy: ScrollViewProxy) async {
        // Un lien partagé désigne un passage : on le sélectionne, sinon
        // l'expéditeur a choisi trois versets pour rien et le destinataire
        // doit deviner lesquels.
        if !router.pendingSelection.isEmpty {
            selection = router.pendingSelection
            router.pendingSelection = []
        }
        if router.pendingShare {
            router.pendingShare = false
            autoShare = true
        }

        let vise = router.pendingVerse
            ?? (model.position?.chapterId == chapter.id ? model.position?.verse : nil)
        router.pendingVerse = nil

        guard let vise, vise > 1, let ancre = anchor(for: vise) else {
            // Rien à viser : le suivi peut reprendre tout de suite.
            tracking = true
            return
        }

        // Plusieurs passes, échelonnées au-delà de l'animation de navigation.
        //
        // Une poussée de pile dure environ un demi-seconde, et pendant ce
        // temps la vue de défilement n'a pas sa taille finale : un
        // `scrollTo` y est appliqué puis défait quand la transition se pose.
        // C'est pourquoi le défilement marchait au lancement à froid — pas
        // d'animation — et pas depuis la table des matières.
        //
        // Les passes après 0,6 s ne coûtent rien quand la première a visé
        // juste : viser une position déjà atteinte ne déplace rien.
        for delai in [Duration.zero, .milliseconds(250), .milliseconds(600), .seconds(1)] {
            if delai > .zero { try? await Task.sleep(for: delai) }
            guard !Task.isCancelled else { return }
            proxy.scrollTo(VerseAnchor(n: ancre), anchor: .top)
        }
        // Le suivi ne reprend qu'après : il ne doit pas enregistrer les
        // versets survolés pendant le trajet.
        tracking = true
    }

    /// L'identité à viser pour atteindre un verset.
    ///
    /// En bloc par verset, c'est le verset lui-même. En prose continue il n'y
    /// a plus de vue par verset : un bloc entier est un seul `Text`, et seule
    /// son identité — le numéro de son **premier** verset — existe pour le
    /// défilement. On rabat donc la cible sur le début de son bloc.
    private func anchor(for verse: Int) -> Int? {
        guard theme.preferences.continuous else { return verse }
        for bloc in chapter.blocks {
            guard case .verses(let group) = bloc else { continue }
            if group.contains(where: { $0.n == verse }) { return group.first?.n }
        }
        return nil
    }

    /// L'opacité de ce qui n'est pas sélectionné.
    ///
    /// Le procédé vient de Bible Strong, et il est plus efficace qu'un fond
    /// coloré : au lieu d'ajouter une marque au verset désigné, on retire du
    /// poids à tout le reste. La page entière devient le contraste.
    private var dim: Double { selection.isEmpty ? 1 : 0.32 }

    private var reference: String {
        VerseRange.reference(selection, chapterTitle: chapter.title)
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: spacing.s) {
            Text(chapter.title)
                .font(theme.type.display.font)
                .foregroundStyle(theme.type.display.color)

            if let subtitle = chapter.subtitle {
                HStack(spacing: spacing.s) {
                    // Le pont de navigation : le nom français et le renvoi
                    // biblique, jamais la désignation principale (§2.6).
                    Text(subtitle.french).font(.callout.italic())
                    Text(subtitle.hebrew).font(theme.type.hebrew.font)
                    if let reference = subtitle.reference {
                        Text(reference).font(.callout.monospacedDigit())
                    }
                }
                .foregroundStyle(theme.ink.opacity(0.6))
            }

            if chapter.status == .brouillon {
                Label("Brouillon — en attente de validation", systemImage: "pencil.line")
                    .font(.caption)
                    .foregroundStyle(ONTColors.goldDeep)
                    .padding(.top, spacing.xs)
            }
        }
        .opacity(dim)
        GoldRule().opacity(dim)
    }
}

// MARK: - Le verset

/// L'unité que le lecteur surligne, note et partage.
private struct VerseRow: View {
    @Environment(ReadingModel.self) private var model
    @Environment(\.ontTheme) private var theme
    private var spacing = ONTSpacing()

    let verse: Verse
    let chapter: Chapter
    @Binding var noteTarget: VerseSelection?
    @Binding var selection: Set<Int>

    @Environment(\.ontTracking) private var tracking

    private var highlight: Highlight? {
        model.highlight(chapterId: chapter.id, verse: verse.n)
    }

    private var selected: Bool { selection.contains(verse.n) }

    /// Estompé quand une sélection existe ailleurs. C'est le procédé de Bible
    /// Strong : on ne marque pas le verset désigné, on efface le reste.
    private var dim: Double { selection.isEmpty || selected ? 1 : 0.32 }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing.xs) {
            // Le pointillé passe par le moteur de rendu, pas par un cadre
            // dessiné autour : la sélection épouse ainsi les retours à la
            // ligne, et le dernier mot d'un verset n'entraîne pas une bordure
            // sur toute la largeur.
            Text(ONTTextRenderer.compose(verse: verse, theme: theme, underlined: selected))
                .lineSpacing(theme.lineSpacing)

            if let note = highlight?.note {
                Label(note, systemImage: "text.quote")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.leading, spacing.xs)
            }
        }
        .padding(.horizontal, spacing.xs)
        .padding(.vertical, spacing.xs)
        .background {
            // Le surlignage seul pose une surface colorée : c'est une marque
            // durable que le lecteur a posée. La sélection, elle, n'est qu'un
            // état passager de son doigt — d'où le pointillé plutôt qu'un
            // fond, qui ferait croire qu'on vient de surligner.
            if let color = highlight?.color {
                RoundedRectangle(cornerRadius: ONTRadius.highlight)
                    .fill(ONTColors.highlight(color).opacity(ONTColors.highlightOpacity))
            }
        }
        // Toute la boîte répond, pas seulement les lettres : viser un mot pour
        // désigner un verset serait un jeu d'adresse.
        .opacity(dim)
        .contentShape(.rect)
        .onTapGesture {
            if selected {
                selection.remove(verse.n)
            } else {
                selection.insert(verse.n)
            }
        }
        .id(VerseAnchor(n: verse.n))
        // La **visibilité**, pas l'apparition. Depuis que la pile n'est plus
        // paresseuse, toutes les lignes apparaissent d'un coup au chargement :
        // `onAppear` enregistrait donc le chapitre entier en une fois, et la
        // position ne bougeait plus jamais pendant la lecture. « Reprendre »
        // ramenait à une position vieille de plusieurs sessions.
        .onScrollVisibilityChange(threshold: 0.6) { visible in
            guard visible, tracking else { return }
            model.remember(chapter: chapter, verse: verse.n)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(selected ? "Toucher pour désélectionner" : "Toucher pour sélectionner")
    }
}

// MARK: - La barre d'actions

/// Ce qu'on peut faire d'une sélection de versets.
///
/// Elle remplace le menu contextuel par appui long : un menu ne peut agir que
/// sur le verset qu'on tient, alors qu'on surligne souvent un passage. C'est
/// le geste de YouVersion et de Bible Strong — on désigne, puis on agit.
private struct VerseActionBar: View {
    @Environment(ReadingModel.self) private var model
    @Environment(\.ontTheme) private var theme
    private var spacing = ONTSpacing()

    let chapter: Chapter
    @Binding var selection: Set<Int>
    @Binding var noteTarget: VerseSelection?
    /// Vrai quand l'ouverture vient de la pastille du widget.
    @Binding var autoShare: Bool

    /// Ce qui part dans la feuille de partage. Rempli à l'appui, pas avant :
    /// rendre une image de 1080 × 1080 à chaque verset touché serait du
    /// gaspillage pur.
    @State private var partage: ONTShareItem?

    var body: some View {
        VStack(spacing: 18) {
            poignee
            couleurs
            actions
        }
        .padding(.top, 10)
        .padding(.bottom, 14)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background {
            // Une fenêtre posée sur la page, détachée des quatre bords : le
            // texte continue de courir derrière elle, et la carte se lit comme
            // un objet qu'on peut écarter — pas comme un morceau de l'écran.
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(theme.surface)
                .shadow(
                    color: .black.opacity(theme.mode == .dark ? 0.6 : 0.18),
                    radius: 22,
                    y: 4
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(theme.separator)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .sheet(item: $partage) { item in
            ONTActivityView(items: item.items)
        }
        .task {
            // Le geste économisé : venir du widget par « Partager » ouvre le
            // passage **et** la feuille, au lieu d'obliger à retoucher un
            // bouton qu'on vient déjà de toucher.
            guard autoShare else { return }
            autoShare = false
            partage = ONTShareItem(lien.map { [shareText, $0] } ?? [shareText])
        }
    }

    /// La poignée, et la sortie.
    ///
    /// La poignée ne fait rien — elle dit seulement « ceci est une carte
    /// posée par-dessus », ce que le lecteur sait lire d'un coup d'œil. Le
    /// renvoi, lui, est monté dans la barre de navigation : une ligne de moins
    /// ici, et il reste visible quand la carte descend.
    private var poignee: some View {
        ZStack {
            Capsule()
                .fill(theme.ink.opacity(0.16))
                .frame(width: 40, height: 5)
            HStack {
                Spacer()
                Button {
                    selection.removeAll()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.ink.opacity(0.5))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(theme.ink.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Désélectionner")
            }
        }
    }

    /// Les cinq teintes, réparties sur la largeur.
    ///
    /// Des carrés arrondis plutôt que des ronds : à cette taille un carré
    /// montre plus de couleur, et la distingue mieux d'une pastille de statut.
    /// La gomme prend la place que Bible Strong donne à sa flèche, à droite —
    /// elle n'apparaît que s'il y a quelque chose à effacer.
    private var couleurs: some View {
        HStack(spacing: 0) {
            ForEach(HighlightColor.allCases, id: \.self) { color in
                Button {
                    model.apply(color, to: selection, in: chapter)
                } label: {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(ONTColors.highlight(color))
                        .frame(width: 34, height: 34)
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(theme.ink.opacity(0.10))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.label)
                .frame(maxWidth: .infinity)
            }

            Button {
                model.clearHighlights(selection, in: chapter)
            } label: {
                Image(systemName: "eraser")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.ink.opacity(0.6))
                    .frame(width: 34, height: 34)
                    .background(Circle().strokeBorder(theme.ink.opacity(0.18)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retirer le surlignage")
            .frame(maxWidth: .infinity)
            .opacity(model.hasHighlight(selection, in: chapter) ? 1 : 0)
            .disabled(!model.hasHighlight(selection, in: chapter))
        }
    }

    /// Les actions : tuile au-dessus, mot en dessous.
    ///
    /// Le mot sous la tuile plutôt que dedans — la cible reste carrée et
    /// franche, l'intitulé peut s'allonger sans la déformer.
    private var actions: some View {
        HStack(spacing: 0) {
            // Une note se rattache à un verset : le domaine ne sait pas en
            // porter une sur un intervalle, et faire semblant en écrivant le
            // même texte partout produirait cinq notes à corriger une à une.
            if selection.count == 1, let only = selection.first {
                ActionTile(title: "Noter", icon: "square.and.pencil") {
                    noteTarget = VerseSelection(only)
                }
                .frame(maxWidth: .infinity)
            }
            ActionTile(title: "Copier", icon: "doc.on.doc") {
                UIPasteboard.general.string = shareText
                selection.removeAll()
            }
            .frame(maxWidth: .infinity)

            ActionTile(title: "Partager", icon: "square.and.arrow.up") {
                // Le lien accompagne le texte quand il en existe un. Deux
                // objets dans la même feuille : la messagerie prend le texte,
                // et les applications qui savent lire une URL en tirent un
                // aperçu.
                partage = ONTShareItem(lien.map { [shareText, $0] } ?? [shareText])
            }
            .frame(maxWidth: .infinity)

            ActionTile(title: "Image", icon: "photo") {
                let choisis = chapterVerses.filter { selection.contains($0.n) }
                guard let image = ONTShareImage.render(
                    verses: choisis,
                    reference: reference,
                    theme: theme
                ) else { return }
                // L'image d'abord, le texte ensuite : une messagerie qui ne
                // sait pas afficher l'image garde au moins la citation, et
                // celle qui sait met le texte en légende.
                partage = ONTShareItem([image, shareText])
            }
            .frame(maxWidth: .infinity)

            ActionTile(title: "Tout", icon: "checklist") {
                selection = Set(chapterVerses.map(\.n))
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Les versets du chapitre, dans l'ordre.
    private var chapterVerses: [Verse] {
        chapter.blocks
            .compactMap { block -> [Verse]? in
                if case .verses(let group) = block { return group }
                return nil
            }
            .flatMap(\.self)
            .sorted { $0.n < $1.n }
    }

    /// Le renvoi, en intervalles : « Bereshit 1:1-3, 7 » plutôt que sept
    /// numéros à la file. Le calcul vit dans `VerseRange`, pas ici — voir le
    /// plantage qui l'y a envoyé.
    private var reference: String {
        VerseRange.reference(selection, chapterTitle: chapter.title)
    }

    /// Le corps de la traduction seul.
    ///
    /// Un passage qu'on partage se lit d'une traite : ni gloses, ni
    /// translittérations, ni hébreu. L'appareil critique appartient à la
    /// liseuse, pas à une capture qui part dans une conversation.
    private var shareText: String {
        let body = chapterVerses
            .filter { selection.contains($0.n) }
            .map { verse in
                verse.nodes.plainText()
                    .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: " ")

        return "\(body)\n\n— \(reference), La Bible ONT"
    }

    /// Le lien public du passage, s'il existe un domaine.
    ///
    /// `nil` tant que `ONTWebBaseURL` n'est pas renseigné : un lien `ont://`
    /// collé dans une conversation n'est pas cliquable, et ne mène nulle part
    /// pour qui n'a pas l'app. Mieux vaut partager sans lien que partager une
    /// adresse morte.
    private var lien: URL? {
        Router.webLink(
            book: chapter.bookId,
            chapter: chapter.id,
            verses: VerseRange.label(selection)
        )
    }
}

/// Une action de la barre — une tuile, pas un mot souligné.
///
/// La cible fait 60 × 46 : au-dessous, on rate le bouton en tenant le
/// téléphone d'une main, ce qui est exactement la posture de lecture.
private struct ActionTile: View {
    @Environment(\.ontTheme) private var theme
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ActionTileLabel(title: title, icon: icon, theme: theme)
        }
        .buttonStyle(.plain)
    }
}

private struct ActionTileLabel: View {
    let title: String
    let icon: String
    let theme: ONTTheme

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(theme.accent)
                .frame(width: 52, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(theme.accent.opacity(0.12))
                )
            Text(title)
                .font(.caption2)
                .foregroundStyle(theme.ink.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .contentShape(.rect)
    }
}

/// Les versets à la suite, en prose continue.
///
/// Un seul `Text` pour tout un bloc. La découpe en versets reste lisible —
/// les numéros sont là, en exposant — mais elle ne coupe plus la phrase.
/// C'est la lecture suivie ; le bloc par verset reste le mode d'étude.
private struct FlowingVerses: View {
    @Environment(ReadingModel.self) private var model
    @Environment(Router.self) private var router
    @Environment(\.ontTheme) private var theme
    @Environment(\.ontTracking) private var tracking
    private var spacing = ONTSpacing()

    let verses: [Verse]
    let chapter: Chapter
    @Binding var selection: Set<Int>

    var body: some View {
        Text(
            ONTTextRenderer.composeFlowing(
                verses: verses,
                theme: theme,
                selected: selection,
                highlight: { n in
                    model.highlight(chapterId: chapter.id, verse: n)
                        .map { ONTColors.highlight($0.color).opacity(ONTColors.highlightOpacity) }
                }
            )
        )
        .lineSpacing(theme.lineSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, spacing.xs)
        // La seule identité que le défilement puisse viser dans ce mode.
        .id(VerseAnchor(n: verses.first?.n ?? -1))
        // La reprise de lecture n'a plus de ligne où s'accrocher : on retient
        // le premier verset du bloc visible, ce qui suffit à rouvrir au bon
        // endroit sans prétendre à une précision qu'on n'a pas.
        .onScrollVisibilityChange(threshold: 0.6) { visible in
            guard visible, tracking, let premier = verses.first else { return }
            model.remember(chapter: chapter, verse: premier.n)
        }
        // Le moteur de texte nous dit quel verset a été atteint ; c'est ici
        // qu'on en fait une sélection.
        .onChange(of: router.tappedVerse) { _, touche in
            guard let touche, verses.contains(where: { $0.n == touche.id }) else { return }
            router.tappedVerse = nil
            if selection.contains(touche.id) {
                selection.remove(touche.id)
            } else {
                selection.insert(touche.id)
            }
        }
    }
}

// MARK: - Les blocs

private struct BlockView: View {
    @Environment(\.ontTheme) private var theme
    private var spacing = ONTSpacing()

    let block: Block
    let chapter: Chapter
    @Binding var noteTarget: VerseSelection?
    @Binding var selection: Set<Int>

    /// Titres, paragraphes et listes reculent avec le reste : un intertitre
    /// resté noir au milieu d'une page estompée attirerait l'œil plus que la
    /// sélection elle-même.
    private var dim: Double { selection.isEmpty ? 1 : 0.32 }

    var body: some View {
        content.opacity(isVerses ? 1 : dim)
    }

    /// Les versets gèrent leur propre opacité, verset par verset.
    private var isVerses: Bool {
        if case .verses = block { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch block {
        case .heading(_, let nodes):
            Text(ONTTextRenderer.compose(nodes, theme: theme))
                .font(theme.type.heading.font)
                .foregroundStyle(theme.type.heading.color)
                .padding(.top, spacing.s)

        case .verses(let verses):
            if theme.preferences.continuous {
                FlowingVerses(verses: verses, chapter: chapter, selection: $selection)
            } else {
                VStack(alignment: .leading, spacing: theme.verseSpacing) {
                    ForEach(verses) { verse in
                        VerseRow(
                            verse: verse,
                            chapter: chapter,
                            noteTarget: $noteTarget,
                            selection: $selection
                        )
                    }
                }
            }

        case .paragraph(let nodes):
            Text(ONTTextRenderer.compose(nodes, theme: theme))
                .lineSpacing(theme.lineSpacing)
                .textSelection(.enabled)

        case .quote(let nodes):
            Text(ONTTextRenderer.compose(nodes, theme: theme))
                .lineSpacing(theme.lineSpacing)
                .padding(.leading, spacing.m)
                .overlay(alignment: .leading) {
                    Rectangle().fill(ONTColors.gold).frame(width: 3)
                }

        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: spacing.s) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: spacing.s) {
                        Text(ordered ? "\(index + 1)." : "—")
                            .foregroundStyle(ONTColors.goldDeep)
                        Text(ONTTextRenderer.compose(item, theme: theme))
                    }
                }
            }

        case .table(let headers, let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: spacing.l, verticalSpacing: spacing.s) {
                    GridRow {
                        ForEach(Array(headers.enumerated()), id: \.offset) { _, cell in
                            Text(ONTTextRenderer.compose(cell, theme: theme)).fontWeight(.semibold)
                        }
                    }
                    Divider()
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(ONTTextRenderer.compose(cell, theme: theme))
                            }
                        }
                    }
                }
            }

        case .rule:
            GoldRule(opacity: 0.6)
        }
    }
}

/// Le pied d'unité — version, verrouillage, décisions terminologiques propres.
private struct FooterView: View {
    @Environment(\.ontTheme) private var theme
    private var spacing = ONTSpacing()

    let footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: spacing.m) {
            GoldRule()

            HStack(spacing: spacing.xs) {
                Image(systemName: footer.locked ? "lock.fill" : "pencil.line")
                Text(footer.locked ? "Verrouillée" : "À valider")
                if let version = footer.version {
                    Text("· Version \(version)")
                }
            }
            .font(.caption)
            .foregroundStyle(ONTColors.goldDeep)

            if !footer.notes.isEmpty {
                SectionCaption("Décisions terminologiques")
                ForEach(Array(footer.notes.enumerated()), id: \.offset) { _, note in
                    Text(plain(note)).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, spacing.m)
    }

    private func plain(_ block: Block) -> AttributedString {
        switch block {
        case .paragraph(let nodes), .heading(_, let nodes), .quote(let nodes):
            ONTTextRenderer.compose(nodes, theme: theme)
        case .list(_, let items):
            items.reduce(into: AttributedString()) { output, item in
                output += ONTTextRenderer.compose(item, theme: theme) + AttributedString("\n")
            }
        default:
            AttributedString()
        }
    }
}

// MARK: - La note

private struct NoteEditor: View {
    @Environment(ReadingModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let chapter: Chapter
    let verse: Int

    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("\(chapter.title):\(verse)") {
                    TextEditor(text: $text).frame(minHeight: 140)
                }
            }
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        model.setNote(text, verse: verse, in: chapter)
                        dismiss()
                    }
                }
            }
            .onAppear {
                text = model.highlight(chapterId: chapter.id, verse: verse)?.note ?? ""
            }
        }
        .presentationDetents([.medium])
    }
}


// MARK: - Réglages

/// Les réglages de lecture — les trois niveaux, la taille, la fonte, le thème.
public struct ReadingSettingsSheet: View {
    @Environment(ReadingModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// Le chapitre ouvert, quand la feuille est appelée depuis la lecture.
    ///
    /// Facultatif : depuis l'onglet « Vous », il n'y a pas de chapitre
    /// courant, et l'aperçu retombe alors sur la dernière lecture.
    private let chapter: Chapter?

    public init(chapter: Chapter? = nil) {
        self.chapter = chapter
    }

    /// Le chapitre à montrer dans l'aperçu.
    private var previewed: Chapter? {
        if let chapter { return chapter }
        guard let position = model.position else { return nil }
        return model.chapter(book: position.bookId, id: position.chapterId)
    }

    public var body: some View {
        @Bindable var model = model

        NavigationStack {
            // L'aperçu est **hors** du formulaire, donc épinglé : dedans, il
            // défilait avec les réglages et disparaissait au moment précis où
            // on tournait le bouton qui le fait changer. Un aperçu qu'il faut
            // remonter voir n'est pas un aperçu.
            VStack(spacing: 0) {
                if let previewed {
                    SettingsPreview(chapter: previewed)
                    Divider()
                }
                controls
            }
            .navigationTitle("Lecture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    /// Les réglages, qui défilent sous l'aperçu.
    @ViewBuilder
    private var controls: some View {
        @Bindable var model = model

        Form {
                Section {
                    Toggle("Versets à la suite", isOn: $model.preferences.continuous)
                } header: {
                    Text("Disposition")
                } footer: {
                    Text(
                        "À la suite, les versets coulent en prose et leurs numéros "
                            + "passent en exposant — c'est la lecture suivie. En blocs, "
                            + "chaque verset se tient seul : c'est le mode d'étude."
                    )
                }

                Section {
                    Toggle("Gloses", isOn: $model.preferences.showGloss)
                    Toggle("Translittération et hébreu", isOn: $model.preferences.showLevel3)
                } header: {
                    Text("Niveaux du texte")
                } footer: {
                    Text(
                        "Le corps de la traduction reste toujours visible. "
                            + "Les gloses explicitent l'implicite hébreu ; "
                            + "le niveau 3 donne le mot original."
                    )
                }

                Section {
                    LabeledContent("Taille") {
                        Slider(value: $model.preferences.textSize, in: 15...28, step: 1)
                    }
                    LabeledContent("Interligne") {
                        Slider(value: $model.preferences.lineSpacing, in: 0.2...1.0, step: 0.1)
                    }
                } header: {
                    Text("Corps")
                } footer: {
                    Text(
                        "Cette taille s'ajoute au réglage système : agrandir le texte dans "
                            + "Réglages › Affichage agrandit aussi celui-ci."
                    )
                }

                Section {
                    ForEach(ReadingFont.allCases, id: \.self) { font in
                        FontRow(font: font, selection: $model.preferences.bodyFont)
                    }
                } header: {
                    Text("Fonte")
                } footer: {
                    Text(
                        "Chaque nom est composé dans sa propre fonte : "
                            + "ce que vous voyez est ce que vous lirez."
                    )
                }

                Section("Thème") {
                    Picker("Thème", selection: $model.preferences.theme) {
                        ForEach(ReadingTheme.allCases, id: \.self) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                }
        }
    }
}

/// L'aperçu vivant, en haut des réglages.
///
/// Il montre les premiers versets du chapitre ouvert, composés avec les
/// réglages **en cours de modification** : bouger la taille, changer de fonte
/// ou éteindre les gloses se voit ici, sur le texte réel, sans refermer la
/// feuille. Un échantillon inventé ne dirait rien — c'est la cohabitation des
/// trois niveaux qui décide si un réglage tient.
private struct SettingsPreview: View {
    @Environment(ReadingModel.self) private var model
    private var spacing = ONTSpacing()

    let chapter: Chapter

    /// Les deux premiers versets, et rien de plus.
    ///
    /// Deux suffisent à faire apparaître les trois niveaux, et l'aperçu doit
    /// tenir dans une feuille à mi-hauteur sans avaler les réglages.
    private var verses: [Verse] {
        chapter.blocks
            .compactMap { block in
                if case .verses(let group) = block { return group }
                return nil
            }
            .flatMap(\.self)
            .prefix(2)
            .map(\.self)
    }

    var body: some View {
        // Le thème est reconstruit depuis les préférences **vivantes** plutôt
        // que lu dans l'environnement : celui-ci a été capturé à l'ouverture
        // de la feuille, et l'aperçu doit suivre le curseur, pas l'état de
        // départ.
        PreviewBody(verses: verses, title: chapter.title)
            .ontTheme(from: model.preferences)
    }

    private struct PreviewBody: View {
        @Environment(\.ontTheme) private var theme
        private var spacing = ONTSpacing()

        let verses: [Verse]
        let title: String

        var body: some View {
            VStack(alignment: .leading, spacing: spacing.xs) {
                Text("Aperçu — \(title)")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(theme.ink.opacity(0.5))
                    .padding(.horizontal, spacing.xs)

                // L'aperçu défile en lui-même : borné en hauteur pour laisser
                // la place aux réglages, mais rien n'y devient inatteignable.
                // Sans ça, `.clipped()` coupait la fin du second verset — et
                // c'est souvent la fin d'une glose qui départage deux fontes.
                ScrollView {
                    VStack(alignment: .leading, spacing: spacing.s) {
                        ForEach(verses, id: \.n) { verse in
                            Text(ONTTextRenderer.compose(verse: verse, theme: theme))
                                .lineSpacing(theme.lineSpacing)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(spacing.m)
                }
                .frame(maxWidth: .infinity, maxHeight: 250, alignment: .leading)
                .background(theme.background)
                .clipShape(RoundedRectangle(cornerRadius: ONTRadius.card))
                .overlay {
                    RoundedRectangle(cornerRadius: ONTRadius.card)
                        .strokeBorder(theme.separator)
                }
                .accessibilityLabel("Aperçu de \(title) avec les réglages en cours")
            }
            .padding(.horizontal, spacing.m)
            .padding(.top, spacing.s)
            .padding(.bottom, spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface)
        }
    }
}

/// Une fonte proposée au lecteur, composée dans elle-même.
///
/// Un `Picker` ordinaire afficherait sept noms dans la fonte du système —
/// c'est-à-dire sept mots qui ne disent rien de ce qu'ils désignent. Ici le
/// nom est son propre échantillon.
private struct FontRow: View {
    @Environment(\.ontTheme) private var theme
    let font: ReadingFont
    @Binding var selection: ReadingFont

    private var chosen: Bool { selection == font }

    var body: some View {
        Button {
            selection = font
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(font.label)
                        .font(.custom(ONTFonts.family(font), size: 19))
                        .foregroundStyle(theme.ink)
                    Text(font.note)
                        .font(.footnote)
                        .foregroundStyle(theme.ink.opacity(0.6))
                }
                Spacer(minLength: 8)
                if chosen {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(theme.accent)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }
}
