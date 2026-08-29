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
        // Posé ici plutôt que par un `.kerning()` sur la vue : la prose
        // continue et le mode blocs passent tous deux par cette fonction, et
        // un modificateur de vue aurait demandé de ne pas l'oublier deux fois.
        if theme.tracking != 0 { output.kern = theme.tracking }
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
    /// ## Pourquoi un `Text` et non une `AttributedString`
    ///
    /// Chaque verset devient un `Text` marqué de son numéro
    /// (`ONTVerseAttribute`), et les marques ne survivent qu'à cette forme —
    /// une `AttributedString` ne sait pas les porter jusqu'au moteur de dessin.
    ///
    /// ## Ce qui n'est plus ici
    ///
    /// Ni estompage, ni soulignement. Le résultat ne dépend **pas** de la
    /// sélection, et c'est tout l'intérêt : il reste identique d'un appui à
    /// l'autre, donc la mise en page a lieu une fois pour le bloc.
    /// `ONTProseRenderer` fait le reste au dessin, où changer d'avis ne coûte
    /// qu'un repeint.
    ///
    /// Ce qui reste, en revanche, dépend du texte lui-même et n'a aucune raison
    /// de bouger quand un doigt se pose :
    ///
    /// * **le surlignage**, un fond posé sur la plage du verset ;
    /// * **la désignation**, un lien `ont://verse/<n>` sur cette même plage.
    ///   Les intraduisibles gardent le leur : le lien le plus intérieur
    ///   l'emporte, donc toucher un terme ouvre sa fiche et toucher ailleurs
    ///   désigne le verset.
    public static func flowingText(
        verses: [Verse],
        theme: ONTTheme,
        highlight: (Int) -> Color?
    ) -> Text {
        let type = theme.type
        var sortie = Text("")

        for verse in verses {
            // Le numéro **à part**, et c'est ce qui permet de l'épargner.
            //
            // Il est en exposant ; le pointillé de désignation, tracé sous la
            // ligne, ne le rejoint donc jamais et fait un décroché à chaque
            // début de verset. Le mode blocs l'évitait depuis toujours en ne
            // soulignant que le corps — la prose, elle, soulignait tout.
            //
            // Comme une marque ne se pose que sur un `Text` entier, il faut
            // que le numéro en soit un. `ONTProseRenderer` saute alors les
            // fragments qui la portent.
            var numero = AttributedString("\(verse.n)\u{00A0}")
            numero.font = type.verseNumber.font
            numero.foregroundColor = type.verseNumber.color
            numero.baselineOffset = type.verseBaselineOffset

            // Une espace pleine entre deux versets, jamais un retour à la
            // ligne : c'est toute la différence entre les deux modes.
            var corps = compose(verse.nodes, theme: theme)
            corps += run(" ", type.corpus)

            if let fond = highlight(verse.n) {
                numero.backgroundColor = fond
                corps.backgroundColor = fond
            }
            if let cible = verseURL(verse.n) {
                poserLeLien(cible, sur: &numero)
                poserLeLien(cible, sur: &corps)
            }

            sortie = sortie
                + Text(numero)
                    .customAttribute(ONTVerseAttribute(n: verse.n))
                    .customAttribute(ONTNumeroDeVerset())
                + Text(corps).customAttribute(ONTVerseAttribute(n: verse.n))
        }
        return sortie
    }

    /// Le corps d'un verset en prose continue, tel qu'il est réellement rendu.
    ///
    /// Ouvert aux épreuves parce que c'est **la seule** représentation où l'on
    /// peut vérifier ce que porte chaque caractère : `flowingText` rend un
    /// `Text`, qui ne s'inspecte pas. Un défaut de zone tactile ne se voit ni à
    /// la compilation ni dans le rendu — seulement ici.
    public static func corpsEnProse(_ verse: Verse, theme: ONTTheme) -> AttributedString {
        var corps = compose(verse.nodes, theme: theme)
        corps += run(" ", theme.type.corpus)
        if let cible = verseURL(verse.n) {
            poserLeLien(cible, sur: &corps)
        }
        return corps
    }

    /// Pose un lien partout où il n'y en a pas déjà.
    ///
    /// Les plages sont relevées **avant** d'écrire. Poser un lien fusionne des
    /// runs voisins, donc parcourir `runs` en modifiant la chaîne qu'on
    /// parcourt travaille sur des plages que l'écriture précédente a déjà
    /// invalidées — une faute qui ne se voit que sur certains versets, ceux
    /// dont le balisage produit assez de runs pour que la fusion décale tout.
    private static func poserLeLien(_ cible: URL, sur chaine: inout AttributedString) {
        let plages = chaine.runs.filter { $0.attributes.link == nil }.map(\.range)
        for plage in plages {
            chaine[plage].link = cible
        }
    }

    /// Ce qu'un lecteur d'écran doit prononcer pour une suite de versets.
    ///
    /// ## Pourquoi ça ne va pas de soi
    ///
    /// En lecture suivie, une section entière est un seul `Text` dont chaque
    /// fragment porte un lien — le renvoi qui rend le verset touchable. SwiftUI
    /// expose donc un **élément par fragment** : quatre-vingt-quinze pour un
    /// chapitre, relevés sur Bereshit 11, annoncés « lien » et coupés au milieu
    /// des phrases. « unifiés (devarim ahadim / … ) [ » est un énoncé complet
    /// pour VoiceOver, et ne veut rien dire pour personne.
    ///
    /// Le texte n'était donc pas muet, il était haché. On rend ici une phrase
    /// continue, où les numéros de verset sont **dits** plutôt que laissés en
    /// exposant que rien ne prononce.
    ///
    /// On compose avec le thème du lecteur, gloses et hébreu compris s'ils sont
    /// allumés : ce qui se lit à l'oreille doit être ce qui s'affiche à l'œil,
    /// sinon éteindre une glose ne l'éteindrait que pour les voyants.
    public static func aLireAVoixHaute(verses: [Verse], theme: ONTTheme) -> String {
        verses
            // Les **nœuds**, et non `compose(verse:)` : celui-là préfixe déjà
            // le numéro en exposant, et on l'entendrait deux fois.
            .map { "Verset \($0.n). " + String(compose($0.nodes, theme: theme).characters) }
            .joined(separator: " ")
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

            case .accentuation(let children):
                // Aucun lien, délibérément : une accentuation n'a pas de
                // fiche de lexique, et un mot qui répond au doigt sans rien
                // avoir à dire est pire qu'un mot qui ne répond pas.
                var marque = AttributedString()
                append(children, to: &marque, type: type, inGloss: inGloss)
                for piece in marque.runs where piece.attributes.link == nil {
                    marque[piece.range].foregroundColor = ONTColors.accentuation(type.theme)
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

            case .link(let children, let href):
                // **L'adresse était jetée ici**, et les renvois n'étaient donc
                // touchables nulle part. Une glose qui écrit « déjà posé en
                // *Bereshit* 9:27 » désigne une unité que le lecteur ne peut
                // pas trouver seul : la numérotation ONT repart de 1 à chaque
                // unité, et 9:27 est le dixième verset de la neuvième.
                //
                // Le pipeline a fait le calcul et l'a mis dans le lien. Il
                // suffit de le porter jusqu'à l'attribut, et `RootView` le
                // rattrape déjà : `openURL` passe par le routeur, qui
                // reconnaît le domaine du site et ouvre l'unité au verset —
                // sans jamais sortir vers Safari.
                var lie = AttributedString()
                append(children, to: &lie, type: type, inGloss: inGloss)
                if let url = URL(string: href) {
                    lie.link = url
                    // Le renvoi se distingue du corps sans crier : la couleur
                    // de l'accentuation, pas l'or — l'or promet une fiche, et
                    // un renvoi n'en est pas une.
                    lie.foregroundColor = ONTColors.accentuation(type.theme)
                    lie.underlineStyle = .single
                }
                output += lie

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
            case .accentuation(let children):
                // Une accentuation survit à l'extinction des niveaux : elle
                // appartient au corps, pas à l'appareil critique. Mais ses
                // enfants sont nettoyés — il peut contenir une glose.
                kept.append(
                    .accentuation(children.prepared(showGloss: showGloss, showLevel3: showLevel3))
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
