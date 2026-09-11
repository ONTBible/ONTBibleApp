import Foundation
import ONTKit
import SwiftUI

/// **Ce qui entre dans la feuille du verset d'origine.**
///
/// Trois choses, et elles viennent toutes du dehors : *où l'on est*
/// (`PositionDeVerset`), *ce que les langues sources disent de là* — le domaine
/// d'`ONTKit`, adapté ici en types de présentation — et *comment une fiche
/// arrive* (`ontFicheDunMot`).
///
/// ## Ce fichier portait un chargeur, et il n'en porte plus
///
/// `ChargeurDeSources` lisait `Bundle.main.resourceURL` à la main, décodait
/// `he-wlc/bereshit.json` — 476 Ko — **à chaque ouverture de feuille**, et
/// devinait le chemin d'un témoin au lieu de le lire au manifeste. Il le disait
/// lui-même en tête : un provisoire, en attendant la vraie couche.
///
/// La vraie couche est là — `SourcesRepository` dans `ONTKit`,
/// `DiskSourcesRepository` dans `ONTData` : le disque d'abord, le bundle en
/// socle, un cache par fichier, et le manifeste pour dire où sont les fichiers.
/// Il ne reste ici que ce qui est vraiment de la présentation — la traduction
/// du domaine vers ce que la feuille rend.

// MARK: - Où l'on est

/// Où se trouve un verset, en position et non en numéro.
public struct PositionDeVerset: Identifiable, Hashable, Sendable {
    public let livre: String
    public let unite: String
    public let position: Int

    public var id: String { "\(unite)#\(position)" }

    public init(livre: String, unite: String, position: Int) {
        self.livre = livre
        self.unite = unite
        self.position = position
    }
}

// MARK: - Du domaine à ce que la feuille rend

/// **La traduction se fait ici, une fois, au point d'entrée.**
///
/// `ONTKit` dit ce qu'un témoin *est* ; la feuille dit ce qu'elle en *montre*.
/// Les deux ne se recouvrent pas — l'un porte une `Langue` qui sait dans quel
/// sens elle court, l'autre un index stable pour se paginer — et les confondre
/// ferait remonter des soucis d'affichage jusque dans le domaine.
extension TemoinAffiche {
    /// **Le nom du manifeste est une attribution, pas un titre.**
    ///
    /// « Westminster Leningrad Codex + Open Scriptures Hebrew Bible » déborde
    /// sur deux lignes en tête de feuille, là où le lecteur attend de savoir en
    /// un coup d'œil quelle langue il regarde. On garde sa première part, avant
    /// le « + » ou le tiret cadratin — et le nom entier reste où il doit être,
    /// dans `Temoin.attribution`, que le domaine porte littéralement.
    ///
    /// C'est bien une décision de présentation : raccourcir dans `ONTKit`
    /// abîmerait le crédit que les licences exigent exact.
    init(_ temoin: Temoin) {
        self.init(
            id: temoin.cle,
            nom: Self.court(temoin.nom),
            langue: temoin.langue.code
        )
    }

    /// La première part d'un nom de témoin.
    private static func court(_ nom: String) -> String {
        for coupe in [" + ", " — ", " - "] {
            if let r = nom.range(of: coupe) {
                return String(nom[..<r.lowerBound])
            }
        }
        return nom
    }
}

extension MotAffiche {
    /// `rang` **est** l'index de présentation : c'est la position du mot dans
    /// le verset, la même des deux côtés. Rien à renuméroter.
    init(_ mot: MotSource) {
        self.init(
            id: mot.rang,
            forme: mot.texte,
            strong: mot.lemme,
            morphologie: mot.morphologie,
            translitteration: mot.translitteration,
            fiche: mot.cible
        )
    }
}

extension VersetAffiche {
    /// Même chose un cran plus haut : `rang` est la position dans l'unité, et
    /// `numero` reste ce qu'on affiche — **jamais ce qui identifie**. Une
    /// parashah qui couvre deux chapitres bibliques fait repartir la
    /// numérotation à ¹, et *Bereshit* 7 porte deux versets « 1 ».
    init(_ verset: VersetSource) {
        self.init(
            id: verset.rang,
            numero: verset.numero,
            texte: verset.texte,
            mots: verset.mots.map(MotAffiche.init)
        )
    }
}

// MARK: - Les fiches, pour les rendre dans la carte

/// Ce qu'une fiche ONT donne à lire, sans quitter le verset.
public struct FicheAffichee: Hashable, Sendable {
    /// La translittération — « bara », « ʾelohim ».
    public let titre: String
    public let hebreu: String?
    /// Ce que l'ONT en dit, tel que le corpus le porte.
    public let definition: [Block]

    public init(titre: String, hebreu: String?, definition: [Block]) {
        self.titre = titre
        self.hebreu = hebreu
        self.definition = definition
    }
}

/// **Comment la feuille obtient une fiche, sans savoir d'où elle vient.**
///
/// `ReadingFeature` ne dépend d'aucune autre feature — c'est écrit dans
/// `Package.swift` : « un onglet qui ne sait rien des autres reste un onglet
/// qu'on peut déplacer, replier ou retirer ». Et il ne lit pas non plus les
/// fichiers du corpus : le lexique a ses dépôts, et les court-circuiter
/// reviendrait à ouvrir un second chemin vers la même donnée.
///
/// La composition pose donc la fonction, et la lecture ne connaît qu'elle.
///
/// ## Pourquoi les langues sources, elles, ne passent pas par ici
///
/// Une fiche se compose de **deux** dépôts — le lexique et les Shemot — avec un
/// aiguillage sur la sorte de cible. Aucun port ne dit cette question-là : la
/// fonction est le plus petit contrat qui la porte.
///
/// Les langues sources en ont un, `SourcesRepository`, écrit pour cette
/// question et pour elle seule. Et une clé d'environnement **exige une valeur
/// par défaut** : ce serait ici un dépôt qui répond « aucun témoin » — soit
/// exactement ce que répondent six livres sur sept. Une composition qui
/// oublierait de la poser afficherait « pas de texte source » sur la Genèse,
/// sans une erreur, sans un rouge, et sans que la relecture puisse le voir. Le
/// port voyage donc par `ReadingModel`, où l'oublier ne compile pas.
public struct FicheDunMotKey: EnvironmentKey {
    public static let defaultValue: @Sendable (CibleDuNiveauTrois) -> FicheAffichee? = { _ in
        nil
    }
}

extension EnvironmentValues {
    /// La fiche d'un mot source, posée par la composition.
    public var ontFicheDunMot: @Sendable (CibleDuNiveauTrois) -> FicheAffichee? {
        get { self[FicheDunMotKey.self] }
        set { self[FicheDunMotKey.self] = newValue }
    }
}
