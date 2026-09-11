import ONTDesignSystem
import ONTKit
import SwiftUI

/// L'onglet **Chuqqot** — חֻקּוֹת, ce qui est *gravé* et qui demeure.
///
/// ## Le nom, et pourquoi ce n'est pas « Khuqqim »
///
/// Les deux pluriels existent et ne disent pas la même chose. חֹק → חֻקִּים,
/// masculin, tire vers la **prescription** — ce qu'on ordonne de faire. חֻקָּה
/// → חֻקּוֹת, féminin, tire vers la **disposition permanente** — ce qui est
/// établi et tient.
///
/// Ce que cet onglet porte n'oblige personne à agir : ce sont des régularités
/// reconnues, énoncées comme des **nécessités** — « on ne peut pas inventer un
/// engin si l'on est soi-même dans l'engin ». La racine ח-ק-ק dit *graver,
/// inciser, tailler dans* : un chuq tient parce qu'il ne peut pas ne pas tenir.
///
/// Et la formule qui tranche : **חֻקַּת עוֹלָם**, *chuqqat ʿolam*, « statut
/// perpétuel ». Tout le vocabulaire du corpus repose sur `ʿolam` — la durée
/// indéterminée, le mode d'être dans le temps. C'est de cette famille-là.
///
/// ## Et l'initiale : `ch`, jamais `kh`
///
/// Le §2.9 du vault fixe que **ח** (*het*) se rend `ch`, et que `kh` est
/// réservé à **כ** (*khaf*). חֻקָּה commence par un het. Le `kh` de la première
/// écriture venait de l'habitude française — la même divergence que
/// `Khanokh → Chanokh`, corrigée le 29 août.
///
/// Le mot qui le démontre est *chokhmah* : un het au début, un khaf au milieu.
/// Tout écrire en `kh` donnerait `khokhmah`, **deux `kh` pour deux lettres
/// différentes** — et rien ne dirait que l'information a été effacée.
///
/// **Ne « corriger » ni en masculin, ni en `kh`.** Les deux écarts sont
/// délibérés : le féminin arbitré le 7 septembre 2026, l'initiale le 8.
///
/// ## Ce que l'onglet est devenu, le 11 septembre 2026
///
/// Il a été un squelette — la place dans la barre, la pile de navigation, le
/// grand titre, et un état vide qui disait « Ils ne sont pas encore écrits ».
/// C'était vrai le jour où il a été écrit ; ça ne l'était plus depuis que sept
/// chuqqot vivent dans le vault et que le pipeline émet `chuqqot.json`.
///
/// **Le défaut n'était pas l'écran vide, c'était l'écran qui mentait.** Un état
/// vide est un état légitime ; un état vide qui se trompe de raison envoie le
/// lecteur chercher ailleurs ce qui l'attend ici. Le contrôle des émissions l'a
/// nommé le jour même, et c'est sa première trouvaille.
///
/// ## Une pile, et non une feuille
///
/// Une chuqqah est un texte **long, dense, qui se lit d'un bout à l'autre** —
/// pas une fiche qu'on consulte. C'est ce qui décide de sa présentation : on la
/// pousse dans la pile de navigation, plein écran, avec un retour nommé.
///
/// Une feuille aurait été le geste d'imitation — c'est ce que fait le Lexique.
/// Elle aurait été un contresens : une feuille s'ouvre par-dessus ce qu'on
/// faisait et se referme d'un glissement du pouce, ce qui est exactement ce
/// qu'on veut d'une définition et exactement ce qu'on ne veut pas d'une lecture
/// de dix minutes. En prime, l'onglet ne présente aucune feuille — donc rien à
/// habiller, et rien que `eprouver-les-feuilles.sh` ait à dire.
public struct ChuqqotTab: View {
    @Environment(ChuqqotModel.self) private var model

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if model.chuqqot.isEmpty {
                    EnAttenteDeValidation()
                } else {
                    ListeDesChuqqot(chuqqot: model.chuqqot)
                }
            }
            .ontScreen()
            .navigationTitle("Chuqqot")
            .ontTitreCompact()
            // **La destination est déclarée ici, une fois.**
            //
            // La poser sur la rangée la redéclarerait à chaque ligne : SwiftUI
            // n'en retient qu'une par type et par pile, et le doublon se paie
            // en reconstructions sans rien changer à l'écran. C'est aussi ce
            // qui permettra à un futur `router.aller(a:)` de pousser une
            // chuqqah nommée sans que la liste ait eu à être montée.
            .navigationDestination(for: Chuqqah.self) { chuqqah in
                PageDeChuqqah(chuqqah: chuqqah)
            }
        }
    }
}

/// L'index — les chuqqot dans l'ordre de lecture.
///
/// ## `ontListeDeProse` et non `ontListeDIndex`
///
/// Les deux noms disent une intention, et il fallait choisir. Un index se
/// *parcourt* — le Lexique et ses trois cent trente-quatre entrées, avec un
/// rail de lettres collé au bord droit, où la gouttière de lecture serait un
/// contresens : elle décollerait le rail de l'endroit précis où le pouce va le
/// chercher.
///
/// Ici, il y a une poignée de titres, aucun rail, et ce qu'on lit est déjà de
/// la prose : le titre d'une chuqqah est une phrase, pas une étiquette — « Les
/// quatre modes de présence d'ʾAdonai dans l'ʿolam ». Une liste qui touche les
/// deux bords ferait à ces phrases ce que la feuille de prononciation
/// subissait encore le 8 septembre.
private struct ListeDesChuqqot: View {
    let chuqqot: [Chuqqah]

    var body: some View {
        List {
            Section {
                ForEach(Array(chuqqot.enumerated()), id: \.element.id) { rang, chuqqah in
                    // `NavigationLink(value:)` et non un `Button` qui pousse
                    // un état à lui : la pile porte alors la valeur elle-même,
                    // et le chevron du système arrive avec — un lecteur voit
                    // du premier coup d'œil que la ligne mène quelque part.
                    NavigationLink(value: chuqqah) {
                        RangeeDeChuqqah(chuqqah: chuqqah)
                            // Toute la rangée répond, pas seulement les
                            // lettres : un `HStack` ne définit aucune forme
                            // tactile, seul le dessin des glyphes est touché.
                            .contentShape(.rect)
                            // La carte du Mac — survol, pression, bord à bord.
                            // Inerte sur iOS.
                            .ontCarteDeLigne()
                    }
                    .ontLigneDeCarte()
                    .ontApparition(rang)
                }
            } header: {
                // **Le sous-titre est un en-tête de section, pas un `Text`
                // posé au-dessus de la liste.**
                //
                // Une `List` épingle ses en-têtes : celui-ci reste lisible
                // pendant qu'on descend, là où un bloc au-dessus disparaîtrait
                // au premier défilement. C'est le même montage que le bascule
                // du Lexique, et pour la même raison.
                Text("ce qui est gravé")
                    .font(ONTUI.footnote)
                    .foregroundStyle(.secondary)
                    // Sans quoi le système le passe en capitales, et la glose
                    // se lirait comme une rubrique de formulaire.
                    .textCase(nil)
            }
        }
        .ontListeDeProse()
    }
}

/// Une ligne de l'index.
///
/// Le titre seul. **Pas d'extrait du corps**, et c'est délibéré : les deux
/// premières lignes d'une chuqqah posent son cadre, elles ne la résument pas —
/// un extrait donnerait le sentiment d'avoir compris ce qu'on n'a pas lu, ce
/// qui est le contraire de ce qu'un énoncé permanent demande.
///
/// Et pas de numéro de rang non plus : `rang` sert à ordonner, pas à nommer.
/// L'afficher inviterait à citer « la chuqqah n° 3 », qui changerait de numéro
/// à la première insertion.
private struct RangeeDeChuqqah: View {
    @Environment(\.ontTheme) private var theme

    let chuqqah: Chuqqah

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(chuqqah.titre)
                .font(ONTUI.body)
                .foregroundStyle(theme.ink)
                // Le titre d'une chuqqah est une phrase entière, et il se
                // replie — d'autant plus au curseur de taille monté, que
                // Gloire tient haut. Sans ça, SwiftUI le tronque à une ligne
                // dans une rangée de liste, et la moitié du titre disparaît
                // sans que rien ne le dise.
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
    }
}

/// La page d'une chuqqah — le texte du vault, rendu comme du corpus.
///
/// ## Ce qu'elle ne fait pas
///
/// Elle ne **compose** rien. Le titre, les intertitres et les énoncés viennent
/// de `chuqqot/<nom>.md` dans le vault ; l'app les affiche et s'arrête là.
/// Écrire ici une mise en forme propre aux chuqqot en ferait une seconde
/// grammaire, qui divergerait du corpus à la première correction — c'est
/// l'argument que `chuqqot.rs` donne côté pipeline pour ne pas leur écrire un
/// analyseur à elles, et il vaut dans les deux sens.
///
/// Et parce que le texte arrive en blocs, ses intraduisibles sont en or et ses
/// Shemot en terre brûlée, **touchables**, sans une ligne de code de plus ici.
/// Un énoncé sur `ha-Maqom` a tout intérêt à ce que le mot ouvre sa fiche.
///
/// `titresPleins: true` : la page n'a pas d'en-tête de section au-dessus
/// d'elle, et le réglage de fiche rendrait ses `##` **plus petits que le
/// corps** — mesuré à l'écran sur la feuille de prononciation le 8 septembre.
private struct PageDeChuqqah: View {
    let chuqqah: Chuqqah

    var body: some View {
        List {
            Section {
                ForEach(Array(chuqqah.blocs.enumerated()), id: \.offset) { _, bloc in
                    BlocDeFiche(block: bloc, titresPleins: true)
                }
            }
            .ontRow()
        }
        .ontListeDeProse()
        .ontScreen()
        // Le titre dans la barre, et non un titre dessiné en tête du corps :
        // c'est lui que le bouton de retour reprend pour nommer d'où l'on
        // vient. Dessiné dans le corps, toutes les pages s'appelleraient
        // « Chuqqot ».
        .navigationTitle(chuqqah.titre)
        .ontTitreCompact()
    }
}

/// L'état vide — et il doit dire la **vérité**.
///
/// ## Le texte d'avant était faux, pas seulement vide
///
/// Il disait « Cet onglet portera les chuqqot. Ils ne sont pas encore écrits. »
/// Sept l'étaient, dans `brouillons/chuqqot/` du vault, et le pipeline en
/// produisait déjà le fichier. Un lecteur qui les avait vues passer ailleurs
/// n'avait aucune raison de revenir ici.
///
/// C'est l'état le plus fréquent de cet écran pour l'instant, et c'est
/// justement pour ça qu'il doit être juste : un écran qu'on ne voit jamais peut
/// se permettre d'être approximatif, celui-ci non.
///
/// ## Pourquoi il ne compte pas les chuqqot en attente
///
/// « Sept sont écrites » se périmerait à la première validation, et personne ne
/// penserait à venir corriger un état vide — c'est l'écran qu'on regarde le
/// moins. Le compte exact, lui, vit là où il se recalcule tout seul :
/// `dist/report.md`, que le pipeline réécrit à chaque construction.
///
/// ## Et pourquoi il reste un état vide plutôt qu'un aperçu des brouillons
///
/// La tentation était réelle : les textes existent, on pourrait les montrer
/// marqués « brouillon », comme le fait un chapitre de traduction en cours.
///
/// La décision de l'auteur, le 9 septembre 2026, dit l'inverse, et sa raison
/// tient en une phrase : **un énoncé permanent « en attente de validation » se
/// contredit lui-même.** Un chapitre qui s'améliore sous les yeux du lecteur
/// reste honnête ; une chuqqah, non. La garde vit dans le pipeline — l'app n'a
/// donc rien à filtrer, et surtout rien à contourner en allant chercher les
/// brouillons par un autre chemin.
private struct EnAttenteDeValidation: View {
    @Environment(\.ontTheme) private var theme
    private var spacing = ONTSpacing()

    var body: some View {
        VStack(alignment: .leading, spacing: spacing.s) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: ONTUI.points(28), weight: .light))
                .foregroundStyle(ONTColors.brandInk(theme.mode))
            Text("Rien à lire pour l'instant")
                .font(ONTUI.headline)
                .foregroundStyle(theme.ink)
            Text(
                "Les chuqqot sont écrites et attendent leur validation. "
                    + "Elles paraîtront ici une à une, dès qu'elles seront arrêtées."
            )
            .font(ONTUI.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Text(
                "Un énoncé permanent ne se publie pas « en attente » : "
                    + "il se contredirait lui-même."
            )
            .font(ONTUI.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, spacing.page)
        .padding(.top, spacing.xl)
        // L'état vide se range **en haut** de la page. Centré verticalement, il
        // se lirait comme une alerte au milieu d'un écran, alors qu'il décrit
        // une situation parfaitement normale.
        .frame(maxHeight: .infinity, alignment: .top)
        // Les trois textes se lisent d'un seul tenant à VoiceOver. Séparés, le
        // lecteur entend « Rien à lire pour l'instant » et balaie avant la
        // raison — c'est-à-dire avant la seule chose que cet écran a à dire.
        .accessibilityElement(children: .combine)
    }
}
