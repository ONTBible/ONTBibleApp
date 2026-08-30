import ONTDesignSystem
import SwiftUI
import Testing

@testable import ONTMac

/// **⌘= agit-il seulement ?**
///
/// L'auteur l'a signalé trois fois : « le resize de l'UI ne marche toujours
/// pas ». J'ai cherché deux fois au mauvais endroit — un défaut de câblage du
/// menu, puis la barre latérale d'AppKit. Les deux étaient de vrais défauts,
/// aucun n'était *le* défaut.
///
/// Le troisième relevé a tranché : `dynamicTypeSize`, sur quoi tout reposait,
/// **ne fait rien sur macOS**. Ces épreuves gardent les deux moitiés de ce
/// constat — que l'ancien levier est mort, et que le nouveau tire vraiment.
@MainActor
struct EchelleDeLInterfaceTests {
    /// Rend un texte et rend sa hauteur en points.
    ///
    /// `ImageRenderer` plutôt qu'une capture d'écran : pas de fenêtre, donc
    /// mesurable en intégration continue — et surtout, une mesure qui ne dépend
    /// pas de ce qui est au premier plan.
    private func hauteur(_ vue: some View) -> CGFloat {
        ImageRenderer(content: vue).nsImage?.size.height ?? 0
    }

    @Test("dynamicTypeSize reste sans effet sur macOS")
    func leLevierMort() {
        let petite = hauteur(Text("Toledot").font(.body).dynamicTypeSize(.xSmall))
        let grande = hauteur(Text("Toledot").font(.body).dynamicTypeSize(.xxxLarge))
        #expect(petite > 0)
        #expect(
            petite == grande,
            """
            macOS honore maintenant dynamicTypeSize (\(petite) → \(grande)). \
            L'échelle maison de ONTUI n'est peut-être plus nécessaire — \
            à reconsidérer plutôt qu'à empiler.
            """)
    }

    @Test("Le facteur d'interface grossit vraiment les fontes")
    func leLevierVivant() {
        let depart = ONTEchelleUI.partage.facteur
        defer { ONTEchelleUI.partage.facteur = depart }

        ONTEchelleUI.partage.facteur = TaillesAuClavier.interface.first!
        let petite = hauteur(Text("Toledot").font(ONTUI.body))
        ONTEchelleUI.partage.facteur = TaillesAuClavier.interface.last!
        let grande = hauteur(Text("Toledot").font(ONTUI.body))

        #expect(petite > 0)
        #expect(grande > petite, "Le facteur ne change rien : \(petite) → \(grande)")
    }

    @Test("Les écarts suivent le texte")
    func lesEcartsSuivent() {
        let depart = ONTEchelleUI.partage.facteur
        defer { ONTEchelleUI.partage.facteur = depart }

        // Un texte qui grandit dans des marges figées se serre contre elles :
        // les deux doivent bouger ensemble, ou l'interface se défait.
        ONTEchelleUI.partage.facteur = 1
        let serré = ONTUI.points(16)
        ONTEchelleUI.partage.facteur = 1.5
        let large = ONTUI.points(16)
        #expect(large > serré)
    }

    @Test("Un cran hors bornes ne fait pas tomber l'app")
    func lesBornes() {
        // Un réglage relu d'une session précédente peut désigner un cran qui
        // n'existe plus. Le lire hors bornes ferait tomber l'app à l'ouverture,
        // c'est-à-dire sans qu'on puisse le reproduire.
        #expect(TaillesAuClavier.facteur(-5) == TaillesAuClavier.interface.first)
        #expect(TaillesAuClavier.facteur(99) == TaillesAuClavier.interface.last)
    }
}

/// **Le texte qui n'écrit aucune fonte suit-il le facteur ?**
///
/// L'écran « Vous » ne déclare pas une seule fonte — ses dix-huit `Text`
/// prennent celle de l'environnement. C'est exactement le cas que l'auteur
/// signale trois fois : « l'UI bouge mais pas le texte ». On le mesure ici
/// plutôt que de le supposer une quatrième fois.
@MainActor
struct FonteDeLInterfaceTests {
    private func hauteur(_ vue: some View) -> CGFloat {
        ImageRenderer(content: vue.frame(width: 320)).nsImage?.size.height ?? 0
    }

    @Test("Un texte sans fonte déclarée suit le facteur")
    func leTexteNu() {
        let depart = ONTEchelleUI.partage.facteur
        defer { ONTEchelleUI.partage.facteur = depart }

        ONTEchelleUI.partage.facteur = 1
        let petit = hauteur(AvecLaFonteDeLInterface { Text("Continuer avec Apple") })
        ONTEchelleUI.partage.facteur = 1.5
        let grand = hauteur(AvecLaFonteDeLInterface { Text("Continuer avec Apple") })

        #expect(petit > 0)
        #expect(grand > petit, "le texte nu ne suit pas : \(petit) → \(grand)")
    }

    /// **Un `Form`, et rien d'autre. Surtout pas une `List`.**
    ///
    /// Cette épreuve s'appelait « un texte dans un Form aussi — c'est la
    /// feuille de ⌘, ». La seconde moitié était fausse, et c'est la moitié qui
    /// rassurait : l'écran « Vous » n'emploie pas de `Form`, il emploie une
    /// `List`. L'épreuve mesurait donc quelque chose qui passe pour établir
    /// quelque chose qui échoue.
    ///
    /// Ce qu'une mesure dans la vraie fenêtre a montré, facteur forcé à 1,5 —
    /// 32 px valent 13 pt, 48 px valent 19,5, soit 13 × 1,5 :
    ///
    ///     Text nu, hors d'une List                 48 px   suit
    ///     Text nu, dans une List                   32 px   ne suit pas
    ///     .font(ONTUI.body) sur la ligne           48 px   suit
    ///     .font(ONTUI.body) posé sur la List       32 px   ne suit pas
    ///     .environment(\.font, …) sur la List      32 px   ne suit pas
    ///     .font(ONTUI.body) posé sur une Section   32 px   ne suit pas
    ///     Label .font(…) dans une List             32 px   ne suit pas
    ///     Label sous un LabelStyle                 48 px   suit
    ///
    /// **Une `List` de macOS ne transmet pas `\.font` à ses lignes** : elle leur
    /// pose la fonte système de son style. L'environnement n'est pas perdu — la
    /// même vue posée à côté de la liste grossit — il est **écrasé au passage**,
    /// et rien de ce qu'on met au-dessus ne franchit la barrière. Pour un
    /// `Label`, même `.font()` sur la ligne ne suffit pas : c'est son *style*
    /// qui compose son titre.
    ///
    /// La ligne de la `Section` est celle qu'on aurait tentée en second, après
    /// la liste : elle ne passe pas non plus. Il n'y a **aucun rang
    /// intermédiaire** où poser la fonte — ou bien la ligne la déclare, ou bien
    /// un style l'atteint.
    ///
    /// Le nom dit donc maintenant ce que l'épreuve tient, et pas ce qu'on
    /// espérait qu'elle établisse.
    ///
    /// ## Pourquoi la `List` n'est pas éprouvée ici
    ///
    /// `ImageRenderer` rend **0 × 0** pour une `List`, qui n'a pas de taille
    /// propre ; `NSHostingView.fittingSize` aussi. Une épreuve écrite ainsi
    /// échouerait sur « 0,0 → 0,0 », ce qui ne dit rien du sujet. Il faut
    /// mesurer sur une capture de la vraie fenêtre, et ça ne se fait pas sans
    /// écran.
    ///
    /// Ce qui garde la `List`, c'est donc le style posé dans `FonteDesListes` et
    /// l'œil. On l'écrit plutôt que de laisser croire qu'une épreuve le couvre.
    @Test("Un texte dans un Form suit le facteur — et un Form n'est pas une List")
    func leTexteDansUnFormulaire() {
        let depart = ONTEchelleUI.partage.facteur
        defer { ONTEchelleUI.partage.facteur = depart }

        ONTEchelleUI.partage.facteur = 1
        let petit = hauteur(
            AvecLaFonteDeLInterface {
                Form { Label("Continuer avec Apple", systemImage: "apple.logo") }
            })
        ONTEchelleUI.partage.facteur = 1.5
        let grand = hauteur(
            AvecLaFonteDeLInterface {
                Form { Label("Continuer avec Apple", systemImage: "apple.logo") }
            })

        #expect(petit > 0)
        #expect(grand > petit, "le texte du formulaire ne suit pas : \(petit) → \(grand)")

        // Rappel de ce que cette épreuve **ne** dit pas : la `List` de
        // « Vous » n'obéit pas au même contrat, et rien ici ne la couvre.
    }
}
