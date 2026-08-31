import ONTDesignSystem
import SwiftUI

/// Rend aux lignes de liste la fonte d'interface, que macOS leur reprend.
///
/// ## Ce qui a été mesuré
///
/// L'auteur a signalé que l'écran « Vous » ne suivait pas ⌘= alors que la barre
/// latérale, elle, suivait. La barre suivait parce qu'elle **déclare** ses
/// fontes — `ONTUI.points(14)` ; « Vous » s'en remet à l'environnement que pose
/// `AvecLaFonteDeLInterface`.
///
/// Sondes posées dans la vraie fenêtre, hauteurs relevées au pixel sur une
/// capture, facteur forcé à 1,5 — 32 px valent 13 pt, 48 px valent 19,5 pt,
/// c'est-à-dire 13 × 1,5 :
///
///     Text nu, hors d'une List                       48 px   suit
///     Text nu, dans une List                         32 px   ne suit pas
///     Text .font(ONTUI.body), dans une List          48 px   suit
///     .font(ONTUI.body) posé sur la List             32 px   ne suit pas
///     .environment(\.font, …) posé sur la List       32 px   ne suit pas
///     .font(ONTUI.body) posé sur une Section         32 px   ne suit pas
///     Label .font(ONTUI.body), dans une List         32 px   ne suit pas
///     Label sous ce style-ci, dans une List          48 px   suit
///
/// Trois choses en sortent, et aucune n'était devinable :
///
/// 1. **une `List` de macOS ne transmet pas `\.font` à ses lignes.** Elle leur
///    pose la fonte système de son style. L'environnement n'est pas perdu — la
///    même vue posée à côté de la liste grossit — il est **écrasé au passage** ;
/// 2. **rien posé au-dessus ne franchit la barrière** : ni sur la `List`, ni sur
///    une `Section`. Il faut que la fonte soit déclarée *dans* la ligne ;
/// 3. **et pour un `Label`, `.font()` sur la ligne ne suffit pas non plus.**
///    C'est son *style* qui compose son titre, et il reprend la fonte du
///    système. Seul un style de libellé atteint le titre.
///
/// D'où ces deux styles plutôt qu'une retouche ligne à ligne : posés une fois
/// sur le détail, ils atteignent les dix-sept lignes de « Vous » sans qu'aucune
/// n'ait à savoir qu'elle est sur un Mac.
///
/// ## Pourquoi ça ne casse rien sur iOS
///
/// Ce fichier est propre à `MacSources`. Et même s'il ne l'était pas, `ONTUI.body`
/// **rend la fonte sémantique sur iOS** — voir `ONTUI` — où c'est Dynamic Type
/// qui commande. Le remède n'a de contenu que là où le mal existe.
struct FonteDeLibelle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label {
            configuration.title.font(ONTUI.body)
        } icon: {
            configuration.icon
        }
    }
}

/// Le même service pour `LabeledContent` — « Versets » et son « 864 ».
///
/// Les deux moitiés portent la fonte : la valeur est aussi éloignée du corps
/// que l'intitulé, et n'en suivrait pas moins l'échelle.
struct FonteDeContenuLibelle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        LabeledContent {
            configuration.content.font(ONTUI.body)
        } label: {
            configuration.label.font(ONTUI.body)
        }
    }
}

extension View {
    /// Pose les deux styles d'un coup, là où des listes vivent.
    func fonteDesListes() -> some View {
        labelStyle(FonteDeLibelle())
            .labeledContentStyle(FonteDeContenuLibelle())
    }
}
