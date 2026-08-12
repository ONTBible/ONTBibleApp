import ONTKit
import SwiftUI

/// Le rendu du texte ONT — les trois niveaux en typographie.
///
/// Transforme un arbre `[Inline]` en `AttributedString`. Toutes les décisions
/// visuelles viennent de `ONTTypography` : ce fichier ne contient plus une
/// seule taille ni une seule couleur en dur, donc changer de fonte ou ajouter
/// un thème ne demande pas d'y revenir.
///
/// Les intraduisibles portent un lien `ont://term/<lemme>` : les toucher ouvre
/// leur fiche. On préfère le **toucher** à l'appui long de Bible Strong parce
/// qu'ici les cibles sont rares et identifiées — pas besoin de distinguer le
/// geste de la sélection de texte.
public enum ONTTextRenderer {
    public static let termScheme = "ont"

    public static func termURL(_ lemma: String) -> URL? {
        URL(string: "\(termScheme)://term/\(lemma)")
    }

    /// L'adresse qui désigne un verset — employée seulement en lecture continue.
    public static func verseURL(_ n: Int) -> URL? {
        URL(string: "\(termScheme)://verse/\(n)")
    }

    // MARK: - Composition

    /// Compose un fragment de texte ONT.
    public static func compose(_ nodes: [Inline], theme: ONTTheme) -> AttributedString {
        var output = AttributedString()
        let prepared = nodes.prepared(
            showGloss: theme.preferences.showGloss,
            showLevel3: theme.preferences.showLevel3
        )
        append(prepared, to: &output, type: theme.type, inGloss: false)
        return output
    }

    /// Compose un verset, précédé de son numéro en exposant.
    ///
    /// `underlined` pose le pointillé de sélection — sous le texte, comme dans
    /// YouVersion et Bible Strong. Un soulignement suit les retours à la ligne
    /// et n'ajoute aucune surface colorée : il désigne sans se confondre avec
    /// le surlignage, qui, lui, est une marque que le lecteur a posée.
    public static func compose(
        verse: Verse,
        theme: ONTTheme,
        underlined: Bool = false
    ) -> AttributedString {
        let type = theme.type

        var number = AttributedString("\(verse.n)\u{00A0}")
        number.font = type.verseNumber.font
        number.foregroundColor = type.verseNumber.color
        number.baselineOffset = type.verseBaselineOffset

        var body = compose(verse.nodes, theme: theme)
        if underlined {
            // Seulement le corps : le numéro est en exposant, et son
            // soulignement flotterait au-dessus de celui de la ligne.
            body.underlineStyle = Text.LineStyle(
                pattern: .dot,
                color: ONTColors.accent(theme.mode).opacity(0.8)
            )
        }
        return number + body
    }

    /// Compose un bloc de versets **à la suite**, en prose continue.
    ///
    /// ## Pourquoi ce n'est pas seulement une mise en page
    ///
    /// En bloc par verset, chaque verset est une vue : on la touche, on lui
    /// pose un fond de surlignage, on l'anime. En prose continue il n'y a plus
    /// qu'un seul `Text` — tout ce qui reposait sur « une vue par verset »
    /// disparaît d'un coup.
    ///
    /// D'où deux reports dans le texte lui-même :
    ///
    /// * **le surlignage** devient un `backgroundColor` sur la plage du verset,
    ///   au lieu d'un rectangle dessiné derrière une ligne ;
    /// * **la désignation** devient un lien `ont://verse/<n>` sur cette même
    ///   plage. Les intraduisibles gardent le leur : le lien le plus intérieur
    ///   l'emporte, donc toucher un terme ouvre sa fiche et toucher ailleurs
    ///   désigne le verset.
    ///
    /// C'est aussi pour ça que le pointillé de sélection reste juste : un
    /// soulignement suit les retours à la ligne, un cadre non.
    public static func composeFlowing(
        verses: [Verse],
        theme: ONTTheme,
        selected: Set<Int>,
        highlight: (Int) -> Color?
    ) -> AttributedString {
        let type = theme.type
        var output = AttributedString()

        for verse in verses {
            var morceau = compose(verse: verse, theme: theme, underlined: selected.contains(verse.n))

            if let fond = highlight(verse.n) {
                morceau.backgroundColor = fond
            }
            // Le lien de désignation ne se pose que là où il n'y en a pas déjà :
            // un intraduisible garde le sien.
            if let cible = verseURL(verse.n) {
                for piece in morceau.runs where piece.attributes.link == nil {
                    morceau[piece.range].link = cible
                }
            }
            output += morceau
            // Une espace pleine entre deux versets, jamais un retour à la
            // ligne : c'est toute la différence entre les deux modes.
            output += run(" ", type.corpus)
        }
        return output
    }

    /// Compose le corps seul — ce qu'on partage ou ce qu'on met en exergue.
    public static func composeBare(
        _ nodes: [Inline],
        theme: ONTTheme,
        ink: Color? = nil
    ) -> AttributedString {
        var bare = theme
        bare.preferences.showGloss = false
        bare.preferences.showLevel3 = false

        var output = compose(nodes, theme: bare)
        if let ink {
            output.foregroundColor = ink
        }
        return output
    }

    private static func run(_ text: String, _ style: ONTTextStyle) -> AttributedString {
        var run = AttributedString(text)
        run.font = style.font
        run.foregroundColor = style.color
        return run
    }

    private static func append(
        _ nodes: [Inline],
        to output: inout AttributedString,
        type: ONTTypography,
        inGloss: Bool
    ) {
        for node in nodes {
            switch node {
            case .text(let value):
                output += run(value, inGloss ? type.gloss : type.corpus)

            case .term(let value, let lemma):
                var style = type.term
                if inGloss { style.font = type.gloss.font }
                var piece = run(value, style)
                piece.link = termURL(lemma)
                output += piece

            case .hebrew(let value):
                output += hebrewRun(value, style: inGloss ? type.hebrewSmall : type.hebrew)

            case .translit(let translit, let hebrew):
                output += run("(", type.apparatus)
                output += run(translit, type.translit)
                output += run(" / ", type.apparatus)
                output += hebrewRun(hebrew, style: type.hebrewSmall)
                output += run(")", type.apparatus)

            case .gloss(let children):
                output += run("[", type.apparatus)
                append(children, to: &output, type: type, inGloss: true)
                output += run("]", type.apparatus)

            case .important(let children):
                // Aucun lien, délibérément : un terme important n'a pas de
                // fiche de lexique, et un mot qui répond au doigt sans rien
                // avoir à dire est pire qu'un mot qui ne répond pas.
                var marque = AttributedString()
                append(children, to: &marque, type: type, inGloss: inGloss)
                for piece in marque.runs where piece.attributes.link == nil {
                    marque[piece.range].foregroundColor = ONTColors.important(type.theme)
                    if let font = marque[piece.range].font {
                        marque[piece.range].font = font.weight(.semibold)
                    }
                }
                output += marque

            case .emphasis(let children):
                var nested = AttributedString()
                append(children, to: &nested, type: type, inGloss: inGloss)
                // L'italique se pose par-dessus, sans écraser la fonte
                // hébraïque que les enfants ont pu poser.
                for piece in nested.runs where piece.attributes.link == nil {
                    if let font = nested[piece.range].font {
                        nested[piece.range].font = font.italic()
                    }
                }
                output += nested

            case .link(let children, _):
                append(children, to: &output, type: type, inGloss: inGloss)

            case .lineBreak:
                output += AttributedString("\n")
            }
        }
    }

    /// Une séquence hébraïque, isolée du texte latin qui l'entoure.
    ///
    /// Les marques d'isolation Unicode (FSI … PDI) empêchent l'algorithme bidi
    /// d'emporter la ponctuation française voisine dans le sens
    /// droite-à-gauche — sans elles, une parenthèse fermante saute de l'autre
    /// côté du mot.
    private static func hebrewRun(_ value: String, style: ONTTextStyle) -> AttributedString {
        run("\u{2068}\(value)\u{2069}", style)
    }
}

// MARK: - Préparation de l'arbre

extension [Inline] {
    /// Retire les niveaux éteints, puis resserre les blancs qu'ils laissent.
    ///
    /// Sans ce nettoyage, éteindre les gloses laisse « se laissa voir    par
    /// lui ». Les données restent fidèles à la source ; c'est l'affichage qui
    /// recolle.
    func prepared(showGloss: Bool, showLevel3: Bool) -> [Inline] {
        var kept: [Inline] = []

        for node in self {
            switch node {
            case .gloss(let children):
                guard showGloss else { continue }
                kept.append(.gloss(children.prepared(showGloss: showGloss, showLevel3: showLevel3)))
            case .translit where !showLevel3:
                continue
            case .hebrew where !showLevel3:
                continue
            case .emphasis(let children):
                kept.append(
                    .emphasis(children.prepared(showGloss: showGloss, showLevel3: showLevel3))
                )
            case .important(let children):
                // Un terme important survit à l'extinction des niveaux : il
                // appartient au corps, pas à l'appareil critique. Mais ses
                // enfants sont nettoyés — il peut contenir une glose.
                kept.append(
                    .important(children.prepared(showGloss: showGloss, showLevel3: showLevel3))
                )
            case .link(let children, let href):
                kept.append(
                    .link(
                        children.prepared(showGloss: showGloss, showLevel3: showLevel3),
                        href: href
                    )
                )
            default:
                kept.append(node)
            }
        }

        return kept.mergingText().tighteningWhitespace()
    }

    /// Fusionne les nœuds de texte devenus voisins après un retrait.
    func mergingText() -> [Inline] {
        reduce(into: [Inline]()) { output, node in
            if case .text(let value) = node, case .text(let previous) = output.last {
                output[output.count - 1] = .text(previous + value)
            } else {
                output.append(node)
            }
        }
    }

    /// Resserre les espaces, en respectant la typographie française.
    ///
    /// On rabat les blancs multiples et l'espace devant `, . …` — mais **pas**
    /// celui qui précède `: ; ! ?` ni le guillemet fermant, que le français
    /// exige et que le texte source porte déjà correctement.
    func tighteningWhitespace() -> [Inline] {
        var output = map { node -> Inline in
            guard case .text(let value) = node else { return node }
            var tightened = value.replacingOccurrences(
                of: " {2,}",
                with: " ",
                options: .regularExpression
            )
            tightened = tightened.replacingOccurrences(
                of: " +([,.\u{2026}])",
                with: "$1",
                options: .regularExpression
            )
            return .text(tightened)
        }

        if case .text(let first) = output.first {
            let trimmed = String(first.drop { $0 == " " })
            if trimmed.isEmpty { output.removeFirst() } else { output[0] = .text(trimmed) }
        }
        return output
    }
}
