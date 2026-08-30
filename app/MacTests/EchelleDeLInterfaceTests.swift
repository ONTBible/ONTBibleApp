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

    @Test("Un texte dans un Form aussi — c'est la feuille de ⌘,")
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
    }
}
