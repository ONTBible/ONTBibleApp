import ONTKit
import SwiftUI

/// Un bloc de prose du corpus, quel qu'il soit.
///
/// **Partagé par tout ce qui rend de la prose ONT** — la feuille d'un
/// intraduisible, celle d'un Shem, la feuille de prononciation, et depuis le
/// 11 septembre 2026 la page d'une chuqqah. Ces écrans diffèrent par ce qu'ils
/// annoncent autour ; le corps, lui, se rend de la même façon, et le dédoubler
/// ferait diverger les rendus au premier bloc ajouté au domaine.
///
/// ## Pourquoi il a quitté `LexiconFeature`
///
/// Il y était `internal`, donc invisible depuis `ChuqqotFeature`. Trois issues,
/// et deux coûtaient trop cher :
///
/// - **le republier tel quel dans l'onglet Chuqqot** : deux rendus du même
///   texte, qui divergent à la première correction de typographie. C'est
///   exactement ce que le commentaire ci-dessus condamnait déjà entre les deux
///   feuilles du Lexique ;
/// - **faire dépendre `ChuqqotFeature` de `LexiconFeature`** : le `Package.swift`
///   dit pourquoi l'onglet n'a aucune dépendance de feature — « un onglet qui ne
///   sait rien des autres reste un onglet qu'on peut déplacer, replier ou
///   retirer sans les toucher ». Une chuqqah n'a rien à voir avec le lexique ;
/// - **le poser dans `ONTDesignSystem`**, retenu. Le paquet dépend déjà d'ONTKit
///   pour la raison exacte que son propre commentaire donne — « traduire les
///   trois niveaux du texte en typographie est une décision de présentation,
///   pas de domaine ». Un bloc n'est rien d'autre que ça, un cran au-dessus de
///   `ONTTextRenderer`, dont il est désormais voisin de fichier.
///
/// Le déplacement ne change aucun pixel : c'est le même corps, rendu public.
///
/// **La fiche ne rendait que ses paragraphes**, et tout le reste tombait sans
/// rien dire — exactement comme le pipeline jetait les titres avant de les
/// émettre. Deux silences en série : celui qui écrivait la fiche ne pouvait pas
/// savoir lequel des deux l'avait mangée.
///
/// Une fiche porte maintenant trois mouvements — la racine dans les six
/// ruachim, le porteur, les renvois — et sans leurs titres ils arrivent collés
/// en un seul flot.
public struct BlocDeFiche: View {
    @Environment(\.ontTheme) private var theme
    public let block: Block

    /// **Vrai quand le bloc vit dans une feuille pleine et non dans une fiche.**
    ///
    /// Les tailles de titre ci-dessous ont été choisies pour une fiche posée
    /// *dans* une section de formulaire : elles se resserrent pour ne pas
    /// rivaliser avec l'en-tête qui les contient. Dans une feuille qui n'a pas
    /// d'en-tête au-dessus d'elle, le même réglage rend un titre **plus petit
    /// que le corps** — mesuré à l'écran sur la feuille de prononciation, où
    /// « Le cas qui a fait écrire cette feuille » se lisait comme un paragraphe.
    ///
    /// Un drapeau plutôt qu'une seconde vue : les deux rendus partagent tout le
    /// reste, et les dédoubler les ferait diverger à la première correction.
    public var titresPleins = false

    /// **Un init explicite, et non celui que le compilateur donne.**
    ///
    /// L'init par membres d'une `struct` est `internal` : hors du paquet, il
    /// n'existe pas. Depuis que cette vue a deux consommateurs dans deux
    /// bibliothèques — le Lexique et les Chuqqot —, l'omettre rendrait le type
    /// public et inconstructible, ce que le compilateur ne signale qu'au point
    /// d'appel.
    ///
    /// `titresPleins` garde son défaut ici : la fiche est le cas fréquent, la
    /// pleine page l'exception qui se déclare.
    public init(block: Block, titresPleins: Bool = false) {
        self.block = block
        self.titresPleins = titresPleins
    }

    public var body: some View {
        switch block {
        case .paragraph(let nodes):
            Text(ONTTextRenderer.compose(nodes, theme: theme))
                .lineSpacing(4)

        case .heading(let level, let nodes):
            // **Les niveaux se resserrent au lieu de se suivre.** Un `##` de
            // fiche est déjà sous un en-tête de section du formulaire ; lui
            // donner une taille de titre le ferait rivaliser avec « Ce qu'il
            // signifie », qui le contient. Deux tailles suffisent, et la
            // seconde n'est qu'une nuance.
            Text(ONTTextRenderer.compose(nodes, theme: theme))
                .font(
                    titresPleins
                        ? (level <= 2 ? ONTUI.title3.weight(.semibold) : ONTUI.headline)
                        : (level <= 2
                            ? .subheadline.weight(.semibold) : .footnote.weight(.semibold))
                )
                .foregroundStyle(theme.accent)
                .padding(.top, titresPleins ? 14 : 6)
                // Un titre est un en-tête pour VoiceOver, sans quoi il se lit
                // comme une phrase de plus dans le flot.
                .accessibilityAddTraits(.isHeader)

        case .list(_, let items):
            // Le « Voir aussi » est une liste, et c'est le bloc qui devenait le
            // plus illisible collé à la prose.
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("·").foregroundStyle(theme.accent)
                            .font(ONTUI.ligneDeListe)
                        Text(ONTTextRenderer.compose(item, theme: theme))
                    }
                }
            }

        case .quote(let nodes):
            Text(ONTTextRenderer.compose(nodes, theme: theme))
                .italic()
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Capsule().fill(theme.accent.opacity(0.4)).frame(width: 2)
                }

        case .rule:
            Divider()

        // **Ni versets ni tableaux, et c'est une limite qu'il faut dire.**
        //
        // Les nommer plutôt que les laisser à un `default` fait que l'ajout
        // d'un cas au domaine casse ici — c'est le seul endroit qui le dirait.
        //
        // Un verset ne peut pas arriver : la prose de fiche n'en porte pas, et
        // la liseuse a sa propre vue pour ça. Un **tableau**, en revanche, est
        // écrit dans les sept chuqqot du vault. Il ne parvient pas jusqu'ici
        // aujourd'hui — `blocs_de_prose`, côté pipeline, ne rend que `Para` et
        // `Heading`, si bien qu'une table de markdown arrive sous forme de
        // paragraphe à barres verticales. Le trou est donc en amont, et le
        // combler ici le masquerait au lieu de le fermer.
        case .verses, .table:
            EmptyView()
        }
    }
}
