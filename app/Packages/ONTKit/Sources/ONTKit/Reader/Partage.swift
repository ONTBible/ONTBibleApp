import Foundation

/// Ce qu'un passage partagé emporte avec lui.
///
/// **On ne partage pas un verset à sa mère et à un groupe d'étude de la même
/// manière.** La forme était figée — référence complète, nom de l'app, lien —
/// et il n'y avait pas moyen d'en sortir.
///
/// Les défauts reprennent ceux que Bible Strong a éprouvés sur des années, à
/// une exception près, motivée plus bas.
public struct ReglagesDePartage: Codable, Hashable, Sendable {
    /// « ¹ Quand Elohim commença… » plutôt que « Quand Elohim commença… ».
    ///
    /// Allumé : c'est ce qui permet de retrouver le passage, et c'est le seul
    /// endroit du partage où le texte lui-même porte l'information.
    public var numerosDeVersets: Bool
    /// Les versets à la file, ou un par ligne.
    ///
    /// À la suite par défaut : c'est ainsi qu'on cite. Un par ligne sert à
    /// l'étude, où l'on veut voir la structure.
    public var versetsALaSuite: Bool
    /// Le corps entre chevrons français.
    public var guillemets: Bool
    /// « — Bereshit 1:1-3, **La Bible ONT** ».
    ///
    /// **Éteint par défaut**, comme chez Bible Strong. Celui qui partage cite
    /// un texte, il ne fait pas de la réclame ; et le lien, quand il est là,
    /// dit déjà d'où ça vient.
    public var nomDeLApp: Bool
    /// Le lien vers `ontbible.com`.
    ///
    /// **Allumé par défaut, et c'est notre écart avec Bible Strong** — qui n'a
    /// pas de site où renvoyer. Le lien est ce qui fait qu'un passage partagé
    /// ramène quelqu'un au texte entier ; l'ôter a un coût qui n'est pas
    /// typographique.
    ///
    /// Il reste une bascule, parce que dans un message à un proche il encombre
    /// autant qu'il sert.
    public var lien: Bool

    public static let `default` = ReglagesDePartage(
        numerosDeVersets: true, versetsALaSuite: true, guillemets: true,
        nomDeLApp: false, lien: true)

    public init(
        numerosDeVersets: Bool = true, versetsALaSuite: Bool = true,
        guillemets: Bool = true, nomDeLApp: Bool = false, lien: Bool = true
    ) {
        self.numerosDeVersets = numerosDeVersets
        self.versetsALaSuite = versetsALaSuite
        self.guillemets = guillemets
        self.nomDeLApp = nomDeLApp
        self.lien = lien
    }

    /// Décodage tolérant : un fichier écrit avant un champ se relit.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ReglagesDePartage.default
        numerosDeVersets =
            try c.decodeIfPresent(Bool.self, forKey: .numerosDeVersets) ?? d.numerosDeVersets
        versetsALaSuite =
            try c.decodeIfPresent(Bool.self, forKey: .versetsALaSuite) ?? d.versetsALaSuite
        guillemets = try c.decodeIfPresent(Bool.self, forKey: .guillemets) ?? d.guillemets
        nomDeLApp = try c.decodeIfPresent(Bool.self, forKey: .nomDeLApp) ?? d.nomDeLApp
        lien = try c.decodeIfPresent(Bool.self, forKey: .lien) ?? d.lien
    }
}

/// La composition d'un passage à partager.
public enum Partage {
    /// Le nom de l'app, tel qu'il paraît dans une signature.
    public static let nom = "La Bible ONT"

    /// Un verset prêt à composer — son numéro et son corps déjà aplati.
    public struct Morceau: Hashable, Sendable {
        public let numero: Int
        public let texte: String

        public init(numero: Int, texte: String) {
            self.numero = numero
            self.texte = texte
        }
    }

    /// Compose le texte partagé.
    ///
    /// **Pure, et c'est ce qui permet l'aperçu.** L'écran des options appelle
    /// exactement cette fonction sur un passage d'exemple : ce que le lecteur
    /// voit changer sous les bascules est le rendu réel, pas une imitation qui
    /// dériverait au premier changement de règle.
    ///
    /// Le lien n'entre pas ici : il voyage comme **second élément** du partage,
    /// ce qui laisse iOS en faire un aperçu cliquable au lieu d'une adresse
    /// noyée dans une phrase.
    public static func composer(
        _ morceaux: [Morceau],
        reference: String,
        reglages: ReglagesDePartage
    ) -> String {
        let lignes = morceaux.map { morceau in
            reglages.numerosDeVersets ? "\(morceau.numero) \(morceau.texte)" : morceau.texte
        }
        var corps = lignes.joined(separator: reglages.versetsALaSuite ? " " : "\n")

        if reglages.guillemets, !corps.isEmpty {
            // Chevrons français, avec l'espace insécable que la typographie
            // demande de chaque côté. Sans elle, un retour à la ligne peut
            // séparer le chevron du mot qu'il ouvre.
            corps = "«\u{00A0}\(corps)\u{00A0}»"
        }

        // La signature reste sur sa propre ligne, séparée du corps : c'est ce
        // qui permet à qui reçoit de citer le texte sans la traîner.
        var signature = "— \(reference)"
        if reglages.nomDeLApp { signature += ", \(nom)" }

        return corps.isEmpty ? signature : "\(corps)\n\n\(signature)"
    }

    /// Le texte et son lien, en **une seule chaîne**.
    ///
    /// C'est ce que le presse-papier demande : il n'a qu'un contenu, là où une
    /// feuille de partage porte deux objets — le texte d'un côté, l'URL de
    /// l'autre, pour que la messagerie en tire un aperçu.
    ///
    /// **Le copier ne l'emportait pas**, et rien ne le disait. Le lecteur qui
    /// allume la bascule du lien la croit vraie partout ; il colle son verset
    /// dans un message, et le lien manque sans qu'aucun écran ne lui ait
    /// annoncé l'exception.
    ///
    /// Le lien va sur sa propre ligne, détaché par une ligne blanche comme la
    /// signature : ce qui se cite doit pouvoir se séparer de ce qui
    /// l'accompagne.
    public static func avecLien(_ texte: String, _ lien: URL?) -> String {
        guard let lien else { return texte }
        return "\(texte)\n\n\(lien.absoluteString)"
    }
}
