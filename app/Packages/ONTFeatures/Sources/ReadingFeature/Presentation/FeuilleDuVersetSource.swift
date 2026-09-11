import ONTDesignSystem
import ONTKit
import SwiftUI

// MARK: - Ce que la feuille affiche

/// Un mot du texte source, tel que la feuille le rend.
///
/// **Un type de présentation, distinct du domaine**, et c'est délibéré : la
/// feuille a besoin d'un *index stable* pour se paginer, ce dont le domaine n'a
/// aucune raison de s'encombrer. L'adaptation se fait au point d'entrée, une
/// fois.
public struct MotAffiche: Identifiable, Hashable, Sendable {
    /// La **position** dans le verset. Pas le numéro de Strong : deux mots d'un
    /// même verset peuvent porter le même lemme, et la pagination les
    /// confondrait.
    public let id: Int
    /// La forme telle qu'elle s'écrit — voyelles et cantillation comprises.
    public let forme: String
    /// Le numéro de Strong, tel que le témoin l'écrit.
    public let strong: String?
    /// Le code morphologique du témoin — « HVqp3ms ».
    public let morphologie: String?
    /// La fiche ONT que ce mot ouvre, quand il en ouvre une.
    public let fiche: CibleDuNiveauTrois?

    public init(
        id: Int,
        forme: String,
        strong: String? = nil,
        morphologie: String? = nil,
        fiche: CibleDuNiveauTrois? = nil
    ) {
        self.id = id
        self.forme = forme
        self.strong = strong
        self.morphologie = morphologie
        self.fiche = fiche
    }
}

/// Un verset du texte source.
public struct VersetAffiche: Identifiable, Hashable, Sendable {
    /// La **position** dans l'unité, et jamais le numéro affiché.
    ///
    /// Le numéro n'est pas unique : quand une parashah couvre deux chapitres
    /// bibliques, la numérotation repart à ¹ au second, et *Bereshit* 7 porte
    /// ainsi deux versets « 1 ». C'est le piège que `sources.rs` documente pour
    /// l'apparat critique, et il vaut ici mot pour mot.
    public let id: Int
    /// Le numéro à afficher.
    public let numero: Int
    /// Le verset entier, joint — il garde la ponctuation que les mots perdent.
    public let texte: String
    public let mots: [MotAffiche]

    public init(id: Int, numero: Int, texte: String, mots: [MotAffiche]) {
        self.id = id
        self.numero = numero
        self.texte = texte
        self.mots = mots
    }
}

/// Un témoin disponible pour cette unité.
public struct TemoinAffiche: Identifiable, Hashable, Sendable {
    public let id: String
    /// « Hébreu · WLC ».
    public let nom: String
    /// Le code de langue — `he`, `grc`, `gez`.
    public let langue: String

    public init(id: String, nom: String, langue: String) {
        self.id = id
        self.nom = nom
        self.langue = langue
    }
}

// MARK: - La feuille

/// **Le verset d'origine, mot à mot.**
///
/// ## Ce que l'auteur a demandé, et la forme qu'il a montrée
///
/// « Au long press tu ouvres une sheet : en haut le texte, en bas sa
/// signification, et chaque mot cliquable. Possible de switcher de verset en
/// swipant le verset à droite comme à gauche, et aussi de switcher de mot en
/// swipant les définitions. Et on garde notre DA. »
///
/// Deux axes de glissement, donc, et ils ne disent pas la même chose : le haut
/// change **de verset**, le bas change **de mot**. C'est ce qui permet de
/// parcourir un verset sans le quitter, puis de passer au suivant sans revenir
/// en arrière.
///
/// ## Ce qui est tranché ici, et pourquoi
///
/// **En haut, c'est l'hébreu — pas le français.** On ne possède aucun
/// alignement mot à mot entre la traduction ONT et sa source ; l'inventer
/// reviendrait à deviner, et le lecteur ne pourrait pas voir l'erreur. C'est
/// aussi la fonctionnalité demandée : *faire apparaître le verset d'origine*.
///
/// **Tout mot s'ouvre, même sans fiche.** Arbitré par l'auteur : 92 % des mots
/// n'ont pas encore de fiche ONT, et un mot inerte se lit comme une panne
/// tandis qu'un mot qui dit « je n'ai pas encore de fiche » enseigne l'état du
/// lexique. C'est le même arbitrage que pour les renvois bibliques, le même
/// jour.
public struct FeuilleDuVersetSource: View {
    @Environment(\.ontTheme) private var theme
    private let spacing = ONTSpacing()
    @Environment(\.openURL) private var openURL

    let titreDeLUnite: String
    let temoins: [TemoinAffiche]
    let versets: [VersetAffiche]

    @Binding var temoinChoisi: String
    @State private var position: Int
    @State private var mot: Int = 0

    public init(
        titreDeLUnite: String,
        temoins: [TemoinAffiche],
        versets: [VersetAffiche],
        temoinChoisi: Binding<String>,
        positionInitiale: Int
    ) {
        self.titreDeLUnite = titreDeLUnite
        self.temoins = temoins
        self.versets = versets
        self._temoinChoisi = temoinChoisi
        self._position = State(initialValue: positionInitiale)
    }

    private var verset: VersetAffiche? {
        versets.indices.contains(position) ? versets[position] : nil
    }

    public var body: some View {
        VStack(spacing: 0) {
            entete
            Divider().overlay(theme.separator)
            if let verset {
                corpsDuVerset(verset)
                Divider().overlay(theme.separator)
                cartesDesMots(verset)
            } else {
                indisponible
            }
        }
        .background(theme.background)
    }

    // MARK: - L'en-tête

    private var entete: some View {
        VStack(alignment: .leading, spacing: spacing.xs) {
            Text(titreDeLUnite)
                .font(ONTUI.headline)
                .foregroundStyle(theme.ink)
            // **Le sélecteur ne paraît qu'à partir de deux témoins.** Un
            // segment unique n'offre aucun choix : il occupe la hauteur d'une
            // décision pour n'en présenter aucune.
            if temoins.count > 1 {
                ONTSegments(
                    selection: $temoinChoisi,
                    segments: temoins.map { ($0.id, $0.nom) }
                )
            } else if let seul = temoins.first {
                Text(seul.nom)
                    .font(ONTUI.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, spacing.page)
        .padding(.vertical, spacing.m)
    }

    // MARK: - Le verset

    /// Le verset en bloc, de droite à gauche, chaque mot touchable.
    ///
    /// **Le glissement horizontal change de verset**, et il est posé sur la
    /// zone entière plutôt que sur le texte : viser les lettres pour feuilleter
    /// serait un jeu d'adresse, exactement ce que la lecture évite déjà pour la
    /// désignation d'un verset.
    private func corpsDuVerset(_ v: VersetAffiche) -> some View {
        VStack(alignment: .leading, spacing: spacing.s) {
            Text("verset \(v.numero)")
                .font(ONTUI.caption)
                .foregroundStyle(.secondary)

            // **Le verset prend la hauteur qu'il lui faut, et pas davantage.**
            //
            // Une zone défilante sans borne réclame toute la place disponible :
            // à l'écran, un verset de sept mots laissait un trou vertical de
            // trois cents points entre lui et sa pagination. Le défilement ne
            // sert qu'aux versets longs — il ne doit pas se payer sur les
            // courts.
            ScrollView(.vertical) {
                motsEnFlot(v)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .scrollBounceBehavior(.basedOnSize)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: 260)

            pagination
        }
        .padding(.horizontal, spacing.page)
        .padding(.bottom, spacing.m)
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .gesture(glissementDesVersets)
    }

    /// Les mots, posés en flot et alignés à droite.
    ///
    /// `layoutDirection` plutôt qu'un `HStack` inversé à la main : l'hébreu
    /// n'est pas du latin qu'on renverse, et le système sait déjà couper les
    /// lignes dans le bon sens. Le flot suit alors le texte réel — un verset
    /// long se replie comme il se replierait sur une page.
    private func motsEnFlot(_ v: VersetAffiche) -> some View {
        FlotDeMots(
            mots: v.mots,
            choisi: mot,
            theme: theme,
            spacing: spacing
        ) { index in
            // Une animation courte : le lecteur suit son doigt du haut vers le
            // bas, et une transition lente lui ferait perdre le lien entre le
            // mot qu'il touche et la carte qui répond.
            withAnimation(.snappy(duration: 0.22)) { mot = index }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var pagination: some View {
        HStack {
            bouton("Verset précédent", "chevron.left", actif: position > 0) {
                changerDeVerset(-1)
            }
            Spacer()
            bouton(
                "Verset suivant", "chevron.right",
                actif: position + 1 < versets.count
            ) {
                changerDeVerset(+1)
            }
        }
        .font(ONTUI.footnote)
    }

    private func bouton(
        _ titre: String, _ symbole: String, actif: Bool, _ action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(titre, systemImage: symbole)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.plain)
        .foregroundStyle(actif ? theme.accent : Color.secondary)
        .disabled(!actif)
        .accessibilityHidden(!actif)
    }

    /// **Le sens du glissement est celui de l'écriture.**
    ///
    /// L'hébreu se lit de droite à gauche : glisser **vers la droite** ramène
    /// donc au verset précédent, comme on tourne une page vers l'arrière dans
    /// un livre hébreu. L'inverse — calquer le geste latin — mettrait le
    /// lecteur à contresens du texte qu'il est en train de lire.
    private var glissementDesVersets: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { valeur in
                guard abs(valeur.translation.width) > abs(valeur.translation.height) else {
                    return
                }
                changerDeVerset(valeur.translation.width > 0 ? -1 : +1)
            }
    }

    /// Change de verset, et pose le mot **du côté d'où l'on vient**.
    ///
    /// `parDerriere` sert le débordement des cartes : en sortant par la fin
    /// d'un verset on entre au **premier** mot du suivant ; en sortant par le
    /// début on entre au **dernier** du précédent. Le parcours devient continu,
    /// et c'est précisément ce qu'on attend d'un carrousel qu'on pousse — la
    /// rupture entre « je change de mot » et « je change de verset » n'existe
    /// que dans le code, jamais sous le doigt.
    private func changerDeVerset(_ pas: Int, parDerriere: Bool = false) {
        let vise = position + pas
        guard versets.indices.contains(vise) else { return }
        withAnimation(.snappy(duration: 0.26)) {
            position = vise
            // **Le mot ne se conserve jamais d'un verset à l'autre** : garder
            // l'index désignerait un mot sans rapport, au hasard de deux
            // longueurs qui ne coïncident pas.
            mot = parDerriere ? max(versets[vise].mots.count - 1, 0) : 0
        }
    }

    private var indisponible: some View {
        VStack(spacing: spacing.s) {
            Text("Pas de texte source pour cette unité")
                .font(ONTUI.headline)
            Text("Le témoin ne couvre pas encore ce passage.")
                .font(ONTUI.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(spacing.page)
    }
}

// MARK: - Les cartes des mots

extension FeuilleDuVersetSource {
    /// Les définitions, une carte par mot, feuilletées à l'horizontale.
    ///
    /// **La carte voisine dépasse volontairement**, et c'est la seule chose qui
    /// dit qu'il y en a une. Un carrousel qui remplit exactement la largeur ne
    /// s'annonce pas : le lecteur ne glisse que s'il devine qu'il y a quelque
    /// chose à atteindre.
    ///
    /// Les deux sens sont liés : toucher un mot en haut fait défiler les cartes,
    /// et faire défiler les cartes désigne le mot en haut. Un seul état — `mot`
    /// — tient les deux, sinon ils divergent au premier geste rapide.
    fileprivate func cartesDesMots(_ v: VersetAffiche) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                // **`HStack` et non `LazyHStack`.** Un verset porte une
                // vingtaine de mots, jamais mille : la paresse n'achète rien
                // et coûte une vue qui ne se rend pas hors d'un vrai
                // défilement — ce qui rend tout banc d'essai aveugle.
                HStack(spacing: spacing.m) {
                    ForEach(v.mots) { m in
                        CarteDuMot(mot: m, actif: m.id == mot) {
                            ouvrir(m)
                        }
                        .containerRelativeFrame(.horizontal, count: 4, span: 3, spacing: spacing.m)
                        .id(m.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, spacing.page)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollPosition(id: Binding(
                get: { Optional(mot) },
                set: { if let n = $0 { mot = n } }
            ))
            .onChange(of: mot) { _, n in
                withAnimation(.snappy(duration: 0.22)) { proxy.scrollTo(n, anchor: .leading) }
            }
            // **Pousser au-delà du dernier mot change de verset.**
            //
            // Demandé par l'auteur, et c'est le bon réflexe : un carrousel
            // qu'on pousse et qui bute sans rien faire se lit comme une fin de
            // course, alors que le texte, lui, continue. Les deux axes cessent
            // d'être deux : on parcourt un verset, puis le suivant, du même
            // geste.
            //
            // `simultaneousGesture` plutôt qu'un `gesture` : le défilement du
            // carrousel garde la main, et l'on ne lit la course qu'à la fin,
            // quand elle n'a plus rien à déplacer.
            .simultaneousGesture(
                DragGesture(minimumDistance: 30).onEnded { valeur in
                    guard abs(valeur.translation.width) > abs(valeur.translation.height) else {
                        return
                    }
                    let dernier = max(v.mots.count - 1, 0)
                    // Vers la gauche : on avance dans les cartes. Sorti par la
                    // fin, on entre au premier mot du verset suivant.
                    if valeur.translation.width < 0, mot >= dernier {
                        changerDeVerset(+1)
                    } else if valeur.translation.width > 0, mot <= 0 {
                        changerDeVerset(-1, parDerriere: true)
                    }
                }
            )
        }
        .padding(.vertical, spacing.m)
    }

    /// Ouvre la fiche ONT du mot, quand il en a une.
    ///
    /// On réemploie les adresses `ont://term/` et `ont://shem/` que le routeur
    /// sert déjà : la fiche qui se soulève est **exactement la même** que celle
    /// qu'on obtient en touchant un intraduisible dans le corps du texte. Une
    /// seconde présentation pour le même contenu finirait par diverger.
    fileprivate func ouvrir(_ m: MotAffiche) {
        guard let fiche = m.fiche else { return }
        let url: URL? =
            switch fiche {
            case .term(let lemma): ONTTextRenderer.termURL(lemma)
            case .shem(let lemma): ONTTextRenderer.shemURL(lemma)
            }
        if let url { openURL(url) }
    }
}

/// Une carte de définition.
private struct CarteDuMot: View {
    @Environment(\.ontTheme) private var theme
    private let spacing = ONTSpacing()

    let mot: MotAffiche
    let actif: Bool
    let ouvrir: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: spacing.s) {
            Text(isole(mot.forme))
                .font(theme.type.hebrew.font)
                .foregroundStyle(theme.ink)
                .environment(\.layoutDirection, .rightToLeft)

            if let morphologie = mot.morphologie {
                Text(morphologie)
                    .font(ONTUI.caption)
                    .foregroundStyle(.secondary)
                    .monospaced()
            }

            Rectangle()
                .fill(actif ? theme.accent : theme.separator)
                .frame(width: 44, height: 2)

            contenu

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(spacing.m)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: ONTRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: ONTRadius.card)
                .strokeBorder(actif ? theme.accent.opacity(0.5) : theme.separator)
        }
        // **L'opacité dit lequel est choisi**, et non un cadre seul : l'auteur
        // lit à moins d'un dixième d'acuité, et un liseré de un point ne se
        // distingue pas d'un défaut de rendu.
        .opacity(actif ? 1 : 0.55)
    }

    @ViewBuilder private var contenu: some View {
        if mot.fiche != nil {
            Button(action: ouvrir) {
                Label("Ouvrir la fiche", systemImage: "chevron.right")
                    .font(ONTUI.callout)
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.accent)
        } else {
            // **Le message plutôt que le vide**, arbitré par l'auteur. Il dit
            // l'état du lexique au lieu de laisser croire à une panne — et il
            // le dira pour 92 % des mots le premier jour, ce qui est
            // exactement l'information.
            Text("Ce mot n'a pas encore de fiche ONT.")
                .font(ONTUI.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if let strong = mot.strong {
            Text("Strong \(strong)")
                .font(ONTUI.caption)
                .foregroundStyle(.tertiary)
        }
    }

    /// Isole la séquence hébraïque de son voisinage — voir `hebrewRun`.
    private func isole(_ v: String) -> String { "\u{2068}\(v)\u{2069}" }
}

// MARK: - Le flot des mots

/// Les mots du verset, posés comme du texte qui se replie.
///
/// **Pourquoi un `Layout` et non un `HStack` dans un `ScrollView`.** Un verset
/// hébreu tient rarement sur une ligne, et une bande qui défile à l'horizontale
/// n'est pas une phrase : le lecteur perd le retour à la ligne, donc le rythme.
/// SwiftUI n'offre pas de flot, alors on l'écrit — une soixantaine de lignes,
/// et le reste du système fait le travail, coupures et direction comprises.
private struct FlotDeMots: View {
    let mots: [MotAffiche]
    let choisi: Int
    let theme: ONTTheme
    let spacing: ONTSpacing
    let toucher: (Int) -> Void

    var body: some View {
        FlotLayout(espace: spacing.xs, interligne: spacing.s) {
            ForEach(mots) { m in
                Text("\u{2068}\(m.forme)\u{2069}")
                    .font(theme.type.hebrew.font)
                    .foregroundStyle(
                        m.id == choisi
                            ? theme.background
                            : (m.fiche == nil ? theme.ink : theme.accent)
                    )
                    .padding(.horizontal, spacing.xs)
                    .padding(.vertical, 2)
                    .background {
                        // Le mot choisi porte une surface, les autres rien.
                        // C'est la même grammaire que le surlignage d'un verset
                        // : une surface dit « c'est celui-ci », jamais « il
                        // s'est passé quelque chose ».
                        if m.id == choisi {
                            // **L'ambre à pleine force, et l'encre inversée.**
                            //
                            // À 22 % d'opacité la surface sortait presque noire
                            // sur le thème sombre — mesuré à l'écran. L'auteur
                            // lit à moins d'un dixième d'acuité : une marque
                            // qu'il faut chercher n'est pas une marque.
                            RoundedRectangle(cornerRadius: ONTRadius.highlight)
                                .fill(theme.accent)
                        }
                    }
                    .contentShape(.rect)
                    .onTapGesture { toucher(m.id) }
                    .accessibilityLabel(m.forme)
                    .accessibilityAddTraits(m.id == choisi ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

/// Un flot : on pose côte à côte tant qu'il y a la place, puis on descend.
private struct FlotLayout: Layout {
    let espace: CGFloat
    let interligne: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let largeur = proposal.width ?? .infinity
        let lignes = decouper(subviews, largeur: largeur)
        let hauteur = lignes.reduce(CGFloat.zero) { total, ligne in
            total + ligne.hauteur + (total > 0 ? interligne : 0)
        }
        return CGSize(width: largeur == .infinity ? lignes.map(\.largeur).max() ?? 0 : largeur,
                      height: hauteur)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let lignes = decouper(subviews, largeur: bounds.width)
        var y = bounds.minY
        for ligne in lignes {
            var x = bounds.minX
            for i in ligne.indices {
                let taille = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(
                    at: CGPoint(x: x, y: y + (ligne.hauteur - taille.height) / 2),
                    proposal: ProposedViewSize(taille)
                )
                x += taille.width + espace
            }
            y += ligne.hauteur + interligne
        }
    }

    private struct Ligne {
        var indices: [Int] = []
        var largeur: CGFloat = 0
        var hauteur: CGFloat = 0
    }

    private func decouper(_ subviews: Subviews, largeur: CGFloat) -> [Ligne] {
        var lignes: [Ligne] = []
        var courante = Ligne()
        for i in subviews.indices {
            let taille = subviews[i].sizeThatFits(.unspecified)
            let ajout = courante.indices.isEmpty ? taille.width : taille.width + espace
            // **Une ligne au moins un mot**, même trop large : sinon un mot plus
            // long que la colonne ferait boucler sans jamais être posé.
            if !courante.indices.isEmpty, courante.largeur + ajout > largeur {
                lignes.append(courante)
                courante = Ligne()
            }
            courante.indices.append(i)
            courante.largeur += courante.indices.count == 1 ? taille.width : ajout
            courante.hauteur = max(courante.hauteur, taille.height)
        }
        if !courante.indices.isEmpty { lignes.append(courante) }
        return lignes
    }
}

// MARK: - Le point d'entrée depuis la lecture

extension FeuilleDuVersetSource {
    /// Ouvre la feuille sur un verset désigné par sa position.
    ///
    /// **Le chargement se fait ici et non au point d'appel** : la vue de
    /// lecture n'a pas à savoir d'où viennent les langues sources, et le
    /// chargeur provisoire sera remplacé sans qu'elle bouge.
    init(titreDeLUnite: String, position: PositionDeVerset) {
        let temoins = ChargeurDeSources.temoins(de: position.livre)
        let premier = temoins.first?.id ?? ""
        self.init(
            titreDeLUnite: titreDeLUnite,
            temoins: temoins,
            versets: ChargeurDeSources.versets(
                temoin: premier, livre: position.livre, unite: position.unite),
            temoinChoisi: .constant(premier),
            positionInitiale: position.position
        )
    }
}
