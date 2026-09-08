import ONTDesignSystem
import ONTKit
import SwiftUI

/// L'onglet **Chuqqot** — חֻקּוֹת, ce qui est *gravé* et qui demeure.
///
/// ## Le nom, et pourquoi ce n'est pas « Chuqqot »
///
/// Les deux pluriels existent et ne disent pas la même chose. חֹק → חֻקִּים,
/// masculin, tire vers la **prescription** — ce qu'on ordonne de faire. חֻקָּה
/// → חֻקּוֹת, féminin, tire vers la **disposition permanente** — ce qui est
/// établi et tient.
///
/// Ce que cet onglet portera n'oblige personne à agir : ce sont des
/// régularités reconnues, énoncées comme des **nécessités** — « on ne peut pas
/// inventer un engin si l'on est soi-même dans l'engin ». La racine ח-ק-ק dit
/// *graver, inciser, tailler dans* : un khoq tient parce qu'il ne peut pas ne
/// pas tenir.
///
/// Et la formule qui tranche : **חֻקַּת עוֹלָם**, *khuqqat olam*, « statut
/// perpétuel ». Tout le vocabulaire du corpus repose sur `olam` — la durée
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
/// ## Où il en est
///
/// C'est un squelette : la place dans la barre, la pile de navigation, le
/// grand titre. **Aucun contenu, et l'écran le dit.** Ce qu'est une entrée,
/// d'où elle vient et ce qu'on en lit ne sont pas encore arrêtés — les poser
/// en devinant reviendrait à figer une forme avant de savoir ce qu'elle porte.
///
/// ## Pourquoi un état vide qui s'annonce, plutôt qu'un écran blanc
///
/// Un écran vide sans un mot se lit comme une panne. Celui-ci dit ce qu'il
/// attend, ce qui est vrai — et il disparaîtra dès que la première entrée
/// arrivera.
public struct ChuqqotTab: View {
    @Environment(\.ontTheme) private var theme
    private var spacing = ONTSpacing()

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: spacing.m) {
                    Text("Chuqqot")
                        .font(.custom(ONTFonts.display, size: ONTUI.points(30)))
                        .foregroundStyle(theme.ink)
                    Text("ce qui est gravé")
                        .font(ONTUI.subheadline)
                        .foregroundStyle(.secondary)

                    EnAttenteDeContenu()
                        .padding(.top, spacing.xl)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, spacing.page)
                .padding(.top, spacing.l)
            }
            .ontScreen()
            .navigationTitle("Chuqqot")
            .ontTitreCompact()
        }
    }
}

/// L'état vide, tant qu'aucun khuq n'est écrit.
///
/// Il nomme ce qui manque au lieu de le masquer. Un état vide muet fait croire
/// à un défaut de chargement, et le lecteur relance l'app pour rien.
private struct EnAttenteDeContenu: View {
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
            Text("Cet onglet portera les chuqqot. Ils ne sont pas encore écrits.")
                .font(ONTUI.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
