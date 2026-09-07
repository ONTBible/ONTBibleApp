#!/usr/bin/env swift
//
// Mesurer la hauteur d'une ligne qui mêle le latin et l'hébreu.
//
//   swift scripts/banc-interligne.swift
//
// ## Pourquoi un banc, et pourquoi celui-ci
//
// Quatre bancs ont répondu à côté avant lui, le 30 août 2026, et **aucun n'a
// échoué** : deux composaient une écriture avec la fonte système sans le dire,
// un comparait EzraSIL au système plutôt qu'à Literata, un concluait d'un seul
// point de mesure. Chacun rendait des nombres plausibles et une cause fausse.
//
// D'où les deux garde-fous en tête de fichier, qui sont l'essentiel de ce
// script :
//
//   1. **inscrire les fontes** — `CTFontManagerRegisterFontsForURL`. Un
//      processus qui n'est pas l'app ne les a pas : `Font.custom` retombe alors
//      en silence sur la fonte système, et l'on mesure autre chose ;
//   2. **vérifier qu'elles répondent** avant de mesurer quoi que ce soit, et
//      s'arrêter sinon. C'est la garde qui manquait aux quatre.
//
// ## Ce qu'il établit
//
// La cause n'est pas qu'une fonte soit plus haute que l'autre — leurs boîtes de
// ligne se valent à taille égale. C'est que la ligne mêlée prend l'ascendante
// la plus haute et la descendante la plus basse **parmi deux fontes
// différentes** : l'ascendante de Literata, la descendante d'EzraSIL.
//
// Et que `SwiftUI.Text` ignore le style de paragraphe, là où TextKit l'honore
// et referme l'écart à zéro. Le balayage le montre : un seul point de mesure ne
// distingue pas « ça répond » de « ça a bougé pour une autre raison ».

import AppKit
import CoreText
import SwiftUI

// MARK: - Les fontes, inscrites puis vérifiées

let fontes = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("app/Resources/Fonts")

for fichier in ["EzraSIL.ttf", "Literata-Regular.ttf"] {
    var erreur: Unmanaged<CFError>?
    CTFontManagerRegisterFontsForURL(
        fontes.appendingPathComponent(fichier) as CFURL, .process, &erreur)
}

let CORPS = "Literata-Regular"
let HEBREU = "EzraSIL"
let TAILLE: CGFloat = 20
/// `ONTFonts.hebrewScale`.
let ECHELLE: CGFloat = 1.08
let LARGEUR: CGFloat = 420

for nom in [CORPS, HEBREU] where NSFont(name: nom, size: 12) == nil {
    print("✗ « \(nom) » ne répond pas — la mesure porterait sur la fonte de repli.")
    print("  Vérifier \(fontes.path)")
    exit(1)
}

func boite(_ f: NSFont) -> CGFloat { f.ascender - f.descender + f.leading }

// MARK: - Le texte mesuré

let AVANT = "Au commencement, Elohim créa les cieux et la terre, et la terre était"
let APRES = " et vide, et les ténèbres"
let MOT = "וַיֵּרָא"
/// De même longueur que `MOT`, pour que la coupe des lignes ne change pas.
let TEMOIN = "informe"

@MainActor func rendu(_ a: AttributedString) -> CGFloat {
    ImageRenderer(content: Text(a).frame(width: LARGEUR, alignment: .leading))
        .nsImage?.size.height ?? 0
}

func course(_ s: String, _ nom: String, _ taille: CGFloat) -> AttributedString {
    var a = AttributedString(s)
    a.font = .custom(nom, size: taille)
    return a
}

func bloc(hebreu: Bool, echelle: CGFloat = ECHELLE) -> AttributedString {
    var a = course(AVANT + " ", CORPS, TAILLE)
    a +=
        hebreu
        ? course(MOT, HEBREU, TAILLE * echelle)
        : course(TEMOIN, CORPS, TAILLE)
    a += course(APRES, CORPS, TAILLE)
    return a
}

func impose(_ a: AttributedString, _ hauteur: CGFloat) -> AttributedString {
    var c = a
    let p = NSMutableParagraphStyle()
    p.minimumLineHeight = hauteur
    p.maximumLineHeight = hauteur
    c.appKit.paragraphStyle = p
    return c
}

/// Le même contenu, rendu par TextKit plutôt que par SwiftUI.
func renduTextKit(_ hebreu: Bool, imposee: CGFloat?) -> CGFloat {
    let latin = NSFont(name: CORPS, size: TAILLE)!
    let ezra = NSFont(name: HEBREU, size: TAILLE * ECHELLE)!
    let m = NSMutableAttributedString()
    m.append(NSAttributedString(string: AVANT + " ", attributes: [.font: latin]))
    m.append(
        NSAttributedString(
            string: hebreu ? MOT : TEMOIN, attributes: [.font: hebreu ? ezra : latin]))
    m.append(NSAttributedString(string: APRES, attributes: [.font: latin]))
    if let imposee {
        let p = NSMutableParagraphStyle()
        p.minimumLineHeight = imposee
        p.maximumLineHeight = imposee
        m.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: m.length))
    }
    let champ = NSTextField(labelWithAttributedString: m)
    champ.preferredMaxLayoutWidth = LARGEUR
    champ.lineBreakMode = .byWordWrapping
    return champ.sizeThatFits(NSSize(width: LARGEUR, height: .greatestFiniteMagnitude)).height
}

// MARK: - Le relevé

MainActor.assumeIsolated {
    let latin = NSFont(name: CORPS, size: TAILLE)!
    let ezra = NSFont(name: HEBREU, size: TAILLE * ECHELLE)!

    print("=== les métriques, à \(Int(TAILLE)) pt ===")
    for (nom, f) in [("Literata", latin), ("EzraSIL ×\(ECHELLE)", ezra)] {
        print(
            String(
                format: "  %-16s asc %6.2f  desc %6.2f  → boîte %6.2f",
                (nom as NSString).utf8String!, f.ascender, f.descender, boite(f)))
    }
    let melee = max(latin.ascender, ezra.ascender) - min(latin.descender, ezra.descender)
    print(String(format: "  ligne mêlée      = max(asc) + max(desc) = %6.2f", melee))
    print(String(format: "  → dépasse le latin seul de %+.2f pt\n", melee - boite(latin)))

    let pur = rendu(bloc(hebreu: false))
    print("=== rendu SwiftUI, largeur \(Int(LARGEUR)) pt ===")
    print(String(format: "  tout latin                       %6.2f", pur))
    for e in [1.00, 1.04, ECHELLE, 1.15] {
        let v = rendu(bloc(hebreu: true, echelle: e))
        print(String(format: "  fragment hébreu à %.2f×          %6.2f   écart %+.2f", e, v, v - pur))
    }

    print("\n=== SwiftUI honore-t-il le style de paragraphe ? ===")
    print("  (un seul point ne prouve rien — on balaie)")
    for h in [CGFloat(20), 26, 40, 60, 90] {
        print(
            String(
                format: "  imposé %2.0f → latin %6.2f   mêlé %6.2f", h,
                rendu(impose(bloc(hebreu: false), h)), rendu(impose(bloc(hebreu: true), h))))
    }

    print("\n=== TextKit, lui, l'honore ===")
    let l0 = renduTextKit(false, imposee: nil)
    print(String(format: "  sans style  latin %6.2f   mêlé %6.2f   écart %+.2f",
                 l0, renduTextKit(true, imposee: nil), renduTextKit(true, imposee: nil) - l0))
    for h in [CGFloat(26), 30, 34] {
        let a = renduTextKit(false, imposee: h)
        let b = renduTextKit(true, imposee: h)
        print(String(format: "  imposé %2.0f   latin %6.2f   mêlé %6.2f   écart %+.2f", h, a, b, b - a))
    }
}
