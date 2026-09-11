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
    /// **La translittération, quand le vault l'a écrite quelque part.**
    ///
    /// Récoltée, jamais inventée : il n'existe aucun translittérateur dans ce
    /// dépôt, et en écrire un produirait des formes que l'auteur — qui lit
    /// l'hébreu ancien — verrait fausses immédiatement. Le pipeline prend donc
    /// les couples que les niveaux 3 du corpus portent déjà,
    /// `(bereshit / בְּרֵאשִׁית)`, et refuse ceux dont une même forme en porte
    /// deux différentes.
    ///
    /// Absente pour les deux tiers des mots aujourd'hui. C'est l'état du
    /// vault, pas un défaut du pont.
    public let translitteration: String?
    /// La fiche ONT que ce mot ouvre, quand il en ouvre une.
    public let fiche: CibleDuNiveauTrois?

    public init(
        id: Int,
        forme: String,
        strong: String? = nil,
        morphologie: String? = nil,
        translitteration: String? = nil,
        fiche: CibleDuNiveauTrois? = nil
    ) {
        self.id = id
        self.forme = forme
        self.strong = strong
        self.morphologie = morphologie
        self.translitteration = translitteration
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

    @Environment(\.ontFicheDunMot) private var ficheDunMot

    @Binding var temoinChoisi: String
    @State private var position: Int
    @State private var mot: Int = 0
    /// **Vrai quand la fiche a pris toute la feuille.**
    ///
    /// Un seul état pour les deux dispositions : le verset se replie, la fiche
    /// s'étend, et l'animation n'a rien à orchestrer — c'est la même vue qui
    /// change de place.
    @State private var agrandie = false

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
                // **Le verset et son filet partent ensemble.**
                //
                // Séparés, le filet n'avait aucune transition et disparaissait
                // d'un coup pendant que le verset glissait — l'aller et le
                // retour n'avaient donc pas le même mouvement. Un seul groupe,
                // une seule transition, et les deux sens se ressemblent.
                if !agrandie {
                    VStack(spacing: 0) {
                        corpsDuVerset(verset)
                        Divider().overlay(theme.separator)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
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
            // **Le verset prend ce qu'il lui faut, et la fiche prend le
            // reste.**
            //
            // Le premier jet lui donnait 260 points fixes, et le contenu s'y
            // centrait : un verset de sept mots laissait deux bandes vides
            // au-dessus et au-dessous pendant que la carte de définition, en
            // bas, était à l'étroit. L'auteur, capture à l'appui : « le verset
            // a pas besoin d'autant de place, donne plus de place à la fiche…
            // et dans le pire des cas on scroll ».
            //
            // `maxHeight` sans `fixedSize` : la zone ne réclame plus rien, elle
            // se contente de ce que son contenu occupe, et le plafond ne sert
            // qu'aux versets longs — qui défilent alors, ce qui est le bon prix.
            ScrollView(.vertical) {
                motsEnFlot(v)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    // **De l'air autour du verset, et pas une hauteur fixe.**
                    //
                    // La correction précédente avait supprimé les 260 points
                    // fixes — et avec eux, tout l'espace : le dernier mot
                    // venait toucher « Verset précédent ». L'auteur : « mets
                    // juste un petit peu plus d'espace, là tu l'as totalement
                    // supprimé. »
                    //
                    // Une marge appartient au contenu ; une hauteur appartient
                    // au conteneur. La première suit le verset qu'il soit long
                    // ou court, la seconde imposait la même bande à tous.
                    .padding(.vertical, spacing.l)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 240, alignment: .top)

            pagination
        }
        .padding(.horizontal, spacing.page)
        .padding(.bottom, spacing.m)
        .frame(maxWidth: .infinity, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
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
            withAnimation(ONTMouvement.ressortVif) { mot = index }
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
        withAnimation(ONTMouvement.arrivee) {
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
    ///
    /// ## Une seule zone défilante, agrandie ou non
    ///
    /// Le premier jet échangeait deux vues : un carrousel en petit, une carte
    /// seule en grand. Agrandir **détruisait** donc le carrousel, et revenir le
    /// reconstruisait à l'offset zéro — la carte arrivait de la droite au lieu
    /// de se redimensionner sur place, et le mot choisi se perdait en chemin.
    ///
    /// Deux symptômes, une cause : *ce que SwiftUI croit être la même chose*.
    /// La zone reste donc la même, et seule la largeur des cartes change. Il
    /// n'y a plus de transition à orchestrer — un cadre s'anime tout seul.
    ///
    /// La marge est sur la **zone** et non sur son contenu : c'est elle que
    /// `containerRelativeFrame` mesure, et une carte pleine largeur débordait
    /// de la marge quand celle-ci était au-dedans.
    fileprivate func cartesDesMots(_ v: VersetAffiche) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: spacing.m) {
                    ForEach(v.mots) { m in
                        CarteDuMot(
                            mot: m,
                            actif: agrandie ? m.id == mot : true,
                            fiche: m.fiche.flatMap(ficheDunMot),
                            agrandie: $agrandie
                        )
                        .containerRelativeFrame(
                            .horizontal,
                            count: agrandie ? 1 : 4,
                            span: agrandie ? 1 : 3,
                            spacing: spacing.m
                        )
                        .id(m.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            // Agrandie, on lit : le glissement horizontal n'a plus rien à
            // atteindre, et il volerait le geste de défilement du texte.
            .scrollDisabled(agrandie)
            .scrollPosition(
                id: Binding(
                    get: { Optional(mot) },
                    set: { if let n = $0 { mot = n } }
                )
            )
            .onChange(of: mot) { _, n in
                withAnimation(ONTMouvement.ressortVif) { proxy.scrollTo(n, anchor: .leading) }
            }
            // Le changement de largeur déplace la carte choisie : on la
            // remet sous l'œil dans le même mouvement.
            .onChange(of: agrandie) { _, _ in
                withAnimation(ONTMouvement.arrivee) { proxy.scrollTo(mot, anchor: .leading) }
            }
            .id(v.id)
        }
        .padding(.horizontal, spacing.page)
        .padding(.vertical, spacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

/// Une carte : le mot, sa morphologie, et **ce que l'ONT en dit**.
private struct CarteDuMot: View {
    @Environment(\.ontTheme) private var theme
    private let spacing = ONTSpacing()

    let mot: MotAffiche
    let actif: Bool
    let fiche: FicheAffichee?
    @Binding var agrandie: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: spacing.s) {
            entete
            Rectangle()
                .fill(actif ? theme.accent : theme.separator)
                .frame(width: 44, height: 2)
            contenu
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    private var entete: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isole(mot.forme))
                    .font(theme.type.hebrew.font)
                    .foregroundStyle(theme.ink)
                    .environment(\.layoutDirection, .rightToLeft)
                if let titre = fiche?.titre ?? mot.translitteration {
                    Text(titre)
                        .font(ONTUI.callout)
                        .foregroundStyle(theme.accent)
                }
                if let morphologie = mot.morphologie {
                    Text(morphologie)
                        .font(ONTUI.caption)
                        .foregroundStyle(.secondary)
                        .monospaced()
                }
            }
            Spacer(minLength: spacing.s)
            // **Le bouton d'agrandissement.** Il n'y a rien à orchestrer : le
            // verset se replie, la carte s'étend, et `withAnimation` interpole
            // la même vue d'une place à l'autre.
            Button {
                withAnimation(ONTMouvement.arrivee) { agrandie.toggle() }
            } label: {
                Image(
                    systemName: agrandie
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right"
                )
                .font(ONTUI.callout.weight(.semibold))
                .foregroundStyle(theme.accent)
                .padding(spacing.xs)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(agrandie ? "Réduire la fiche" : "Agrandir la fiche")
        }
    }

    @ViewBuilder private var contenu: some View {
        if let fiche, !fiche.definition.isEmpty {
            // **Le texte de la fiche est ici, pas derrière un bouton.**
            //
            // Le premier jet offrait « Ouvrir la fiche », qui soulevait une
            // seconde feuille par-dessus celle-ci. L'auteur : « je veux que le
            // texte soit directement dedans, même pour les intras ». La feuille
            // existe pour comprendre un mot sans quitter son verset, et un
            // second étage reconduisait ce qu'elle venait supprimer.
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: spacing.s) {
                    ForEach(Array(fiche.definition.enumerated()), id: \.offset) { _, bloc in
                        ProseDeLaFiche(bloc: bloc)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        } else if mot.fiche != nil {
            Text("Cette fiche n'a pas encore de définition.")
                .font(ONTUI.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            // **Le message plutôt que le vide**, arbitré par l'auteur : il dit
            // l'état du lexique au lieu de laisser croire à une panne.
            Text("Ce mot n'a pas encore de fiche ONT.")
                .font(ONTUI.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let strong = mot.strong {
                Text("Strong \(strong)")
                    .font(ONTUI.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Isole la séquence hébraïque de son voisinage — voir `hebrewRun`.
    private func isole(_ v: String) -> String { "\u{2068}\(v)\u{2069}" }
}

/// Un bloc de fiche, rendu sur place.
///
/// **Dette assumée.** `BlocDeFiche` fait déjà ce travail, en mieux — mais il
/// vit dans `LexiconFeature`, et `ReadingFeature` ne dépend d'aucune autre
/// feature : c'est une contrainte écrite dans `Package.swift`, et elle est
/// juste. La branche des chuqqot l'a déplacé dans `ONTDesignSystem`, où il
/// aurait dû être ; ce rendu-ci disparaît le jour où ce déplacement atteint
/// cette branche.
private struct ProseDeLaFiche: View {
    @Environment(\.ontTheme) private var theme
    let bloc: Block

    var body: some View {
        switch bloc {
        case .paragraph(let nodes), .quote(let nodes):
            Text(ONTTextRenderer.compose(nodes, theme: theme))
                .font(ONTUI.body)
                .lineSpacing(theme.lineSpacing)
                .fixedSize(horizontal: false, vertical: true)
        case .heading(_, let nodes):
            Text(ONTTextRenderer.compose(nodes, theme: theme))
                .font(ONTUI.headline)
                .fixedSize(horizontal: false, vertical: true)
        case .list(_, let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("·").foregroundStyle(.secondary)
                        Text(ONTTextRenderer.compose(item, theme: theme))
                            .font(ONTUI.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        // Les tableaux et les filets n'ont pas de place dans une carte de cette
        // largeur. Les taire est exact : ils ne portent jamais le sens d'un
        // mot, et les écraser serait pire que les omettre.
        default:
            EmptyView()
        }
    }
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
                VStack(spacing: 1) {
                    Text("\u{2068}\(m.forme)\u{2069}")
                        .font(theme.type.hebrew.font)
                    // **La translittération sous le mot**, demandée par
                    // l'auteur. Plus petite et plus pâle : elle aide à
                    // prononcer, elle ne concurrence pas le texte.
                    //
                    // Rien quand on ne sait pas — pas un tiret, pas une
                    // parenthèse vide. Une ligne absente se lit comme une
                    // absence ; un signe de remplacement se lit comme une
                    // donnée.
                    if let t = m.translitteration {
                        Text(t)
                            .font(ONTUI.caption)
                            .opacity(0.75)
                    }
                }
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
