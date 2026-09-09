import ONTDesignSystem
import ONTKit
import SwiftUI

/// **Le bloc qui ouvre la feuille de prononciation**, en tête du Lexique.
///
/// ## Ce qu'il répare
///
/// Le corpus écrit `chokhmah`, `malʾakh`, `Chanokh` — et rien dans la graphie
/// n'avertit le lecteur quand il se trompe. L'auteur lui-même prononçait
/// *Chanokh* « cha-no-q » : les deux consonnes fausses, et aucun signe pour le
/// lui dire. Une translittération sans diacritiques est faite pour **remonter à
/// la lettre**, jamais pour guider la bouche.
///
/// ## Pourquoi un bloc et non une ligne de plus
///
/// Le Lexique est une liste de trois cent trente-quatre entrées. Une ligne de
/// plus s'y noierait, et personne ne la toucherait jamais — alors que c'est ce
/// qu'il faut lire **avant** la première fiche.
///
/// Le rapport de un à trois vient de Gloire, et il est juste : au carré, le
/// bloc pèse comme une carte de contenu et concurrence la liste ; à un tiers de
/// sa largeur, il se lit comme un en-tête et laisse la liste commencer.
///
/// ## L'or, et pas le fond des cartes
///
/// Il porte l'aplat de marque des boutons de connexion — `brandInk` avec
/// `onBrandAccent` dessus. C'est le seul autre endroit de l'app où la marque
/// s'affirme en aplat, et c'est voulu : les deux disent « ceci n'est pas du
/// corpus, c'est l'app qui te parle ».
struct HeroDePrononciation: View {
    @Environment(\.ontTheme) private var theme
    private var spacing = ONTSpacing()

    let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: spacing.m) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Comment ça se prononce")
                        // **Une fonte sémantique, pas la fonte de titre.**
                        //
                        // La fonte d'affichage porte un interligne large, fait
                        // pour un titre d'écran qui tient sur une ligne. Dès
                        // que ce libellé passe à deux lignes — et il y passe
                        // au premier cran d'accessibilité — le blanc entre les
                        // deux fait le double de celui du sous-titre, et le
                        // pavé se lit comme deux fragments au lieu d'un titre.
                        //
                        // **Mesuré, et une hypothèse écartée en chemin** :
                        // `relativeTo: .headline` ne change rien. La courbe
                        // d'échelle n'était pas en cause, l'interligne l'était.
                        //
                        // C'est ce que fait déjà le pavé « Reprendre » de
                        // l'onglet Bible — `ONTUI.subheadline` — et c'est
                        // précisément celui qui tient à toutes les tailles.
                        // La chrome emploie les fontes du système ; la fonte
                        // de la marque reste au texte et aux titres d'écran,
                        // qui ne se replient pas.
                        .font(ONTUI.headline)
                    Text("Les cinq sons que le français n'a pas")
                        .font(ONTUI.footnote)
                        .opacity(0.85)
                }
                .foregroundStyle(ONTColors.onBrandAccent(theme.mode))
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "waveform")
                    .font(.system(size: ONTUI.points(22), weight: .light))
                    .foregroundStyle(ONTColors.onBrandAccent(theme.mode))
            }
            .padding(.horizontal, spacing.l)
            // **Le rapport de un à trois, tenu par la hauteur et non par un
            // `aspectRatio`.** Ce dernier imposerait sa forme au texte, qui
            // grandit avec le curseur de taille : le bloc se déformerait chez
            // qui en a le plus besoin. Une hauteur minimale laisse le contenu
            // décider quand il faut plus.
            .frame(minHeight: ONTUI.points(76))
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(ONTColors.brandInk(theme.mode))
            )
            .ontSurvol(dans: RoundedRectangle(cornerRadius: 16, style: .continuous), souleve: true)
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.ontPresse)
        .accessibilityLabel("Comment se prononce ce qui est écrit")
        .accessibilityHint("Ouvre la feuille de prononciation")
    }
}

/// La feuille elle-même — le texte du vault, rendu comme du corpus.
///
/// ## Ce qu'elle ne fait pas
///
/// Elle ne **compose** rien. Le titre, les sections et les exemples viennent de
/// `lexique/prononciation.md` ; l'app les affiche et s'arrête là. Écrire ici
/// une explication de la prononciation en ferait une seconde source, qui
/// divergerait du vault à la première correction.
///
/// Et parce que le texte arrive en blocs, ses intraduisibles sont en or et ses
/// Shemot en terre brûlée, **touchables**, sans une ligne de code de plus. Une
/// feuille qui explique comment dire `chokhmah` a tout intérêt à ce que le mot
/// ouvre sa fiche.
struct FeuilleDePrononciationView: View {
    @Environment(\.ontTheme) private var theme
    private var spacing = ONTSpacing()

    let feuille: FeuilleDePrononciation?

    init(feuille: FeuilleDePrononciation?) {
        self.feuille = feuille
    }

    var body: some View {
        Group {
            if let feuille {
                List {
                    Section {
                        ForEach(Array(feuille.blocs.enumerated()), id: \.offset) { _, bloc in
                            BlocDeFiche(block: bloc, titresPleins: true)
                        }
                    }
                    .ontRow()
                }
                .ontListeDeProse()
            } else {
                // **L'attente se dit.** Un écran vide et muet se lit comme une
                // panne, et le lecteur relance l'app pour rien.
                VStack(alignment: .leading, spacing: spacing.s) {
                    Text("Pas encore écrite")
                        .font(ONTUI.headline)
                        .foregroundStyle(theme.ink)
                    Text("Cette feuille expliquera comment se prononce ce qui est écrit.")
                        .font(ONTUI.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(spacing.page)
            }
        }
        .ontScreen()
    }
}
