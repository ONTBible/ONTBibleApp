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
    @Environment(\.ontLectureFigee) private var lectureFigee

    var spacing = ONTSpacing()
    var echelle = ONTScaled()

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
    /// L'ardoise du suivi : où l'on en est, sans passer par l'état de la vue.
    @State private var suivi = SuiviDeLecture()

    let chapter: Chapter

    /// Vraie pour l'unité **du dessus**, fausse pour celle qui entre ou sort
    /// pendant un glissement.
    ///
    /// Deux unités cohabitent le temps d'une transition, et une barre de
    /// navigation n'appartient qu'à une vue : sans ce drapeau, celle qui arrive
    /// poserait son titre et sa barre d'outils par-dessus celle qu'on regarde
    /// encore, et le résultat dépendrait de l'ordre de composition.
    var actif = true

    /// De combien le **texte** est translaté, sans que la vue bouge.
    ///
    /// Posé sur le contenu défilant seulement, jamais sur le fond. Déplacer la
    /// vue entière ferait voyager son fond avec elle, et l'on verrait le
    /// rectangle de la page — un bord droit à droite, une arête en haut. Or il
    /// n'y a pas de page à voir : le texte court jusqu'aux bords de l'écran, et
    /// c'est ce qui doit rester vrai pendant le geste.
    var decalage: CGFloat = 0

    /// Écrit à la main, et non laissé au compilateur.
    ///
    /// Il dit ce que la vue attend vraiment : une unité, et deux réglages que
    /// seul le feuilletage emploie. L'initialiseur synthétisé le dirait aussi,
    /// mais en y mêlant les jetons de mesure, qui ne regardent personne
    /// au-dehors.
    init(chapter: Chapter, actif: Bool = true, decalage: CGFloat = 0) {
        self.chapter = chapter
        self.actif = actif
        self.decalage = decalage
    }

    /// Ce que porte la pastille de renvoi — **le livre et le rang**.
    ///
    /// Elle est le seul repère de l'écran de lecture : il n'y a pas de barre de
    /// navigation qui rappelle où l'on est, ni de sommaire au-dessus. Le rang
    /// seul — « Chapitre 6 » — dirait donc *quelle* unité sans dire *de quoi*.
    ///
    /// Mais le rang suit le registre, et c'est ici que ça compte le plus : la
    /// pastille est le seul endroit où le lecteur croise le mot **pendant**
    /// qu'il lit. Le sommaire et le sélecteur se traversent ; celui-ci reste
    /// sous les yeux.
    ///
    /// Une introduction garde son titre : elle n'a pas de rang à traduire.
    private var pastille: String {
        guard chapter.n > 0 else { return chapter.title }
        let livre = model.outline(chapter.bookId)?.title ?? chapter.bookId
        return LibelleDUnite.situe(
            livre: livre,
            rang: chapter.n,
            french: model.preferences.french
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ParchmentPage {
                    // Paresseuse, après l'avoir été, ne plus l'être, et le
                    // redevenir. Le va-et-vient mérite d'être expliqué.
                    //
                    // On y avait renoncé parce que la page laissait des
                    // **trous** en défilant : un bloc est une section entière
                    // composée en un seul `Text`, et il n'apparaissait qu'après
                    // sa mise en page. `.scrollPosition` visait par ailleurs des
                    // rangs pas encore établis, ce qui cassait la reprise de
                    // lecture. Une pile pleine réglait les deux, au prix de
                    // l'unité entière mise en page à l'ouverture.
                    //
                    // Ce prix s'est révélé être un **gel**. Mesuré sur le
                    // simulateur avec une minuterie posée sur le fil principal
                    // — son retard est la durée du gel, et c'est ce que mesure
                    // le chien de garde du système. Huit chapitres ouverts à la
                    // suite, dont les plus lourds :
                    //
                    //     Release, pile pleine        3 gels, pic 540 ms
                    //     Release, pile paresseuse    1 gel,  pic 214 ms
                    //
                    //     Debug,   pile pleine        6 gels, pic 795 ms
                    //     Debug,   pile pleine        2 gels, pic 561 ms   (après #23)
                    //
                    // Les deux configurations sont séparées à dessein : une
                    // mesure Debug ne dit rien de ce que reçoit un testeur, et
                    // les mêler dans un seul tableau — ce que ce commentaire
                    // faisait — laisse croire à une progression qui n'a pas été
                    // relevée dans les mêmes conditions.
                    //
                    // Sur un téléphone, plus lent qu'un Mac, les 540 ms sont
                    // devenues les deux secondes qu'Apple sanctionne — Sentry
                    // l'a rapporté avant qu'on le cherche.
                    //
                    // Ce qui a changé depuis le renoncement : le moteur de
                    // dessin ne se pose plus pendant la lecture, et un bloc n'a
                    // donc plus à être rasterisé pour paraître. Il s'établit
                    // assez vite pour qu'on ne le voie plus arriver — c'est
                    // exactement la lenteur qui faisait les trous.
                    //
                    // Vérifié : un renvoi vers un verset lointain — Bereshit
                    // 19:30, 10:28, 1:30 — défile et trouve sa cible, sur une
                    // page pleine. C'est le cas qui avait cassé.
                    LazyVStack(alignment: .leading, spacing: spacing.xl) {
                        header

                        ForEach(Array(blocs.enumerated()), id: \.offset) { _, block in
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
                    // Ce qui désigne les cibles que `.scrollPosition(id:)` peut
                    // viser : les enfants directs de cette pile, donc les blocs.
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
            // Le suivi s'éteint aussi en **partant**, et pas seulement le temps
            // d'arriver.
            //
            // `ONTTracking` documente le piège à l'apparition : les enfants
            // paraissent avant le parent, et les premières lignes répondent
            // « verset 1 » avant qu'on ait pu lire la position. La disparition
            // a le même défaut en miroir — pendant que la vue se retire, la
            // liste se défait et des lignes du haut se signalent visibles. La
            // position enregistrée redevenait le début du chapitre, ce qui ne
            // se voyait qu'à la **fois suivante** : « Reprendre » ramenait en
            // haut, alors que la première visite avait bien fonctionné.
            // Le doigt, et lui seul, ouvre le droit d'enregistrer.
            //
            // `.animating` en est **exclu**, et c'est tout l'enjeu : c'est la
            // phase des défilements que l'app se commande à elle-même — ceux de
            // la restauration. En l'acceptant, la restauration s'ouvrait à
            // elle-même le droit d'écrire, et notait les positions
            // intermédiaires de son propre trajet en quatre passes. La position
            // dérivait donc un peu à chaque aller-retour, jusqu'à ne plus
            // désigner grand-chose au bout de cinq ou six.
            .onScrollPhaseChange { _, phase in
                switch phase {
                case .tracking, .interacting, .decelerating:
                    suivi.defile()
                case .idle:
                    guard let verset = suivi.aRetenir() else { return }
                    model.remember(chapter: chapter, verse: verset)
                case .animating:
                    break
                @unknown default:
                    break
                }
            }
            // Le moteur de texte dit quel verset a été atteint ; c'est ici
            // qu'on en fait une sélection — **une seule fois pour l'unité**.
            //
            // C'était posé dans chaque bloc de prose, ce qui coûtait cher sans
            // que ça se voie : `Router` est `@Observable`, donc lire
            // `tappedVerse` dans un `onChange` crée une dépendance. Un appui
            // invalidait le corps de **tous** les blocs, et deux fois — à la
            // pose du verset touché, puis à sa remise à `nil`. Le bloc concerné
            // était le seul à faire quelque chose ; les autres refaisaient leur
            // travail pour rien.
            .onChange(of: router.tappedVerse) { _, touche in
                guard let touche else { return }
                router.tappedVerse = nil
                if selection.contains(touche.id) {
                    selection.remove(touche.id)
                } else {
                    selection.insert(touche.id)
                }
            }
        }
        // Éteint jusqu'à la restauration : sans ça, les premières lignes
        // écrasent la position avant qu'on ait pu la lire.
        // Le texte glisse ; le fond, posé plus bas par `.ontScreen()`, ne
        // bouge pas d'un pixel.
        .offset(x: decalage)
        .environment(\.ontSuivi, suivi)
        // Figé pendant qu'on soulève la page : sans ça, les deux gestes
        // s'exercent ensemble et on tourne la page en ayant descendu d'un
        // demi-écran sans l'avoir voulu.
        .scrollDisabled(lectureFigee)
        // `.ontScreen()` et non un fond posé à la main. La règle du design
        // system dit que tout écran de premier niveau l'applique ; la liseuse
        // ne le faisait pas, ce qui n'avait pas de conséquence tant que le fond
        // était un aplat — et en aurait eu une dès le grain, qui vit là.
        .ontScreen()
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
        // 0,14 s et non 0,22. Le travail derrière un appui est désormais un
        // dessin, pas une mise en page — ce qui restait de délai perçu était
        // en grande partie cette animation elle-même. Assez court pour suivre
        // le doigt, assez long pour qu'on voie d'où la barre vient.
        .animation(.snappy(duration: 0.14), value: selection.isEmpty)
        // **Chaque verset se sent, et les trois moments ne se ressemblent pas.**
        //
        // On désigne un verset en regardant le texte, pas la barre qui monte du
        // bas de l'écran. Sans retour tactile, le seul signe que quelque chose
        // a changé est hors du regard — et il l'est d'autant plus quand le
        // corps est réglé grand et que la barre sort du champ.
        //
        // Le déclencheur est le **`Set` lui-même** et non son `isEmpty`. Un
        // booléen ne bascule qu'aux frontières du mode : ajouter un deuxième,
        // un troisième verset ne le changeait pas, donc rien ne se sentait
        // au-delà du premier. C'est l'écart que l'auteur a senti sur Android
        // avant de le demander ici.
        //
        // Trois sensations, pour savoir **sans regarder** ce qu'on vient de
        // faire :
        //
        // * **on entre** — un choc net, medium. C'est un mode qui s'ouvre, et
        //   c'est le seul des trois moments qui change ce que l'écran fait ;
        // * **on ajoute ou on retire** — `.selection`, le retour qu'iOS réserve
        //   au déplacement d'une poignée de sélection de texte. Étendre une
        //   sélection est exactement ça ;
        // * **on sort** — un choc léger, plus discret que l'entrée. La
        //   dissymétrie est voulue : entrer demande de l'attention, sortir
        //   rend la page.
        //
        // Android en a deux là où nous en avons trois — `LongPress` puis
        // `TextHandleMove`, sa sortie se confondant avec un retrait. C'est un
        // écart connu et assumé, pas un oubli.
        .sensoryFeedback(trigger: selection) { avant, apres in
            switch (avant.isEmpty, apres.isEmpty) {
            case (true, false): .impact(weight: .medium, intensity: 0.5)
            case (false, true): .impact(weight: .light, intensity: 0.35)
            // Le `Set` a changé sans franchir de frontière : un verset de plus
            // ou de moins. Et s'il n'a pas changé du tout, SwiftUI ne nous
            // appelle pas — le déclencheur est `Equatable`.
            default: .selection
            }
        }
        // Le titre central ne double plus la pastille : il ne sert qu'à
        // porter le renvoi pendant une sélection, comme dans Bible Strong.
        .navigationTitle(actif && !selection.isEmpty ? reference : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if actif {
            // La pastille de renvoi, en haut à gauche — le geste de YouVersion
            // et de Bible Strong. Elle dit où l'on est **et** sert de porte :
            // sans elle, aller de Bereshit 1 à Bereshit 18 demande de remonter
            // à la table, replier, déplier, redescendre.
            ToolbarItem(placement: .topBarLeading) {
                Button { showingPicker = true } label: {
                    HStack(spacing: 4) {
                        Text(pastille)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: echelle(10), weight: .bold))
                    }
                    // **Sans ça, la pastille se vide.**
                    //
                    // Elle partage la place de tête avec le bouton de retour
                    // du système, et iOS lui accorde ce qui reste. Quand le
                    // libellé s'est allongé — « Bereshit 1 » devenu « Bereshit
                    // · Chapitre 1 », deux fois plus long —, ce reste est
                    // tombé à zéro : `lineLimit(1)` a tronqué le texte à
                    // **rien**, et il ne restait qu'une capsule avec un
                    // chevron. Le lecteur y voyait la disparition du
                    // sélecteur, pas un texte tronqué.
                    //
                    // `fixedSize` dit à la mise en page que ce texte ne se
                    // comprime pas. C'est ce que voulait déjà `lineLimit(1)`,
                    // qui ne dit que « une seule ligne » — pas « garde ta
                    // largeur ». Deux réglages voisins, un seul répond à la
                    // question posée.
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(theme.ink.opacity(0.07)))
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Aller à un autre passage — actuellement \(pastille)")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Lecture", systemImage: "textformat.size") { showingSettings = true }
            }
            }
        }
        // ## Chaque feuille repose le thème
        //
        // Une feuille hérite de l'environnement de l'endroit où elle est
        // **déclarée**, et le garde tel qu'il était à sa présentation. Celle
        // des réglages est justement celle où l'on change de thème : sans
        // cette pose, elle repeignait ses surfaces mais gardait le schéma de
        // couleurs du départ, et les commandes d'iOS devenaient illisibles —
        // « Thème » en noir sur l'aubergine. Il fallait relancer l'app.
        .sheet(isPresented: $showingPicker) {
            ReferencePicker(current: chapter)
                .ontTheme(from: model.preferences)
        }
        .sheet(isPresented: $showingSettings) {
            // La pile et le « OK » appartiennent à la **présentation**, pas au
            // contenu : depuis « Vous », la même vue est poussée dans une pile
            // qui existe déjà, et n'a ni l'une ni l'autre à fournir.
            NavigationStack {
                // Le thème est reposé **ici aussi**, au plus près du contenu.
                //
                // Posé seulement autour de la pile, il repeignait les surfaces
                // mais laissait la teinte d'origine : la valeur du sélecteur
                // restait bordeaux sur l'aubergine, soit 1,2:1. Les deux ne
                // voyagent pas par le même chemin — l'une par l'environnement,
                // l'autre par `tint`, que la présentation capture plus haut.
                ReadingSettingsSheet(chapter: chapter)
                    .ontTheme(from: model.preferences)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("OK") { showingSettings = false }
                        }
                    }
            }
            // `.large` en plus : l'aperçu occupe le haut de la feuille, et à
            // grande taille avec les gloses allumées, la mi-hauteur ne laisse
            // plus voir les réglages.
            .presentationDetents([.medium, .large])
            .ontTheme(from: model.preferences)
        }
        .sheet(item: $noteTarget) { selection in
            NoteEditor(chapter: chapter, verse: selection.id)
                .ontTheme(from: model.preferences)
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

        // **Borné aux versets qui existent.**
        //
        // Rien ne le vérifiait, et un lien vers `?v=999` s'enregistrait tel
        // quel : « Reprendre » affichait alors « Bereshit 1:999 », et le
        // lancement suivant visait un verset absent. Un lien bricolé — ou un
        // lien vers une unité qui a raccourci depuis — empoisonnait l'état
        // persistant du lecteur.
        //
        // Le défilement, lui, ne s'en plaignait pas : viser une ancre inconnue
        // est une non-opération silencieuse. Le comportement souhaitable
        // arrivait donc par tolérance du moteur, et le défaut se logeait juste
        // à côté, dans ce qu'on **retient**.
        let demande = router.pendingVerse
            ?? (model.position?.chapterId == chapter.id ? model.position?.verse : nil)
        let vise = demande.flatMap { n in
            chapter.verses.contains(where: { $0.n == n }) ? n : nil
        }
        router.pendingVerse = nil

        suivi.recommence()

        // **Arriver sur une unité, c'est déjà y être.**
        //
        // La position ne s'écrivait qu'après un défilement — la règle qui a
        // corrigé la corruption d'hier, où apparition et disparition
        // enregistraient à tort. Mais elle laissait un trou : ouvrir une unité
        // et la lire sans bouger d'un pouce n'y déplaçait pas la position.
        // « Reprendre » ramenait alors à la précédente.
        //
        // L'ordre est ce qui rend l'écriture sûre : la position d'avant vient
        // d'être **lue** juste au-dessus. On peut donc écrire sans risquer
        // d'effacer ce qu'on allait viser.
        model.remember(chapter: chapter, verse: vise ?? chapter.verses.first?.n ?? 1)

        guard let vise, vise > 1 else {
            // Rien à viser.
            return
        }

        guard let ancre = anchor(for: vise) else { return }

        // Plusieurs passes, échelonnées au-delà de l'animation de navigation.
        //
        // Une poussée de pile dure environ un demi-seconde, et pendant ce
        // temps la vue de défilement n'a pas sa taille finale : un
        // `scrollTo` y est appliqué puis défait quand la transition se pose.
        //
        // Les passes après 0,6 s ne coûtent rien quand la première a visé
        // juste : viser une position déjà atteinte ne déplace rien.
        for delai in [Duration.zero, .milliseconds(250), .milliseconds(600), .seconds(1)] {
            if delai > .zero { try? await Task.sleep(for: delai) }
            guard !Task.isCancelled else { return }
            proxy.scrollTo(VerseAnchor(n: ancre), anchor: .top)
        }
    }

    /// Les blocs tels qu'ils sont rendus.
    ///
    /// En lecture suivie, les versets consécutifs n'en font qu'un — sans quoi
    /// le mode ne changeait rien là où le corpus découpe au verset, c'est-à-dire
    /// presque partout. En mode d'étude, le découpage du corpus fait foi.
    private var blocs: [Block] {
        theme.preferences.continuous
            ? chapter.blocks.fusingConsecutiveVerses()
            : chapter.blocks
    }

    /// L'identité à viser pour atteindre un verset.
    ///
    /// Le verset lui-même, dans les deux modes. En prose il n'y a pas de vue
    /// par verset, mais il y a désormais une **ancre** par verset derrière le
    /// texte : la cible existe donc, et il n'y a plus lieu de rabattre le
    /// repère sur le début du bloc comme on le faisait.
    private func anchor(for verse: Int) -> Int? { verse }

    /// L'opacité de ce qui n'est pas sélectionné.
    ///
    /// Le procédé vient de Bible Strong, et il est plus efficace qu'un fond
    /// coloré : au lieu d'ajouter une marque au verset désigné, on retire du
    /// poids à tout le reste. La page entière devient le contraste.
    private var dim: Double { selection.isEmpty ? 1 : ONTColors.dimmedOpacity }

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
                    .foregroundStyle(ONTColors.accent(theme.mode))
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
    @Environment(\.ontSuivi) private var suivi
    @Environment(ReadingModel.self) private var model
    @Environment(\.ontTheme) private var theme
    var spacing = ONTSpacing()

    let verse: Verse
    let chapter: Chapter
    @Binding var noteTarget: VerseSelection?
    @Binding var selection: Set<Int>


    private var highlight: Highlight? {
        model.highlight(chapterId: chapter.id, verse: verse.n)
    }

    private var selected: Bool { selection.contains(verse.n) }

    /// Estompé quand une sélection existe ailleurs. C'est le procédé de Bible
    /// Strong : on ne marque pas le verset désigné, on efface le reste.
    private var dim: Double { selection.isEmpty || selected ? 1 : ONTColors.dimmedOpacity }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing.xs) {
            // Le pointillé passe par le moteur de rendu, pas par un cadre
            // dessiné autour : la sélection épouse ainsi les retours à la
            // ligne, et le dernier mot d'un verset n'entraîne pas une bordure
            // sur toute la largeur.
            Text(ONTTextRenderer.compose(
                verse: verse, theme: theme, underlined: selected,
                surligne: highlight != nil))
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
                    .fill(ONTColors.highlight(color, theme.mode).opacity(ONTColors.highlightOpacity))
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
            if visible { suivi.entre(verse.n) } else { suivi.sort(verse.n) }
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
    var spacing = ONTSpacing()
    var echelle = ONTScaled()

    let chapter: Chapter
    @Binding var selection: Set<Int>
    @Binding var noteTarget: VerseSelection?
    /// Vrai quand l'ouverture vient de la pastille du widget.
    @Binding var autoShare: Bool

    /// Ce qui part dans la feuille de partage. Rempli à l'appui, pas avant :
    /// rendre une image de 1080 × 1080 à chaque verset touché serait du
    /// gaspillage pur.
    @State private var partage: ONTShareItem?

    /// De combien le doigt a fait descendre la carte.
    @State private var glissement: CGFloat = 0

    /// Au-delà, on lâche : la carte s'en va.
    ///
    /// 60 points, soit un peu plus que la hauteur d'une ligne — assez pour
    /// qu'un doigt qui ripe en visant une couleur ne referme pas tout, assez
    /// peu pour que le geste ne se travaille pas.
    private static let seuil: CGFloat = 60

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
                    color: .black.opacity(theme.mode.isDark ? 0.6 : 0.18),
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
        // La poignée promettait un geste que la carte ne tenait pas : elle
        // dit « objet posé par-dessus, écartable », et il fallait pourtant
        // viser la croix. On tient la promesse.
        .offset(y: glissement)
        .gesture(
            // 10 points avant de prendre la main, sinon le glissement vole
            // les appuis destinés aux pastilles de couleur.
            DragGesture(minimumDistance: 10)
                .onChanged { geste in
                    let hauteur = geste.translation.height
                    // Vers le haut, la carte résiste au lieu de se bloquer net :
                    // un arrêt sec se lit comme un défaut, une retenue se lit
                    // comme une limite.
                    glissement = hauteur > 0 ? hauteur : hauteur / 4
                }
                .onEnded { geste in
                    // La vitesse compte autant que la distance : un geste vif
                    // et court veut fermer, et attendre 60 points le ferait
                    // rebondir alors que le doigt est déjà parti.
                    let lance = geste.predictedEndTranslation.height
                    if geste.translation.height > Self.seuil || lance > Self.seuil * 2.5 {
                        // Pas d'animation ici : vider la sélection déclenche
                        // la transition de sortie déjà posée sur la barre, qui
                        // reprend la carte là où le doigt l'a laissée.
                        selection.removeAll()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            glissement = 0
                        }
                    }
                }
        )
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
    /// La poignée dit « ceci est une carte posée par-dessus », ce que le
    /// lecteur sait lire d'un coup d'œil — et depuis qu'un glissement referme
    /// la carte, elle ne le dit plus en vain. La croix reste : un geste de
    /// glissement demande de la dextérité, un bouton n'en demande pas. Le
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
                        .font(.system(size: echelle(12), weight: .bold))
                        .foregroundStyle(theme.ink.opacity(0.5))
                        .frame(width: echelle(28), height: echelle(28))
                        .background(Circle().fill(theme.ink.opacity(0.07)))
                        // Le disque fait 28 points, la cible en fait 44 : le
                        // minimum d'Apple, atteint sans grossir le dessin.
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
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
                        .fill(ONTColors.highlight(color, theme.mode))
                        .frame(width: 34, height: 34)
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(theme.ink.opacity(0.10))
                        }
                        // La cible s'arrêtait au carré dessiné — 34 points,
                        // sous le minimum d'Apple. Elle prend maintenant toute
                        // la colonne, sans que le carré change de taille.
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.label)
            }

            Button {
                model.clearHighlights(selection, in: chapter)
            } label: {
                Image(systemName: "eraser")
                    .font(.system(size: echelle(15), weight: .medium))
                    .foregroundStyle(theme.ink.opacity(0.6))
                    .frame(width: echelle(34), height: echelle(34))
                    .background(Circle().strokeBorder(theme.ink.opacity(0.18)))
                    // Le cercle est **tracé** et non rempli : sans forme de
                    // contact, son centre était un trou et seul le contour
                    // répondait. La colonne entière devient la cible, ce qui
                    // vaut mieux qu'un disque de 34 points — Apple en demande
                    // 44 au minimum.
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retirer le surlignage")
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
                // **Le lien vient aussi.**
                //
                // Le partage l'emportait, le presse-papier non — et rien ne le
                // disait. Le lecteur qui allume la bascule du lien la croit
                // vraie partout ; il colle son verset dans un message, et le
                // lien manque sans qu'aucun écran ne lui ait annoncé
                // l'exception.
                //
                // Une seule chaîne ici, et non deux objets comme au partage :
                // un presse-papier n'a qu'un contenu, et la ligne à part fait
                // que le destinataire peut citer le texte sans traîner
                // l'adresse.
                UIPasteboard.general.string = texteACopier
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
        // Le repli des espaces est fait par `plainText()` depuis qu'il écrit
        // au fil — et mieux : retours à la ligne préservés, ponctuation
        // française respectée. Le `{2,}` qui traînait ici écrasait tout.
        Partage.composer(
            chapterVerses
                .filter { selection.contains($0.n) }
                .map { Partage.Morceau(numero: $0.n, texte: $0.nodes.plainText()) },
            reference: reference,
            reglages: model.preferences.partage
        )
    }

    /// Ce que le bouton « Copier » met dans le presse-papier.
    ///
    /// Le même texte que le partage, plus le lien sur sa propre ligne quand la
    /// bascule l'allume. Séparé par une ligne blanche, comme la signature, et
    /// pour la même raison : ce qui se cite doit pouvoir se détacher de ce qui
    /// l'accompagne.
    private var texteACopier: String { Partage.avecLien(shareText, lien) }

    /// Le lien public du passage, s'il existe un domaine.
    ///
    /// `nil` tant que `ONTWebBaseURL` n'est pas renseigné : un lien `ont://`
    /// collé dans une conversation n'est pas cliquable, et ne mène nulle part
    /// pour qui n'a pas l'app. Mieux vaut partager sans lien que partager une
    /// adresse morte.
    private var lien: URL? {
        guard model.preferences.partage.lien else { return nil }
        return Router.webLink(
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
    /// Le thème passé en paramètre et non lu dans l'environnement : cette
    /// étiquette est aussi construite hors d'un contexte de vue.
    let theme: ONTTheme

    var body: some View {
        VStack(spacing: 6) {
            // La pastille est en points **fixes**, et c'est la seule chose de
            // l'app qui ne suit pas le curseur des réglages. Ce n'est pas un
            // oubli, c'est le seul arbitrage possible.
            //
            // Cinq tuiles se partagent une largeur qui, elle, ne grandit pas :
            // ce que la pastille prend, elle le prend à l'écart qui la sépare
            // de sa voisine. Mesuré sur deux captures, en rapport écart/tuile —
            // le seul chiffre que deux échelles rendent comparable :
            //
            //     pastille fixe          0,43   la rangée respire
            //     pastille à l'échelle   0,22   les tuiles se touchent
            //
            // Ce qui porte le sens, ce n'est pas le symbole mais le mot en
            // dessous — et lui suit le curseur. On perd donc une icône qui
            // grandit, pas une information qui se lit.
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

/// Pose le moteur de dessin, ou ne pose rien.
///
/// Un `if` dans un `ViewModifier` plutôt qu'à l'appel : la chaîne autour reste
/// écrite une seule fois. L'identité de la vue change quand on passe de l'un à
/// l'autre — c'est-à-dire au premier verset désigné et au dernier relâché,
/// deux fois par sélection, jamais pendant.
private struct Estompage: ViewModifier {
    let moteur: ONTProseRenderer?

    func body(content: Content) -> some View {
        if let moteur {
            content.textRenderer(moteur)
        } else {
            content
        }
    }
}

/// Le texte d'un bloc en prose, et **rien d'autre**.
///
/// Séparée de `FlowingVerses` pour une seule raison : être `Equatable`, donc
/// pouvoir être sautée. Tout ce qui la rend est ici, sous forme de valeurs
/// comparables — pas d'environnement, pas de fermeture, pas de liaison.
///
/// ## Ce que ça corrige
///
/// La sélection était lente en prose continue, et la fusion des blocs en est la
/// cause indirecte : un bloc n'est plus un verset mais une section entière, et
/// chaque appui faisait recomposer **et remettre en page** tous les blocs de
/// l'unité, y compris ceux que la sélection ne touche pas. La composition
/// coûte 0,14 ms par verset — mesuré, linéaire — mais la mise en page d'un
/// `Text` de trente versets coûte bien plus, et elle avait lieu partout.
private struct Prose: View, Equatable {
    let verses: [Verse]
    let theme: ONTTheme
    let surlignages: [Int: Color]

    /// Les versets ne sont **pas** comparés en profondeur.
    ///
    /// Un `Verse` porte son arbre d'inline ; comparer trente arbres à chaque
    /// appui coûterait ce que le saut cherche à économiser. Dans une unité
    /// ouverte, le contenu d'un bloc ne change pas — son premier numéro et sa
    /// longueur l'identifient donc suffisamment.
    /// `nonisolated` : la comparaison ne touche que des valeurs, et SwiftUI
    /// peut l'appeler hors de l'acteur principal. Sans cette annotation, la
    /// conformité franchit la frontière d'isolation et Swift 6 la refuse.
    nonisolated static func == (a: Prose, b: Prose) -> Bool {
        a.verses.first?.n == b.verses.first?.n
            && a.verses.count == b.verses.count
            && a.surlignages == b.surlignages
            && a.theme == b.theme
    }

    var body: some View {
        ONTTextRenderer.flowingText(
            verses: verses,
            theme: theme,
            highlight: { surlignages[$0] }
        )
        .lineSpacing(theme.lineSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Les versets à la suite, en prose continue.
///
/// Un seul `Text` pour tout un bloc. La découpe en versets reste lisible —
/// les numéros sont là, en exposant — mais elle ne coupe plus la phrase.
/// C'est la lecture suivie ; le bloc par verset reste le mode d'étude.
private struct FlowingVerses: View {
    @Environment(\.ontSuivi) private var suivi
    @Environment(ReadingModel.self) private var model
    @Environment(Router.self) private var router
    @Environment(\.ontTheme) private var theme
    var spacing = ONTSpacing()

    let verses: [Verse]
    let chapter: Chapter
    @Binding var selection: Set<Int>

    /// La part de la sélection qui tombe dans ce bloc.
    private var selectionLocale: Set<Int> {
        selection.isEmpty ? [] : selection.intersection(verses.map(\.n))
    }

    /// La part de hauteur que chaque verset occupe dans le bloc.
    ///
    /// Au prorata des signes affichés — c'est ce qu'on a de plus proche de la
    /// hauteur réelle sans demander sa mise en page au moteur de texte. Un
    /// verset vide de tout signe recevrait une part nulle et deviendrait
    /// inatteignable : on lui en garantit une minime.
    private var parts: [(verset: Int, part: CGFloat)] {
        let signes = verses.map { verse in
            max(
                1,
                verse.nodes.plainText(
                    gloss: theme.preferences.showGloss,
                    level3: theme.preferences.showLevel3
                ).count
            )
        }
        let total = CGFloat(signes.reduce(0, +))
        return zip(verses, signes).map { verse, compte in
            (verset: verse.n, part: CGFloat(compte) / total)
        }
    }

    /// L'échelle de l'écran — deux ou trois pixels par point.
    ///
    /// Elle entre dans le plafond parce que le tampon se compte en **pixels**
    /// quand la vue se mesure en points : le même bloc tient sur un écran à
    /// deux, et déborde à trois.
    @Environment(\.displayScale) private var echelleDeLEcran

    /// La hauteur rendue du bloc, relevée à sa pose.
    ///
    /// Zéro avant la première mesure — et le moteur ne se pose donc pas au
    /// premier passage. C'est le bon sens de l'inégalité : on n'estompe qu'une
    /// fois qu'on sait que c'est sans danger.
    @State private var hauteur: CGFloat = 0

    /// Le plafond d'un tampon de rendu, en points.
    ///
    /// Demandé au GPU plutôt qu'écrit en dur. La première parade inscrivait
    /// 8192 px, relevé sur le simulateur — vrai là, et faux sur un téléphone,
    /// qui en accepte le double depuis l'A11. Le plafond prudent coûtait alors
    /// l'estompage sur presque toutes les sections : une section de Bereshit 19
    /// fait 13 695 px, sous ce que la machine sait faire et au-dessus de ce
    /// qu'on lui accordait. Voir `ONTTampon`.
    private var plafondDuTampon: CGFloat {
        ONTTampon.plafondEnPoints(echelle: echelleDeLEcran)
    }

    private var peutEstomper: Bool {
        !selection.isEmpty && hauteur > 0 && hauteur <= plafondDuTampon
    }

    /// Les surlignages de ce bloc, relevés une fois.
    ///
    /// En table plutôt qu'en fermeture : une fermeture n'est pas comparable,
    /// donc elle rendrait `Prose` toujours différente d'elle-même et le saut
    /// ne se produirait jamais.
    private var surlignages: [Int: Color] {
        verses.reduce(into: [:]) { table, verse in
            guard let marque = model.highlight(chapterId: chapter.id, verse: verse.n) else { return }
            table[verse.n] = ONTColors.highlight(marque.color, theme.mode)
                .opacity(ONTColors.highlightOpacity)
        }
    }

    var body: some View {
        Prose(
            verses: verses,
            theme: theme,
            surlignages: surlignages
        )
        // `.equatable()` protège la **composition**. Le texte ne dépendant plus
        // de la sélection, ce corps n'est plus réévalué pour un appui — et la
        // mise en page du bloc a donc lieu une seule fois, à son apparition.
        .equatable()
        // La sélection vit ici, dans le moteur de dessin. Il change à chaque
        // appui, et c'est voulu : SwiftUI **redessine** sans remettre en page.
        //
        // C'était la cause de la lenteur. Estompage et soulignement écrits dans
        // la chaîne composée la faisaient changer, donc SwiftUI refaisait la
        // mise en page de toute la section — 31,3 ms pour trente versets, quand
        // le mode blocs n'en refait que 0,9. Aucune des deux ne déplace un
        // glyphe, mais rien ne permettait de le lui dire.
        //
        // Et **seulement** quand une sélection existe. Sans elle, le moteur ne
        // fait rien : il recopie le contexte et redessine chaque fragment tel
        // quel. Il coûtait pourtant la moitié du livre.
        //
        // ## Ce qu'on a mesuré
        //
        // Dix chapitres de Bereshit sur dix-neuf ne s'affichaient pas — titre
        // de section visible, texte absent. Le corpus était sain, les blocs
        // construits, le texte composé (jusqu'à 1350 caractères par verset),
        // mis en page (blocs de 2878 à 4042 pt) et `draw` appelé avec ses
        // 95 lignes. Tout fonctionnait, et rien ne s'affichait.
        //
        // La frontière s'est révélée en comparant la hauteur du **premier**
        // bloc de chaque chapitre — un chapitre paraît vide quand c'est son
        // premier bloc qui se tait :
        //
        //     ch12  7250 px  s'affiche
        //     ch6   8634 px  muet
        //     ch14 13067 px  muet
        //
        // Soit 8192 px, la taille maximale d'un tampon de rendu. Poser un
        // `TextRenderer` oblige SwiftUI à rasteriser le `Text` hors écran pour
        // le donner au moteur ; au-delà de cette hauteur le tampon n'existe
        // pas, et le dessin est silencieusement perdu. Aucune erreur, aucune
        // trace — le texte est simplement absent.
        //
        // La lecture suivie fabrique exactement ces blocs-là : une section
        // entière en un seul `Text`. Plus le lecteur grossit le texte, plus il
        // en perd — l'inverse de ce que le réglage promet.
        //
        // Ne poser le moteur qu'avec une sélection rend la lecture — le cas de
        // très loin le plus fréquent — à un rendu natif, sans tampon et sans
        // limite. Il reste que sélectionner un verset dans une section très
        // haute retombe dans le même piège : c'est un chantier à part, qui
        // demande de renoncer au bloc unique.
        //
        // Le bloc est donc **mesuré**, et le moteur ne se pose que s'il tient
        // dans un tampon. Un bloc trop haut perd l'estompage — le verset
        // désigné ne se détache plus de ses voisins — mais il reste lisible.
        // Perdre une nuance vaut mieux que perdre le texte, et la carte
        // d'actions comme le renvoi du titre disent déjà ce qui est désigné.
        //
        // Mesuré plutôt que deviné à partir du nombre de caractères : la
        // hauteur dépend de la fonte, du corps choisi, du curseur système et de
        // la largeur de l'écran. Une estimation se tromperait exactement là où
        // le lecteur a le plus grossi son texte.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { hauteur = $0 }
        .modifier(Estompage(moteur: peutEstomper ? ONTProseRenderer(
            selection: selectionLocale,
            uneSelectionExiste: true,
            estompe: ONTColors.dimmedOpacity,
            trait: ONTColors.accent(theme.mode).opacity(0.8),
            corps: theme.scaledTextSize
        ) : nil))
        .padding(.horizontal, spacing.xs)
        // Des ancres invisibles, une par verset, **derrière** la prose.
        //
        // ## Ce qu'elles réparent
        //
        // En prose, un bloc est une section entière dans un seul `Text` : il
        // n'y a plus de vue par verset. La reprise de lecture retenait donc le
        // **premier verset du bloc**, et « Reprendre » ramenait au début de la
        // section au lieu de l'endroit qu'on lisait. Tant que les blocs
        // valaient un verset, ça ne se voyait pas ; la fusion l'a révélé.
        //
        // ## Pourquoi une superposition
        //
        // Elle ne participe pas à la mise en page — elle épouse la taille du
        // texte, sans rien lui imposer. Chaque ancre reçoit la part de hauteur
        // que son verset occupe dans le bloc, estimée sur le **nombre de
        // signes réellement affichés** : les gloses et l'hébreu comptent quand
        // ils sont allumés, et pas quand ils sont éteints.
        //
        // C'est une approximation — un verset serré et un verset aéré ne
        // tiennent pas la même place à nombre de signes égal. Elle vaut à un
        // verset près, là où l'ancien procédé se trompait d'une section
        // entière. Et surtout elle rend les deux sens : ces ancres sont à la
        // fois ce que `proxy.scrollTo` vise et ce qui dit où l'on est.
        .overlay {
            GeometryReader { cadre in
                VStack(spacing: 0) {
                    ForEach(parts, id: \.verset) { part in
                        Color.clear
                            .frame(height: cadre.size.height * part.part)
                            .id(VerseAnchor(n: part.verset))
                            .onScrollVisibilityChange(threshold: 0.5) { visible in
                                if visible { suivi.entre(part.verset) } else { suivi.sort(part.verset) }
                            }
                    }
                }
            }
            // Une matière de repérage, pas une cible : elle ne doit voler ni un
            // appui sur un intraduisible, ni le curseur de VoiceOver.
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        // Une seule voix pour la section, au lieu de quatre-vingt-quinze.
        //
        // ## Ce qu'on a mesuré
        //
        // Chaque fragment de la prose porte un lien — le renvoi qui rend le
        // verset touchable — et SwiftUI en fait autant d'éléments
        // d'accessibilité. Relevé sur Bereshit 11 : sept textes, et
        // **quatre-vingt-quinze liens**. VoiceOver les annonce un à un, chacun
        // précédé de « lien », coupés là où le balisage change et non là où la
        // phrase finit :
        //
        //     lien »  unifiés (devarim ahadim / …) [
        //     lien » devarim
        //     lien »  — intraduisible, pluriel de
        //
        // Le texte n'était donc pas muet — il était haché, et illisible à
        // l'oreille pour cette raison.
        //
        // ## Ce qu'on perd, et pourquoi c'est le bon échange
        //
        // En ignorant les enfants, on prive VoiceOver du moyen de désigner un
        // verset par un appui. L'appui visuel, lui, ne bouge pas : la
        // détection tactile ne passe pas par l'arbre d'accessibilité.
        //
        // Pouvoir lire un chapitre d'une traite vaut mieux que pouvoir en
        // surligner un verset sans pouvoir le lire. Rendre les deux demande de
        // sortir la sélection des liens — un chantier, pas un réglage.
        // ## Pourquoi une **représentation** et non une étiquette
        //
        // `accessibilityElement(children: .ignore)` ne change rien ici, et on
        // s'en est assuré avant d'écrire ceci : quatre-vingt-quinze liens
        // avant, quatre-vingt-quinze après. Ce modificateur écarte les vues
        // **enfants** ; or ces liens ne sont pas des vues, ils naissent dans
        // l'`AttributedString` d'un seul `Text` et SwiftUI les expose depuis
        // l'intérieur.
        //
        // `accessibilityRepresentation` remplace l'arbre entier par celui d'une
        // autre vue. On lui donne un texte nu — même contenu, aucun lien — et
        // c'est lui que VoiceOver rencontre.
        .accessibilityRepresentation {
            Text(ONTTextRenderer.aLireAVoixHaute(verses: verses, theme: theme))
                // Du texte suivi : VoiceOver en change l'intonation et permet
                // d'y naviguer par phrase plutôt que d'un bloc à l'autre.
                .accessibilityTextContentType(.narrative)
        }
    }
}

// MARK: - Les blocs

private struct BlockView: View {
    @Environment(\.ontTheme) private var theme
    var spacing = ONTSpacing()

    let block: Block
    let chapter: Chapter
    @Binding var noteTarget: VerseSelection?
    @Binding var selection: Set<Int>

    /// Titres, paragraphes et listes reculent avec le reste : un intertitre
    /// resté noir au milieu d'une page estompée attirerait l'œil plus que la
    /// sélection elle-même.
    private var dim: Double { selection.isEmpty ? 1 : ONTColors.dimmedOpacity }

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
                            .foregroundStyle(ONTColors.accent(theme.mode))
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
    var spacing = ONTSpacing()

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
            .foregroundStyle(ONTColors.accent(theme.mode))

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
    @Environment(\.ontTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let chapter: Chapter
    let verse: Int

    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("\(chapter.title):\(verse)") {
                    // `TextEditor` porte son propre fond, et il ne vient pas
                    // de la ligne : il reste gris système au milieu d'une nuit
                    // aubergine, même quand la section qui l'entoure est
                    // habillée. On le cache pour laisser voir la surface du
                    // thème derrière, et l'encre suit le thème comme le reste.
                    TextEditor(text: $text)
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(theme.ink)
                        .frame(minHeight: 140)
                }
                .ontRow()
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
            // Une feuille reste un écran, et suit donc le thème comme les
            // autres. Sans ces deux lignes, écrire une note faisait surgir un
            // formulaire gris système au milieu de la nuit aubergine.
            .ontRow()
            .ontScreen()
        }
        .presentationDetents([.medium])
    }
}


// MARK: - Réglages

/// Les réglages de lecture — les trois niveaux, la taille, la fonte, le thème.
public struct ReadingSettingsSheet: View {
    @Environment(ReadingModel.self) private var model

    /// Le chapitre ouvert, quand la feuille est appelée depuis la lecture.
    ///
    /// Facultatif : depuis l'onglet « Vous », il n'y a pas de chapitre
    /// courant, et l'aperçu retombe alors sur la dernière lecture.
    private let chapter: Chapter?

    public init(chapter: Chapter? = nil) {
        self.chapter = chapter
    }

    @State private var confirmeReset = false

    /// Le chapitre à montrer dans l'aperçu.
    private var previewed: Chapter? {
        if let chapter { return chapter }
        guard let position = model.position else { return nil }
        return model.chapter(book: position.bookId, id: position.chapterId)
    }

    /// Le contenu seul — **sans** pile de navigation.
    ///
    /// Elle en créait une, et c'était juste tant qu'un seul appelant existait.
    /// Depuis « Vous », la feuille est poussée par un `NavigationLink` : elle
    /// se retrouvait à empiler sa propre pile dans celle de l'onglet, ce qui
    /// donnait deux barres de navigation, un titre en double et un « OK » qui
    /// ne dépilait pas ce que le lecteur croyait.
    ///
    /// Une vue de destination ne décide pas de sa présentation. C'est
    /// l'appelant qui sait s'il pousse ou s'il présente, donc c'est à lui de
    /// fournir la pile et le bouton qui la referme.
    public var body: some View {
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
                .ontRow()

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
                .ontRow()

                Section {
                    LabeledContent("Taille") {
                        Slider(value: $model.preferences.textSize, in: 11...28, step: 1)
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
                .ontRow()

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
                .ontRow()

                Section {
                    ThemeRow(selection: $model.preferences.theme)
                } header: {
                    Text("Thème")
                } footer: {
                    Text("Mystique est la peau du site ontbible.com — nuit aubergine et or.")
                }
                .ontRow()

                Section {
                    Button("Réinitialiser les réglages", role: .destructive) {
                        confirmeReset = true
                    }
                    // Éteint quand il n'y a rien à annuler : un bouton actif
                    // qui ne ferait rien laisse croire qu'on avait changé
                    // quelque chose.
                    .disabled(model.preferences.isDisplayDefault)
                } footer: {
                    Text(
                        "Ramène disposition, niveaux, corps, fonte et thème à leur "
                            + "état de départ. Le rappel du verset du jour n'est pas touché."
                    )
                }
                .ontRow()
        }
        // Une confirmation, parce que le geste est court et la perte réelle :
        // qui a réglé sa taille de texte pour y voir ne veut pas la retrouver
        .ontRow()
        .ontScreen()
        // au départ pour avoir effleuré une ligne rouge.
        .confirmationDialog(
            "Revenir aux réglages de départ ?",
            isPresented: $confirmeReset,
            titleVisibility: .visible
        ) {
            Button("Réinitialiser", role: .destructive) {
                model.preferences = model.preferences.resettingDisplay()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Votre taille de texte, votre fonte et votre thème reviennent au départ.")
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
    var spacing = ONTSpacing()

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
        // L'aperçu n'a plus à reposer le thème pour lui seul : la feuille
        // entière le fait désormais, et il en hérite comme le reste.
        PreviewBody(verses: verses, title: chapter.title)
    }

    private struct PreviewBody: View {
        @Environment(\.ontTheme) private var theme
        var spacing = ONTSpacing()

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
                    // L'aperçu emprunte les **deux** chemins de rendu de la
                    // liseuse, et non le seul mode blocs comme il le faisait :
                    // « Versets à la suite » est le réglage qui change le plus
                    // la page, et c'était le seul que l'aperçu taisait. On
                    // basculait à l'aveugle, on refermait pour voir.
                    Group {
                        if theme.preferences.continuous {
                            // Rien de surligné : un aperçu montre la mise en
                            // page, pas l'état d'une lecture en cours.
                            ONTTextRenderer.flowingText(
                                verses: verses,
                                theme: theme,
                                highlight: { _ in nil }
                            )
                            .lineSpacing(theme.lineSpacing)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            // `theme.verseSpacing` et non un écart fixe : c'est
                            // ce que la liseuse emploie entre deux versets, et
                            // il dépend du curseur d'interligne. Avec un écart
                            // fixe, bouger ce curseur ne changeait ici que
                            // l'intérieur des versets, jamais ce qui les
                            // sépare — l'aperçu montrait la moitié du réglage.
                            VStack(alignment: .leading, spacing: theme.verseSpacing) {
                                ForEach(verses, id: \.n) { verse in
                                    Text(ONTTextRenderer.compose(verse: verse, theme: theme))
                                        .lineSpacing(theme.lineSpacing)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                    .padding(spacing.m)
                }
                // La prose continue pose un lien sur chaque verset, pour que la
                // liseuse sache lequel on touche. Ici il n'y a rien à
                // désigner : sans cette garde, effleurer l'aperçu naviguerait.
                .environment(\.openURL, OpenURLAction { _ in .handled })
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
/// La rangée du thème, peinte à la main.
///
/// ## Pourquoi elle ne se contente pas d'un `Picker`
///
/// Un `Picker` en menu tire ses couleurs de la **teinte**, et la teinte d'une
/// feuille est capturée au moment où on la présente. Or c'est ici qu'on change
/// de thème : la feuille est déjà ouverte, donc la teinte reste celle d'avant.
/// La valeur s'écrivait en bordeaux sur l'aubergine — 1,2:1 — et il fallait
/// refermer la feuille pour qu'elle redevienne or.
///
/// Reposer le thème n'y change rien : vérifié, y compris au plus près du
/// contenu. On ne compte donc plus sur la teinte, on peint. `FontRow` fait
/// pareil depuis toujours, et c'est pourquoi les fontes, elles, étaient justes.
///
/// ## Ce qu'on garde du `Picker`
///
/// Le menu, et lui seul. À quatre thèmes, un segmenté tronque « Parchemin » et
/// « Mystique » — d'autant plus vite que le lecteur a monté sa taille de texte,
/// c'est-à-dire exactement quand il a besoin de lire les libellés.
private struct ThemeRow: View {
    @Environment(\.ontTheme) private var theme
    @Binding var selection: ReadingTheme

    var body: some View {
        Menu {
            // Des boutons, et non un `Picker` niché dans le menu.
            //
            // Imbriquer les deux fait cohabiter deux mécanismes de choix : le
            // menu marque alors sa **première** ligne d'un liseré gris, quelle
            // que soit la valeur retenue. On voyait « Parchemin » surligné
            // pendant que la coche était sur « Clair » — l'œil lit un choix,
            // la coche en dit un autre.
            //
            // La coche est posée à la main, sur celui qui la mérite.
            ForEach(ReadingTheme.allCases, id: \.self) { choix in
                Button {
                    selection = choix
                } label: {
                    if choix == selection {
                        Label(choix.label, systemImage: "checkmark")
                    } else {
                        Text(choix.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text("Thème")
                    .foregroundStyle(theme.ink)
                Spacer(minLength: 8)
                Text(selection.label)
                    .foregroundStyle(ONTColors.brandInk(theme.mode))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ONTColors.brandInk(theme.mode))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

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
