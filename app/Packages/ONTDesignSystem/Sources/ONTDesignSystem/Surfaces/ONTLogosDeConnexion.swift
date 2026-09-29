import ONTKit
import SwiftUI

/// **Les marques de Google et GitHub** — Apple garde son symbole système.
///
/// ## Deux provenances remplacées, une gardée
///
/// L'écran portait trois glyphes venus de trois endroits : `g.circle.fill` —
/// ==un G générique d'Apple, pas celui de Google== —, trois chevrons `</>` qui
/// se lisaient sans dire GitHub, et `apple.logo` des symboles du système.
///
/// **Les deux premiers changent, le troisième reste**, et l'asymétrie est
/// plus juste que la symétrie : sur une plateforme Apple, `apple.logo` **est**
/// le mark sanctionné — celui qu'Apple fournit, dans la famille qu'elle
/// fournit, pour l'usage qu'elle prévoit. ==Y mettre un logo tiers serait un
/// écart là où il n'y en avait aucun à faire.==
///
/// Ionicons porte les deux autres : même grille 512, même graisse, et
/// monochromes — donc ils prennent la teinte de leur bouton au lieu d'y poser
/// la leur, comme `apple.logo` le fait déjà.
///
/// Décision de l'auteur le 29 septembre 2026, en deux temps : « récupère le
/// Google et GitHub icon », puis la correction d'un portage qui avait étendu
/// le geste à Apple. ==La demande nommait deux fournisseurs ; je l'ai appliquée
/// aux trois.==
///
/// Le site, lui, prend les trois chez Ionicons : la licence des SF Symbols les
/// réserve aux plateformes Apple. C'est là que la ressemblance au pixel
/// s'arrête, et c'est juste — le bouton Apple d'une app iOS et celui d'un site
/// n'ont pas à être le même objet.
///
/// ## Ce qui a été essayé avant, et pourquoi c'est écarté
///
/// **Le mark officiel de Google**, tiré de son kit — les quatre couleurs
/// `#4285F4`, `#EA4335`, `#FBBC05`, `#34A853`. C'est ce que ses *Branding
/// Guidelines* demandent, et c'était la réponse juste à la question posée.
///
/// Mais il est multicolore, et ==il devenait la seule tache de couleur de
/// l'app== : les deux autres marques sont monochromes et suivent la palette.
/// Posé sur une capsule bordeaux, il exigeait en plus une pastille claire —
/// un troisième objet dans un bouton qui en compte deux.
///
/// Aucune variante monochrome officielle n'existe : mesuré le 29 septembre,
/// les cinq sources du kit rendent les quatre couleurs, et
/// `googleg_white_128dp` comme `googleg_grey_128dp` répondent 404.
///
/// ## Ce que ça engage, dit une fois
///
/// Google demande son mark tel qu'il le fournit. Un logo tiers — même MIT,
/// même excellent — s'en écarte. Le risque est **une remarque en relecture
/// App Store**, pas un refus : c'est Google qui édicte ces règles, pas Apple,
/// et l'usage est très répandu. Cet écran a reçu une remarque le 19 août, donc
/// le risque n'est pas nul.
///

/// **Licence** : Ionicons, MIT, Ionic 2015–présent. Redistribution et usage
/// commercial permis, attribution non exigée.
public enum ONTLogoDeConnexion {
    /// La marque d'un fournisseur, teintée comme son bouton.
    ///
    /// `template` est posé dans le catalogue, pas ici : une image de marque
    /// qui arriverait en `original` peindrait sa propre couleur sur un bouton
    /// qui en a déjà une, et ==rien ne le signalerait==.
    public static func marque(_ nom: Nom, cote: CGFloat, teinte: Color) -> some View {
        Image(nom.rawValue, bundle: .module)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(teinte)
            .frame(width: cote, height: cote)
    }

    /// Les deux fournisseurs dont la marque est embarquée.
    ///
    /// Apple n'y est pas, et c'est le point : son symbole vient du système.
    public enum Nom: String {
        case google = "LogoGoogle"
        case github = "LogoGitHub"

        /// **`nil` pour Apple**, et c'est le contrat : l'appelant doit alors
        /// poser le symbole du système.
        ///
        /// Rendre un cas `apple` ici obligerait à embarquer un logo pour lui,
        /// c'est-à-dire exactement ce qu'on vient de défaire. ==Le `nil` dit
        /// « cette marque ne vient pas d'ici », et le compilateur force
        /// l'appelant à s'en occuper.==
        public init?(_ fournisseur: AuthProvider) {
            switch fournisseur {
            case .google: self = .google
            case .github: self = .github
            case .apple: return nil
            }
        }
    }
}
