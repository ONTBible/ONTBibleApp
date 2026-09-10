import ONTDesignSystem
import ONTKit
import SwiftUI
import Testing
import UIKit

@testable import LexiconFeature

/// Ce que les écrans deviennent quand on change la largeur — et la taille du texte.
///
/// ## Pourquoi ce fichier existe
///
/// Deux défauts ont été trouvés le 8 septembre 2026, tous deux invisibles à la
/// largeur par défaut, tous deux trouvés parce que **Gloire les a vus sur son
/// iPhone** :
///
/// - le pavé de prononciation du Lexique n'avait aucune marge verticale. Un
///   `.frame(minHeight: 76)` en tenait lieu : tant que le contenu mesurait
///   moins de 76 points, le cadre le centrait et l'espace au-dessus
///   *ressemblait* à une marge. Au premier cran d'accessibilité, le contenu
///   dépassait 76, le cadre l'épousait exactement, et « n'a pas » se retrouvait
///   collé au bord ;
/// - le sélecteur du Lexique tombait à des initiales illisibles — « V », « T »,
///   « S » — au même cran.
///
/// Les deux tenaient **par accident** : une condition tenait, rien ne disait
/// laquelle, et personne ne l'avait écrite. Regarder l'écran est la seule chose
/// qui les a montrés, et regarder l'écran ne passe pas à l'échelle : il y a
/// quatre onglets, une trentaine de composants, cinq largeurs qui comptent et
/// une douzaine de crans de Dynamic Type.
///
/// Et l'iPhone Duo arrive. Ses dimensions ne sont pas publiées ; l'exigence
/// l'est — « dynamically resize and adjust its layouts ». Le jour où elles le
/// seront, il suffira d'ajouter une ligne à `Self.largeurs`.
///
/// ## Ce que l'épreuve mesure — trois choses, toutes géométriques
///
/// Chaque sujet est **rendu hors écran** par `ImageRenderer`, à une largeur
/// *proposée* et à un cran de Dynamic Type donnés, puis lu au pixel :
///
/// 1. **Le débordement.** `proposedSize` propose une largeur sans l'imposer :
///    la vue rend à la taille qu'elle *veut*. Si l'image sort plus large que ce
///    qu'on lui a proposé, c'est qu'un morceau refuse de se réduire — une
///    largeur fixe, une rangée incompressible. Sur un vrai écran, ce morceau
///    sortirait par le côté. C'est une preuve dure, pas un indice.
/// 2. **La marge au bord.** On cherche, en partant de chaque bord vers
///    l'intérieur, la première ligne de pixels qui porte un **pas brusque** —
///    une variation franche d'un pixel au suivant *le long* du bord. Un fond
///    uni n'en produit aucun ; un dégradé non plus, il varie doucement ; un
///    glyphe ou une icône, si. La distance entre le bord et ce premier pas est
///    la marge réelle du contenu. C'est exactement le défaut du pavé de
///    prononciation, mesuré au lieu d'être vu.
/// 3. **La croissance.** À largeur constante, la hauteur au plus grand cran
///    doit dépasser la hauteur au cran par défaut. Une vue qui porte du texte
///    et qui ne grandit pas est une vue qui rogne son texte quelque part.
///
/// ## Ce qu'elle ne mesure pas — à lire avant de s'y fier
///
/// - **La troncature en tant que telle.** Un « Vocabulai… » tient
///   dimensionnellement : rien ne déborde, rien ne touche le bord. Seule la
///   mesure 3 l'attrape, et seulement quand la troncature empêche la vue de
///   grandir du tout. Le défaut des initiales « V », « T », « S » ne serait
///   donc **pas** trouvé ici — il l'a été à l'œil, et son correctif
///   (`ViewThatFits` dans `ONTSegments`) reste gardé par l'œil.
/// - **Les écrans complets, et tout ce qui s'adosse à UIKit.** `ImageRenderer`
///   ne les rend pas : une `List`, un `ScrollView` de plusieurs pages, un
///   `TextField` sortent vides ou tronqués. Un rendu vide rendrait toutes les
///   mesures *vacuement vertes* — d'où `chaqueSujetRendDeLEncre`, qui exige
///   qu'un sujet porte de l'encre avant qu'on mesure quoi que ce soit. Les
///   sujets sont donc des **composants** construits sur des données simples,
///   jamais les onglets entiers.
///
///   **Le champ de recherche a été retiré pour cette raison précise**, et le
///   cas mérite d'être raconté : il *passait* la garde d'encre, parce que sa
///   capsule, sa loupe et sa croix se rendent très bien. Seul son `TextField`
///   ne se rendait pas — la console le disait, « Unable to render flattened
///   version of PlatformViewRepresentableAdaptor ». On aurait donc mesuré la
///   marge de sa monture autour d'un texte absent, et déclaré vert un
///   composant dont on n'avait pas regardé le contenu. Une garde d'encre
///   globale ne voit pas un trou local.
/// - **Ce qui déborde d'un cadre fixe.** `ONTRailDeLettres` tient dans 22
///   points de large par construction ; au dernier cran d'accessibilité ses
///   lettres sortent de cette colonne, et l'image rendue fait quand même 22
///   points — ce qui dépasse est peint hors du bitmap, donc invisible à la
///   mesure. La mesure 1 voit un cadre qui refuse de rétrécir, pas un contenu
///   qui sort d'un cadre qui, lui, a rétréci.
/// - **Le chevauchement interne.** Deux éléments qui se marchent dessus au
///   milieu de la vue ne touchent aucun bord et ne débordent de rien.
/// - **La lisibilité, le contraste, l'esthétique.** `ThemeContrastTests` et
///   `GammeContrastTests` tiennent le contraste ; ce fichier ne tient que la
///   place.
/// - **Le défilement.** Une vue dans un `ScrollView` a le droit de couper au
///   bord — c'est même son correctif. `bordsLibres` porte ces exemptions,
///   sujet par sujet et bord par bord, avec leur raison.
///
/// ## Pourquoi les sujets sont rendus nus
///
/// Sans la marge de page qui les entoure dans l'app. La tentation inverse est
/// forte — « rendre comme à l'écran » — et elle vide l'épreuve : la marge de
/// page garantirait à elle seule que rien ne touche le bord, et la mesure 2
/// serait verte pour tous, toujours. On mesure donc la marge **propre** du
/// composant, celle qu'il porte lui-même.
@MainActor
struct LargeursTests {

    // MARK: - La matrice

    /// Les largeurs qui comptent, en points.
    ///
    /// Pas des noms d'appareils : des largeurs. Un appareil se renomme et se
    /// retire du catalogue, une largeur reste une largeur — et le Duo, dont on
    /// ignore encore les dimensions, s'ajoutera ici sans qu'on touche au reste.
    static let largeurs: [(nom: String, points: CGFloat)] = [
        // Le plancher réel d'iOS : l'iPhone SE de première génération et la
        // colonne étroite d'un iPad en Split View. C'est là que vivaient les
        // deux défauts du 8 septembre.
        ("étroite (320)", 320),
        ("iPhone standard (375)", 375),
        ("iPhone large (430)", 430),
        // Une moitié d'iPad, et la largeur que prend une feuille sur grand
        // écran.
        ("moitié d'iPad (744)", 744),
        ("iPad pleine largeur (1024)", 1024),
    ]

    /// Les crans de Dynamic Type éprouvés.
    ///
    /// Trois, et non douze : le défaut n'apparaît pas progressivement, il
    /// apparaît à un seuil. Le cran par défaut sert de témoin — si un sujet y
    /// est déjà rouge, ce n'est pas un défaut d'accessibilité mais un défaut
    /// tout court. `accessibilityMedium` est le premier cran d'accessibilité,
    /// **celui où Gloire lit**. Le dernier est la borne.
    static let crans: [(nom: String, categorie: ContentSizeCategory)] = [
        ("par défaut", .large),
        ("accessibilité, premier cran", .accessibilityMedium),
        ("accessibilité, dernier cran", .accessibilityExtraExtraExtraLarge),
    ]

    /// Les deux peaux qu'on mesure.
    ///
    /// La géométrie ne dépend pas du thème, mais **le détecteur de bord, si** :
    /// il lit des couleurs, et cherche un contraste entre l'encre et son fond.
    /// Un détecteur validé en clair seulement pourrait rester aveugle en
    /// sombre — et le sombre est la peau que l'auteur emploie.
    static let peaux: [ReadingTheme] = [.parchment, .mystique]

    // MARK: - Les seuils

    /// La marge minimale exigée entre le contenu et le bord de sa vue, en points.
    ///
    /// Quatre, et non douze. Ce n'est pas la marge de bon goût — c'est le seuil
    /// en dessous duquel on ne parle plus de marge mais de contact. Le pavé de
    /// prononciation en portait seize par accident, puis zéro ; la valeur
    /// exacte relève du design system, pas d'une épreuve.
    static let margeMinimale = 4

    /// Ce qui compte comme un « pas brusque » entre deux pixels voisins, sur
    /// une échelle de 0 à 1 par canal.
    ///
    /// Calibré contre `TemoinSansMarge` : au-dessous de ce seuil, le témoin
    /// cesse d'être signalé et l'épreuve ne mesure plus rien ; bien au-dessus,
    /// l'anticrénelage d'un glyphe passe pour un fond uni. Un dégradé de fond
    /// varie de quelques millièmes d'un pixel au suivant — il en faut deux
    /// ordres de grandeur de plus pour être une lettre.
    static let seuilDePas = 0.20

    /// Ce qui compte comme « le fond est là » au bord, en opacité.
    ///
    /// Sert à trouver la partie **plate** du bord — voir `Rendu.platDuBord`.
    /// Bas à dessein : certaines surfaces de la maison sont des voiles très
    /// dilués (`theme.ink.opacity(0.06)`), et un seuil confortable les
    /// déclarerait transparentes, donc immesurables.
    static let seuilDeFond = 0.05

    /// Ce qu'on retire à chaque bout de la partie plate, en points.
    ///
    /// L'anticrénelage du dernier pixel d'un arc : la transition du vide vers
    /// le fond s'étale sur un ou deux pixels, et le seuil bas de `seuilDeFond`
    /// la fait commencer tôt. Trois points de rab la couvrent largement.
    static let rabDuBordPlat = 3

    /// Jusqu'où l'on cherche le contenu, en points.
    ///
    /// Au-delà, la marge est largement suffisante et la question ne se pose
    /// plus. Chercher plus loin ne dirait rien de plus et coûterait à chaque
    /// case de la matrice.
    static let profondeur = 48

    /// Le plancher de couverture de la mesure de marge.
    ///
    /// **Relevé le 10 septembre 2026 : 462 cas répondent.** Le plancher est posé
    /// nettement en dessous, parce qu'il ne mesure pas la qualité de la
    /// couverture mais son effondrement — un sujet retiré, un cran écarté, un
    /// composant qui gagne un fond translucide font varier ce nombre sans que
    /// rien n'aille mal.
    ///
    /// Le relever quand des sujets s'ajoutent est légitime. Le baisser pour
    /// faire passer une épreuve rouge ne l'est pas : ce serait exactement la
    /// dérive qu'il est là pour rendre visible.
    static let mesuresAttendues = 400

    /// La part de la surface qui doit porter de l'encre pour qu'une mesure
    /// veuille dire quelque chose.
    ///
    /// C'est la garde contre le vert vide. `ImageRenderer` ne se plaint pas
    /// quand il ne sait pas rendre une vue : il rend une image, simplement
    /// vide. Toutes les mesures qui suivent seraient alors vertes — aucun
    /// débordement, aucune encre au bord — et l'épreuve entière ne mesurerait
    /// rien tout en paraissant tenir. Un demi-pour-cent de la surface suffit à
    /// distinguer « rendu » de « pas rendu » sans exiger une vue pleine.
    static let encreMinimale = 0.005

    // MARK: - Les sujets

    /// Ce qu'on rend, et ce qu'on lui accorde.
    ///
    /// Un `enum` plutôt qu'un tableau de vues : `arguments:` exige des valeurs
    /// `Sendable`, et une `AnyView` ne l'est pas. Le cas voyage, la vue se
    /// construit sur le `MainActor` à l'intérieur de l'épreuve.
    enum Sujet: String, CaseIterable, Sendable {
        case pavePrononciation
        case carteDuJourGrande
        case carteDuJourMoyenne
        case carteDuJourPetite
        case carteDePartage
        case segments
        case railDeLettres
        case pastilleDEtat
        case pastilleDePartage
        case carteBordeaux
        case blocSourdine
        case colonneDeLecture
        case legendeDeSection
        case blocDeProse

        var nom: String {
            switch self {
            case .pavePrononciation: "le pavé de prononciation du Lexique"
            case .carteDuJourGrande: "la carte du jour, grand format"
            case .carteDuJourMoyenne: "la carte du jour, format moyen"
            case .carteDuJourPetite: "la carte du jour, petit format"
            case .carteDePartage: "la carte de partage"
            case .segments: "le sélecteur en segments"
            case .railDeLettres: "le rail des lettres du Lexique"
            case .pastilleDEtat: "la pastille d'état"
            case .pastilleDePartage: "la pastille « Partager » de la carte du jour"
            case .carteBordeaux: "la carte bordeaux"
            case .blocSourdine: "le bloc en sourdine"
            case .colonneDeLecture: "la colonne de lecture"
            case .legendeDeSection: "la légende de section"
            case .blocDeProse: "un bloc de prose du corpus"
            }
        }

        /// Les bords dont on n'exige aucune marge, et **pourquoi** — la raison
        /// est dans le libellé, pour qu'une exemption ne puisse pas se poser
        /// sans être justifiée à celui qui la relira.
        var bordsLibres: [Bord: String] {
            switch self {
            case .segments:
                // Le correctif du 8 septembre : quand la rangée ne tient plus,
                // elle défile au lieu de tronquer. Un rail qui défile coupe au
                // bord — c'est ce qu'on lui demande. Exiger une marge ici
                // reviendrait à déclarer défectueux le composant qu'on vient
                // de réparer.
                [.gauche: "la rangée défile quand elle ne tient plus",
                 .droite: "la rangée défile quand elle ne tient plus"]
            case .railDeLettres:
                // Le rail est une colonne de 22 points de large : ses lettres
                // occupent toute la largeur par construction. C'est la hauteur
                // qui l'intéresse.
                [.gauche: "une colonne de 22 points, ses lettres la remplissent",
                 .droite: "une colonne de 22 points, ses lettres la remplissent"]
            default:
                [:]
            }
        }

        /// Faux quand la vue n'a pas à répondre à la largeur qu'on lui propose.
        ///
        /// Il n'y a qu'un cas, et il n'est pas un écran : une **image**. La
        /// carte de partage fait 1080 points de côté par construction — c'est
        /// la taille que les messageries acceptent sans recompresser, et elle
        /// ne dépend d'aucun appareil. Lui reprocher de sortir d'un écran de
        /// 320 points reviendrait à lui reprocher d'être une image.
        ///
        /// Elle reste éprouvée pour la marge : une image dont le renvoi touche
        /// le bord est aussi fautive qu'un écran.
        var suitLaProposition: Bool {
            switch self {
            case .carteDePartage: false
            default: true
            }
        }

        /// Faux quand la vue est faite pour **ne pas** suivre Dynamic Type.
        var grandit: Bool {
            switch self {
            case .carteDePartage:
                // Une image de partage doit rendre pareil chez tout le monde :
                // le lecteur qui a monté son curseur ne doit pas envoyer une
                // image différente de celle du voisin. Sa taille est un
                // paramètre, pas un réglage système.
                false
            case .railDeLettres:
                // Vingt-deux lettres à la queue leu leu, à une taille fixe : le
                // rail sert à viser, pas à lire.
                false
            default:
                true
            }
        }

        @MainActor
        var vue: AnyView {
            switch self {
            case .pavePrononciation:
                AnyView(HeroDePrononciation(action: {}))
            case .carteDuJourGrande:
                AnyView(ONTDailyCard(text: Self.verset, reference: Self.renvoi, size: .large))
            case .carteDuJourMoyenne:
                AnyView(ONTDailyCard(text: Self.verset, reference: Self.renvoi, size: .medium))
            case .carteDuJourPetite:
                AnyView(ONTDailyCard(text: Self.verset, reference: Self.renvoi, size: .small))
            case .carteDePartage:
                AnyView(
                    ONTVerseCard(
                        text: Self.verset, reference: Self.renvoi, size: 20, theme: ONTTheme()
                    )
                )
            case .segments:
                AnyView(SegmentsTemoin())
            case .railDeLettres:
                AnyView(
                    ONTRailDeLettres(
                        lettres: ["A", "B", "C", "D", "E", "F", "G", "H"], vers: { _ in }
                    )
                )
            case .pastilleDEtat:
                AnyView(StatusPill("Brouillon"))
            case .pastilleDePartage:
                AnyView(ONTDailySharePill(destination: URL(string: "ont://verset")!))
            case .carteBordeaux:
                AnyView(BurgundyCard { Text(Self.libelleLong).font(ONTUI.body) })
            case .blocSourdine:
                AnyView(QuietBlock { Text(Self.libelleLong).font(ONTUI.body) })
            case .colonneDeLecture:
                AnyView(ParchmentPage { Text(Self.libelleLong).font(ONTUI.body) })
            case .legendeDeSection:
                AnyView(SectionCaption("Ce que dit le chapitre"))
            case .blocDeProse:
                // Du corpus, et non une chaîne inventée : le rendu du texte ONT
                // passe par `ONTTextRenderer`, qui pose des liens, des gloses et
                // des intraduisibles. Une vue qui tient sur du texte nu peut très
                // bien céder sur du texte composé.
                AnyView(
                    BlocDeFiche(
                        block: .paragraph([
                            .text("Quand "),
                            .term("Elohim", lemma: "elohim"),
                            .text(" commença de façonner les cieux et la terre"),
                        ])
                    )
                )
            }
        }

        /// Un verset assez long pour se replier, assez court pour rester lisible
        /// dans un message d'échec.
        private static var verset: AttributedString {
            AttributedString("Quand Elohim commença de façonner les cieux et la terre")
        }

        private static let renvoi = "Bereshit 1.1"

        private static let libelleLong =
            "Une phrase assez longue pour se replier sur deux lignes à la largeur la plus étroite."
    }

    // MARK: - Les épreuves

    @Test("chaque sujet rend de l'encre — sans quoi les mesures ne mesurent rien")
    func chaqueSujetRendDeLEncre() throws {
        // Cette épreuve passe **avant** les trois autres dans l'ordre de
        // lecture, et c'est délibéré : les trois suivantes n'ont de valeur que
        // si celle-ci est verte. Un sujet dont `ImageRenderer` ne sait rien
        // faire sortirait blanc à toutes, et l'épreuve se croirait tenue.
        var muets: [String] = []
        for sujet in Sujet.allCases {
            guard let rendu = rendre(sujet.vue, largeur: 375, cran: .large, peau: .mystique) else {
                muets.append("\(sujet.nom) — le rendu a échoué")
                continue
            }
            if rendu.partDEncre < Self.encreMinimale {
                muets.append(
                    "\(sujet.nom) — \(pourcent(rendu.partDEncre)) d'encre, "
                        + "rendu à \(entier(rendu.taille.width))×\(entier(rendu.taille.height)) pt"
                )
            }
        }
        #expect(
            muets.isEmpty,
            """
            \(muets.count) sujet(s) ne rendent rien hors écran. Leurs mesures de \
            largeur seraient vertes sans rien mesurer :
            \(muets.map { "  · \($0)" }.joined(separator: "\n"))
            """
        )
    }

    @Test("la mesure de marge atteint encore sa cible")
    func laMargeResteMesurable() throws {
        // ## La seconde garde contre le vert vide
        //
        // `margeDuContenu` rend `nil` quand il n'y a rien de fiable à mesurer —
        // le petit bord d'une capsule, une vue sans fond. C'est honnête, et
        // c'est aussi une porte ouverte : un détecteur cassé rendrait `nil`
        // partout, `margeAuxQuatreBords` n'aurait plus une seule faute à
        // signaler, et l'épreuve virerait au vert en cessant de mesurer.
        //
        // On compte donc les cas où elle **répond**. Le plancher est un ordre de
        // grandeur, pas une cible : il ne dit pas « la couverture est bonne », il
        // dit « la couverture ne s'est pas effondrée ».
        //
        // ## Ce que ce compte ne distingue pas, et qu'il faut savoir en le lisant
        //
        // Un sujet qui pèse zéro n'est pas forcément immesurable : `margeDuContenu`
        // rend aussi `nil` quand elle n'a **rien trouvé** en s'enfonçant de
        // `profondeur` points, c'est-à-dire quand la marge est confortable. La
        // carte de partage en est là — 90 points de marge, bien au-delà des 48
        // qu'on explore — et les cartes du jour aussi, faute de fond à elles :
        // ce sont leurs conteneurs qui les habillent.
        //
        // Le relevé par sujet est donc imprimé dans le message d'échec, et pas
        // seulement le total : c'est lui qui dit si un zéro veut dire « large »
        // ou « aveugle », et les deux ne se corrigent pas pareil.
        var mesures = 0
        var parSujet: [String: Int] = [:]
        for sujet in Sujet.allCases {
            for peau in Self.peaux {
                for (_, largeur) in Self.largeurs {
                    for (_, cran) in Self.crans {
                        guard let rendu = rendre(sujet.vue, largeur: largeur, cran: cran, peau: peau)
                        else { continue }
                        for bord in Bord.allCases where rendu.margeDuContenu(au: bord) != nil {
                            mesures += 1
                            parSujet[sujet.nom, default: 0] += 1
                        }
                    }
                }
            }
        }
        #expect(
            mesures >= Self.mesuresAttendues,
            """
            La mesure de marge ne répond plus que dans \(mesures) cas, contre \
            \(Self.mesuresAttendues) attendus au minimum. Elle a cessé de voir \
            quelque chose, et `margeAuxQuatreBords` est donc verte pour rien.
            Par sujet :
            \(parSujet.sorted { $0.value < $1.value }
                .map { "  · \($0.key) — \($0.value)" }.joined(separator: "\n"))
            """
        )
    }

    @Test("aucun sujet ne déborde de la largeur qu'on lui propose", arguments: Sujet.allCases)
    func aucunDebordement(_ sujet: Sujet) throws {
        guard sujet.suitLaProposition else { return }
        var fautes: [String] = []
        for peau in Self.peaux {
            for (nomLargeur, largeur) in Self.largeurs {
                for (nomCran, cran) in Self.crans {
                    guard let rendu = rendre(sujet.vue, largeur: largeur, cran: cran, peau: peau)
                    else { continue }
                    // Un demi-point de tolérance : `proposedSize` et le rendu
                    // ne s'arrondissent pas au même endroit, et un écart d'un
                    // demi-pixel n'est pas un défaut de mise en page.
                    let deborde = rendu.taille.width - largeur
                    if deborde > 0.5 {
                        fautes.append(
                            "  · \(nomLargeur), \(nomCran), \(peau.rawValue) — "
                                + "\(entier(deborde)) pt de trop "
                                + "(la vue prend \(entier(rendu.taille.width)) pt)"
                        )
                    }
                }
            }
        }
        #expect(
            fautes.isEmpty,
            """
            \(sujet.nom) sort de l'écran dans \(fautes.count) cas. Sur l'appareil, \
            ce qui dépasse est simplement invisible :
            \(fautes.joined(separator: "\n"))
            """
        )
    }

    @Test("aucun sujet ne colle son contenu au bord", arguments: Sujet.allCases)
    func margeAuxQuatreBords(_ sujet: Sujet) throws {
        let libres = sujet.bordsLibres
        var fautes: [String] = []
        for peau in Self.peaux {
            for (nomLargeur, largeur) in Self.largeurs {
                for (nomCran, cran) in Self.crans {
                    guard let rendu = rendre(sujet.vue, largeur: largeur, cran: cran, peau: peau)
                    else { continue }
                    guard rendu.partDEncre >= Self.encreMinimale else { continue }
                    for bord in Bord.allCases where libres[bord] == nil {
                        guard let marge = rendu.margeDuContenu(au: bord) else { continue }
                        if marge < Self.margeMinimale {
                            fautes.append(
                                "  · bord \(bord.rawValue) — \(marge) pt "
                                    + "(\(nomLargeur), \(nomCran), \(peau.rawValue))"
                            )
                        }
                    }
                }
            }
        }
        #expect(
            fautes.isEmpty,
            """
            \(sujet.nom) : le contenu touche le bord dans \(fautes.count) cas, \
            il faut au moins \(Self.margeMinimale) pt.
            \(exemptions(libres))
            \(fautes.prefix(24).joined(separator: "\n"))
            \(fautes.count > 24 ? "  … et \(fautes.count - 24) autres" : "")
            """
        )
    }

    @Test("un sujet qui porte du texte grandit avec le texte", arguments: Sujet.allCases)
    func laHauteurSuitLeTexte(_ sujet: Sujet) throws {
        guard sujet.grandit else { return }
        var fautes: [String] = []
        for (nomLargeur, largeur) in Self.largeurs {
            guard
                let petit = rendre(sujet.vue, largeur: largeur, cran: .large, peau: .mystique),
                let grand = rendre(
                    sujet.vue, largeur: largeur,
                    cran: .accessibilityExtraExtraExtraLarge, peau: .mystique
                )
            else { continue }
            guard petit.partDEncre >= Self.encreMinimale else { continue }
            if grand.taille.height <= petit.taille.height {
                fautes.append(
                    "  · \(nomLargeur) — \(entier(petit.taille.height)) pt au cran par défaut, "
                        + "\(entier(grand.taille.height)) pt au dernier cran"
                )
            }
        }
        #expect(
            fautes.isEmpty,
            """
            \(sujet.nom) ne grandit pas quand le texte grandit. Une vue qui porte \
            du texte et garde sa hauteur le rogne quelque part — c'est le seul \
            angle sous lequel cette épreuve voit une troncature :
            \(fautes.joined(separator: "\n"))
            """
        )
    }

    // MARK: - Les témoins : la preuve que l'épreuve peut rougir

    // Un contrôle qu'on n'a jamais vu échouer ne mesure rien. La règle du
    // projet demande de le retourner contre le code d'avant ; on garde donc
    // **dans le fichier** les trois défauts qu'il doit voir, chacun réduit à sa
    // plus simple expression. Ils rougissent si le détecteur cesse de
    // fonctionner, à chaque exécution, sans que personne ait à casser une vue
    // à la main.
    //
    // C'est le motif de `BarreCalculee` dans `DynamicTypeTests`, qui documente
    // le piège de `ONTSpacing` en restant à côté de lui.

    @Test("le témoin sans marge est bien signalé — sinon la mesure 2 ne mesure rien")
    func leTemoinSansMargeRougit() throws {
        // `TemoinSansMarge` reproduit exactement le pavé d'avant le correctif.
        // Il doit être **vert au cran par défaut** — 76 points de hauteur
        // minimale contre un contenu plus court, le cadre le centre — et
        // **rouge au premier cran d'accessibilité**, où le contenu dépasse 76
        // et où le cadre l'épouse sans rien laisser autour.
        //
        // Les deux moitiés comptent autant l'une que l'autre : un détecteur
        // toujours rouge est aussi inutile qu'un détecteur toujours vert, et
        // seul le couple prouve qu'il lit quelque chose.
        let calme = try #require(
            rendre(TemoinSansMarge(), largeur: 320, cran: .large, peau: .mystique)
        )
        let serre = try #require(
            rendre(
                TemoinSansMarge(), largeur: 320,
                cran: .accessibilityMedium, peau: .mystique
            )
        )

        let margeCalme = calme.margeDuContenu(au: .haut)
        #expect(
            (margeCalme ?? Self.profondeur) >= Self.margeMinimale,
            """
            Le détecteur signale une faute au cran par défaut, où il n'y en a \
            pas : \(margeCalme.map(String.init) ?? "aucun contenu trouvé") pt. \
            Il rougit donc sur du sain, et ses verdicts ne valent plus rien.
            """
        )

        let margeSerree = try #require(
            serre.margeDuContenu(au: .haut),
            "aucun contenu trouvé près du bord haut du témoin — le détecteur est aveugle"
        )
        #expect(
            margeSerree < Self.margeMinimale,
            """
            Le détecteur n'a pas vu le défaut du 8 septembre. Le témoin colle son \
            titre au bord haut au premier cran d'accessibilité, et la mesure rend \
            \(margeSerree) pt — au-dessus du seuil de \(Self.margeMinimale) pt.
            Rendu : \(entier(serre.taille.width))×\(entier(serre.taille.height)) pt, \
            \(pourcent(serre.partDEncre)) d'encre.
            """
        )
    }

    @Test("le témoin trop large est bien signalé — sinon la mesure 1 ne mesure rien")
    func leTemoinTropLargeRougit() throws {
        let rendu = try #require(
            rendre(TemoinTropLarge(), largeur: 320, cran: .large, peau: .mystique)
        )
        #expect(
            rendu.taille.width - 320 > 0.5,
            """
            Le détecteur de débordement n'a pas vu une vue qui exige 500 points \
            quand on lui en propose 320 : elle rend à \(entier(rendu.taille.width)) pt. \
            `proposedSize` n'est donc plus une proposition, et la mesure 1 ne dit \
            plus rien.
            """
        )
    }

    @Test("le témoin sans encre est bien signalé — sinon la garde ne garde rien")
    func leTemoinSansEncreRougit() throws {
        // La garde contre le vert vide doit elle-même pouvoir rougir. Sans ce
        // témoin, rien ne dirait qu'elle sait distinguer une vue rendue d'une
        // vue que `ImageRenderer` a laissée blanche.
        let rendu = try #require(
            rendre(TemoinSansEncre(), largeur: 320, cran: .large, peau: .mystique)
        )
        #expect(
            rendu.partDEncre < Self.encreMinimale,
            """
            Une vue entièrement transparente compte pour \(pourcent(rendu.partDEncre)) \
            d'encre. La garde laisserait donc passer un sujet non rendu, et les \
            trois mesures seraient vertes sans rien mesurer.
            """
        )
    }

    // MARK: - Le rendu hors écran

    /// Rend un sujet et le décompose en pixels, ou rend `nil` si le rendu échoue.
    ///
    /// `scale = 1` fait qu'un pixel vaut un point : tous les seuils de ce
    /// fichier se lisent alors en points, dans l'unité où l'on discute d'une
    /// marge. À `scale = 3`, ils devraient tous être divisés quelque part, et
    /// ce quelque part serait l'endroit où l'on se tromperait.
    ///
    /// `proposedSize` **propose** au lieu d'imposer : c'est toute la mesure 1.
    /// Un `.frame(width:)` aurait forcé la largeur et laissé le contenu déborder
    /// *hors* de l'image, où il aurait été rogné au rendu — donc invisible à la
    /// mesure. La proposition, elle, laisse la vue répondre sa vraie taille.
    private func rendre(
        _ vue: some View,
        largeur: CGFloat,
        cran: ContentSizeCategory,
        peau: ReadingTheme
    ) -> Rendu? {
        var preferences = ReadingPreferences.default
        preferences.theme = peau

        let habillee =
            vue
            // `.ontTheme(from:)` et non `.ontTheme(_:)`, et ce n'est pas un
            // détail de style : le premier passe par `ScaledThemeModifier`, qui
            // porte un `@ScaledMetric` et multiplie `textSize` par le facteur du
            // curseur système. Le second fige `scaledTextSize` à la valeur des
            // préférences. Le harnais aurait donc rendu un corpus qui **ne suit
            // pas Dynamic Type**, alors que l'app le fait suivre : on aurait
            // éprouvé une variante de l'app, pas l'app.
            .ontTheme(from: preferences)
            // Le schéma de couleurs, posé à la main.
            //
            // `ScaledThemeModifier` le pose lui-même par `preferredColorScheme`,
            // mais c'est un réglage de **scène** : hors écran il n'y a pas de
            // scène, et il ne s'applique pas. Sans cette ligne, un `Text` sans
            // couleur explicite reste noir sur la nuit aubergine — le détecteur
            // n'y voit alors aucun contraste et rend `nil` là où il devrait
            // mesurer. Relevé au calibrage : la colonne de lecture se mesurait
            // en parchemin et pas en mystique, pour cette seule raison.
            .environment(\.colorScheme, peau.isDark ? .dark : .light)
            .environment(\.sizeCategory, cran)

        let moteur = ImageRenderer(content: habillee)
        moteur.scale = 1
        // Sans transparence, le vide se rendrait en noir opaque et deviendrait
        // indiscernable d'un texte noir : la garde contre le vert vide ne
        // saurait plus dire si la vue a été rendue.
        moteur.isOpaque = false
        moteur.proposedSize = ProposedViewSize(width: largeur, height: nil)

        guard let image = moteur.uiImage, let cg = image.cgImage else { return nil }
        return Rendu(cg: cg, taille: image.size)
    }

    // MARK: - Le relevé lisible

    private func entier(_ valeur: CGFloat) -> String { String(format: "%.0f", valeur) }

    private func pourcent(_ part: Double) -> String { String(format: "%.2f %%", part * 100) }

    private func exemptions(_ libres: [Bord: String]) -> String {
        guard !libres.isEmpty else { return "" }
        return "Bords exemptés : "
            + libres.map { "\($0.key.rawValue) (\($0.value))" }.sorted().joined(separator: ", ")
    }
}

// MARK: - Les bords

/// Les quatre bords d'un rendu, nommés dans le sens de la lecture.
///
/// « haut » veut dire ce que l'œil appelle le haut, et non la ligne zéro du
/// tampon : Core Graphics compte ses lignes depuis le bas, et confondre les
/// deux ferait chercher le défaut à l'opposé de là où il est. La conversion se
/// fait à un seul endroit — l'accesseur `pixel(x:y:)` de `Rendu` — pour qu'il
/// n'y ait qu'un endroit où se tromper.
enum Bord: String, CaseIterable, Sendable {
    case haut, bas, gauche, droite
}

// MARK: - Un rendu, lu au pixel

/// Une image rendue hors écran, et les trois questions qu'on lui pose.
@MainActor
struct Rendu {
    /// Ce que la vue a **pris**, en points — pas ce qu'on lui a proposé.
    let taille: CGSize

    private let largeurPx: Int
    private let hauteurPx: Int
    /// RGBA prémultiplié, quatre octets par pixel, ligne du bas en premier.
    private let octets: [UInt8]

    init(cg: CGImage, taille: CGSize) {
        self.taille = taille
        self.largeurPx = cg.width
        self.hauteurPx = cg.height

        var tampon = [UInt8](repeating: 0, count: max(1, cg.width * cg.height * 4))
        tampon.withUnsafeMutableBytes { brut in
            guard
                let contexte = CGContext(
                    data: brut.baseAddress,
                    width: cg.width,
                    height: cg.height,
                    bitsPerComponent: 8,
                    bytesPerRow: cg.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else { return }
            contexte.draw(
                cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
            )
        }
        self.octets = tampon
    }

    /// Un pixel, `y` compté **depuis le haut** — voir `Bord`.
    private func pixel(x: Int, y: Int) -> (r: Double, v: Double, b: Double, a: Double) {
        let ligne = hauteurPx - 1 - y
        let i = (ligne * largeurPx + x) * 4
        guard i >= 0, i + 3 < octets.count else { return (0, 0, 0, 0) }
        return (
            Double(octets[i]) / 255, Double(octets[i + 1]) / 255,
            Double(octets[i + 2]) / 255, Double(octets[i + 3]) / 255
        )
    }

    /// La part de la surface qui porte de l'encre.
    ///
    /// « De l'encre » veut dire « pas complètement transparent ». Le seuil de 8
    /// sur 255 écarte l'anticrénelage d'une ombre portée, qui couvre une grande
    /// surface à une opacité dérisoire et ferait passer une vue vide pour une
    /// vue rendue.
    var partDEncre: Double {
        guard largeurPx > 0, hauteurPx > 0 else { return 0 }
        var encre = 0
        for i in stride(from: 3, to: octets.count, by: 4) where octets[i] > 8 { encre += 1 }
        return Double(encre) / Double(largeurPx * hauteurPx)
    }

    /// La distance, en points, entre un bord et la première trace de contenu.
    ///
    /// ## Comment on reconnaît « du contenu »
    ///
    /// Par un **pas brusque** *le long* du bord, et non par la présence d'encre.
    /// La distinction est tout l'intérêt de la mesure : un fond de carte porte
    /// de l'encre sur toute sa surface, y compris au bord — il y est
    /// légitimement, c'est sa surface. Ce qui ne doit pas y être, c'est un
    /// glyphe ou une icône, et un glyphe se trahit par une variation franche
    /// d'un pixel au suivant.
    ///
    /// Un dégradé se disqualifie tout seul : il varie de quelques millièmes par
    /// pixel, deux ordres de grandeur sous le seuil. Un aplat uni ne varie pas
    /// du tout. Un trait de bordure d'un point non plus, tant qu'on le suit
    /// dans sa longueur — c'est pour cela qu'on scrute *le long* du bord et non
    /// perpendiculairement.
    ///
    /// ## Ce que rend `nil`
    ///
    /// Trois cas, et aucun n'est une faute : aucun contenu trouvé jusqu'à
    /// `profondeur` (la marge est largement suffisante), ou bord trop court
    /// pour qu'il en reste quelque chose une fois les coins retirés. Le second
    /// est le seul endroit où l'épreuve renonce en silence, et il est borné :
    /// une vue de moins de cinquante points dans une dimension.
    func margeDuContenu(au bord: Bord) -> Int? {
        let seuil = LargeursTests.seuilDePas

        // La longueur du bord, et sa profondeur possible.
        let (longueur, epaisseurMax) =
            switch bord {
            case .haut, .bas: (largeurPx, hauteurPx)
            case .gauche, .droite: (hauteurPx, largeurPx)
            }
        guard let plat = platDuBord(bord, longueur: longueur) else { return nil }

        let profondeur = min(LargeursTests.profondeur, epaisseurMax)
        for d in 0..<profondeur {
            var precedent: (r: Double, v: Double, b: Double, a: Double)?
            for t in plat {
                let p = auBord(bord, t: t, profondeur: d)
                if let q = precedent {
                    let pas = max(
                        max(abs(p.r - q.r), abs(p.v - q.v)),
                        max(abs(p.b - q.b), abs(p.a - q.a))
                    )
                    if pas > seuil { return d }
                }
                precedent = p
            }
        }
        return nil
    }

    /// La partie **plate** d'un bord : là où le fond est déjà présent à la
    /// profondeur zéro.
    ///
    /// ## Pourquoi on la cherche au lieu de retirer les coins au jugé
    ///
    /// Un coin arrondi produit un pas brusque parfaitement légitime — le fond y
    /// rencontre le vide — et il faut donc l'écarter. La première version
    /// retirait un nombre fixe de points à chaque bout, puis un nombre calculé
    /// depuis les proportions. **Les deux ont rendu des relevés faux**, et pour
    /// la même raison : le rayon d'une `Capsule` n'est écrit nulle part, il vaut
    /// la moitié de sa hauteur. Le sélecteur en segments a été déclaré « contenu
    /// à 1 pt du bord » sur ses bords haut et bas, puis le champ de recherche
    /// « à 0 pt » sur ses bords gauche et droit — où l'arc occupe le bord
    /// **entier**, si bien qu'aucune fraction retirée ne pouvait suffire.
    ///
    /// On cesse donc de deviner la forme, et on la **relève** : les positions où
    /// le fond touche déjà le bord sont, par construction, celles où la forme ne
    /// se courbe pas. Ça marche pour un rectangle arrondi, une capsule, un
    /// rectangle franc et tout ce qu'on n'a pas encore dessiné.
    ///
    /// ## Ce que ça rend `nil`, et pourquoi c'est le bon aveu
    ///
    /// Deux cas :
    ///
    /// - **le bord d'une capsule dans sa petite dimension** — l'arc l'occupe en
    ///   entier, il n'y a pas de partie plate. C'est exact : il n'y a rien à
    ///   mesurer là, et le prétendre serait le relevé faux qu'on vient de
    ///   corriger ;
    /// - **une vue sans fond** — une rangée de liste, une légende. Sa marge ne
    ///   lui appartient pas, elle vient du conteneur qui l'accueille.
    ///
    /// Un `nil` n'est jamais compté comme une réussite : `laMargeResteMesurable`
    /// veille à ce que leur nombre ne puisse pas enfler en silence jusqu'à vider
    /// l'épreuve.
    private func platDuBord(_ bord: Bord, longueur: Int) -> Range<Int>? {
        // La plus longue plage contiguë où le fond est présent. « La plus
        // longue » et non « la première » : deux glyphes qui touchent le bord
        // en produiraient de petites, et c'est la surface qu'on cherche.
        var meilleure: Range<Int>?
        var debut: Int?
        for t in 0...longueur {
            let present =
                t < longueur && auBord(bord, t: t, profondeur: 0).a > LargeursTests.seuilDeFond
            if present {
                if debut == nil { debut = t }
            } else if let d = debut {
                if meilleure == nil || (t - d) > meilleure!.count { meilleure = d..<t }
                debut = nil
            }
        }
        guard let plage = meilleure else { return nil }
        // Deux cinquièmes du bord au moins. En deçà, ce n'est pas une surface
        // qui touche le bord, ce sont quelques glyphes — et les prendre pour un
        // fond ferait mesurer la marge d'une chose par rapport à elle-même.
        guard plage.count * 5 >= longueur * 2 else { return nil }

        let rab = LargeursTests.rabDuBordPlat
        let bas = plage.lowerBound + rab
        let haut = plage.upperBound - rab
        // Moins de huit points à scruter : le bord ne dit plus rien de fiable.
        guard haut - bas >= 8 else { return nil }
        return bas..<haut
    }

    /// Un pixel repéré par son bord, sa position le long de ce bord, et sa
    /// profondeur vers l'intérieur.
    ///
    /// Une seule conversion, à un seul endroit — c'est ici qu'on saurait où
    /// chercher si les bords se retrouvaient un jour inversés.
    private func auBord(
        _ bord: Bord, t: Int, profondeur d: Int
    ) -> (r: Double, v: Double, b: Double, a: Double) {
        switch bord {
        case .haut: pixel(x: t, y: d)
        case .bas: pixel(x: t, y: hauteurPx - 1 - d)
        case .gauche: pixel(x: d, y: t)
        case .droite: pixel(x: largeurPx - 1 - d, y: t)
        }
    }
}

// MARK: - Les témoins

/// Le pavé de prononciation **d'avant le correctif du 8 septembre 2026**.
///
/// Volontairement fautif, et gardé tel quel : `.frame(minHeight: 76)` sans
/// aucune marge verticale. Tant que le contenu tient sous 76 points, le cadre
/// le centre et l'espace au-dessus ressemble à une marge ; dès qu'il dépasse —
/// c'est-à-dire dès le premier cran d'accessibilité — le cadre l'épouse
/// exactement et le titre touche le bord.
///
/// Toute réécriture qui lui ajouterait un `.padding(.vertical:)` ferait tomber
/// `leTemoinSansMargeRougit`, et l'épreuve cesserait de prouver qu'elle voit
/// quelque chose. C'est le filet, pas une négligence — le même motif que
/// `BarreCalculee` dans `DynamicTypeTests`.
private struct TemoinSansMarge: View {
    @Environment(\.ontTheme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Comment ça se prononce")
                    .font(ONTUI.headline)
                Text("Les cinq sons que le français n'a pas")
                    .font(ONTUI.footnote)
            }
            .foregroundStyle(ONTColors.onBrandAccent(theme.mode))
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "waveform")
                .font(.system(size: ONTUI.points(22), weight: .light))
                .foregroundStyle(ONTColors.onBrandAccent(theme.mode))
        }
        .padding(.horizontal, 20)
        // Pas de `.padding(.vertical:)` — c'est le défaut, en une ligne absente.
        .frame(minHeight: ONTUI.points(76))
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(ONTColors.brandInk(theme.mode))
        )
    }
}

/// Une vue qui refuse la proposition : cinq cents points, quoi qu'on lui offre.
///
/// C'est la forme la plus pure du défaut que la mesure 1 cherche — une largeur
/// écrite en dur, qui sort de l'écran sans que rien ne l'annonce.
private struct TemoinTropLarge: View {
    var body: some View {
        Color.red.frame(width: 500, height: 40)
    }
}

/// Une vue qui rend une image, et rien dedans.
///
/// Le sosie de ce que `ImageRenderer` produit quand il ne sait pas rendre une
/// vue adossée à UIKit. La garde contre le vert vide doit le voir.
private struct TemoinSansEncre: View {
    var body: some View {
        Color.clear.frame(width: 200, height: 60)
    }
}

/// Le sélecteur en segments, avec l'état que sa liaison exige.
///
/// `ONTSegments` prend un `Binding` : il lui faut un propriétaire. Les libellés
/// sont ceux du Lexique, parce que ce sont eux qui tombaient à « V », « T »,
/// « S » — le sujet mérite d'être éprouvé avec les mots qui l'ont mis en défaut.
private struct SegmentsTemoin: View {
    @State private var choix = 0

    var body: some View {
        ONTSegments(
            selection: $choix,
            segments: [
                (0, "Intraduisibles"), (1, "Vocabulaire"), (2, "Thèmes"), (3, "Shemot"),
            ]
        )
    }
}
