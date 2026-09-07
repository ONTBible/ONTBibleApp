#!/usr/bin/env swift
//
// Combien coûte la mise en page d'un chapitre entier, et selon quelle forme.
//
//   swift scripts/banc-chapitre.swift
//
// ## La question
//
// Refermer l'écart d'interligne demande de rendre le texte par TextKit plutôt
// que par `SwiftUI.Text` — voir `scripts/banc-interligne.swift`, qui établit
// pourquoi. Reste la crainte, légitime et jamais mesurée : **un chapitre long
// va-t-il ramer ?**
//
// Le risque n'est pas TextKit. Une grande vue de texte est *plus* rapide que
// beaucoup de petites : elle met en page une fois, dans un seul conteneur.
// Le risque est **une vue de texte par verset**, qui multiplie les `NSView` et
// paie une mise en page par verset là où `Text` était léger.
//
// C'est donc un choix d'architecture, pas de moteur, et c'est lui qu'on mesure.
//
// ## Ce que le banc compare
//
// Les deux architectures ne sont pas des hypothèses : **elles existent déjà
// côte à côte dans `ChapterView`**, relevé et non supposé — `ForEach(parts)`
// rend un verset par vue en lecture ordinaire, `flowingText` rend la prose
// continue d'un seul tenant. On mesure donc quatre chemins réels :
//
//   A1 — SwiftUI Text, une par verset       (l'existant, lecture ordinaire)
//   A2 — SwiftUI Text, d'un seul tenant     (l'existant, prose continue)
//   B  — TextKit, une vue par verset        (le remplacement naïf)
//   C  — TextKit, d'un seul tenant          (le portage qui tient)
//
// **B est celui qui inquiète** : c'est ce qu'on écrit si on ne mesure pas.
//
// **A inclut la rastérisation**, `ImageRenderer` n'ayant pas de mode « mise en
// page seule ». Ses valeurs sont un ordre de grandeur, pas un point de
// comparaison. La comparaison loyale est **B contre C** : même moteur, même
// mesure.
//
// ## Froid et chaud, séparés
//
// Un chapitre qui met 400 ms à paraître puis défile comme du beurre n'est pas
// le même défaut qu'un qui paraît vite et saccade — et l'auteur ne les vivrait
// pas pareil. Une moyenne les confondrait. On mesure donc **la première mise en
// page** et **les suivantes** à part.

import AppKit
import CoreText
import SwiftUI

let racine = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let fontes = racine.appendingPathComponent("app/Resources/Fonts")
for f in ["EzraSIL.ttf", "Literata-Regular.ttf", "Literata-Italic.ttf"] {
    var e: Unmanaged<CFError>?
    CTFontManagerRegisterFontsForURL(fontes.appendingPathComponent(f) as CFURL, .process, &e)
}

let CORPS = "Literata-Regular"
let HEBREU = "EzraSIL"
let TAILLE: CGFloat = 20
let ECHELLE: CGFloat = 1.08
let LARGEUR: CGFloat = 620

// La garde qui manquait aux bancs ratés du 30 août : sans elle, on mesure la
// mise en page de la fonte système et l'on croit mesurer la nôtre.
for nom in [CORPS, HEBREU] where NSFont(name: nom, size: 12) == nil {
    print("✗ « \(nom) » ne répond pas — voir \(fontes.path)")
    exit(1)
}

// MARK: - Le corpus réel, aplati en courses

let latin = NSFont(name: CORPS, size: TAILLE)!
let ezra = NSFont(name: HEBREU, size: TAILLE * ECHELLE)!

/// Aplatit un nœud du corpus en courses de texte, en gardant la fonte de
/// chacune. On ne rend pas les niveaux — ce n'est pas ce qu'on mesure — mais on
/// garde **l'alternance des fontes**, qui est tout le sujet.
func courses(_ noeud: [String: Any]) -> [(String, NSFont)] {
    switch noeud["t"] as? String {
    case "translit":
        var r: [(String, NSFont)] = []
        if let t = noeud["translit"] as? String { r.append((t + " ", latin)) }
        if let h = noeud["hebrew"] as? String { r.append((h, ezra)) }
        return r
    case "heb", "shem":
        return [((noeud["v"] as? String) ?? "", ezra)]
    case "break":
        return [("\n", latin)]
    default:
        if let v = noeud["v"] as? String { return [(v, latin)] }
        if let enfants = noeud["children"] as? [[String: Any]] { return enfants.flatMap(courses) }
        return []
    }
}

let livre = try! JSONSerialization.jsonObject(
    with: Data(contentsOf: racine.appendingPathComponent("app/Resources/data/books/bereshit.json")))
    as! [String: Any]
let chapitres = livre["chapters"] as! [[String: Any]]

/// Le chapitre le plus lourd du livre — on mesure le pire cas, pas la moyenne.
let chapitre = chapitres.max(by: {
    (($0["blocks"] as? [[String: Any]])?.count ?? 0) < (($1["blocks"] as? [[String: Any]])?.count ?? 0)
})!

var versets: [[(String, NSFont)]] = []
for bloc in chapitre["blocks"] as! [[String: Any]] {
    guard bloc["t"] as? String == "verses" else { continue }
    for v in (bloc["verses"] as? [[String: Any]]) ?? [] {
        let c = ((v["nodes"] as? [[String: Any]]) ?? []).flatMap(courses)
        if !c.isEmpty { versets.append(c) }
    }
}

let signes = versets.reduce(0) { $0 + $1.reduce(0) { $0 + $1.0.count } }
let avecHebreu = versets.filter { $0.contains { $0.1 == ezra } }.count
print("chapitre « \((chapitre["title"] as? String) ?? "?") » — \(versets.count) versets, "
    + "\(signes) signes, \(avecHebreu) portant de l'hébreu\n")

func nsChaine(_ c: [(String, NSFont)]) -> NSAttributedString {
    let m = NSMutableAttributedString()
    for (texte, fonte) in c { m.append(NSAttributedString(string: texte, attributes: [.font: fonte])) }
    return m
}
func swiftChaine(_ c: [(String, NSFont)]) -> AttributedString {
    var a = AttributedString()
    for (texte, fonte) in c {
        var m = AttributedString(texte)
        m.font = .custom(fonte.fontName, size: fonte.pointSize)
        a += m
    }
    return a
}

// MARK: - Les quatre chemins, à froid puis à chaud

/// Cale une chaîne à une largeur donnée.
///
/// `String(format: "%-38s")` compte les **octets** : « à froid » y vaut huit
/// signes et neuf octets, et la colonne se décale d'un cran par accent. Pire,
/// il rend l'UTF-8 illisible dès que la chaîne en sort. On cale sur le nombre
/// de caractères, qui est ce qu'on voulait dire.
func cale(_ s: String, _ largeur: Int) -> String {
    s + String(repeating: " ", count: max(0, largeur - s.count))
}


/// Rend la mesure à froid — première mise en page — et la moyenne à chaud.
@MainActor
func chrono(_ tours: Int, froid: () -> Void, chaud: () -> Void) -> (Double, Double) {
    let t0 = CFAbsoluteTimeGetCurrent()
    froid()
    let premier = (CFAbsoluteTimeGetCurrent() - t0) * 1000
    chaud()  // un tour à blanc : le premier chaud paie encore des caches
    let t1 = CFAbsoluteTimeGetCurrent()
    for _ in 0..<tours { chaud() }
    return (premier, (CFAbsoluteTimeGetCurrent() - t1) * 1000 / Double(tours))
}

func toutLeChapitre() -> NSAttributedString {
    let tout = NSMutableAttributedString()
    for v in versets {
        tout.append(nsChaine(v))
        tout.append(NSAttributedString(string: "\n", attributes: [.font: latin]))
    }
    return tout
}

func poserTextKit(_ chaine: NSAttributedString) -> (NSLayoutManager, NSTextContainer) {
    let stockage = NSTextStorage(attributedString: chaine)
    let disposition = NSLayoutManager()
    let conteneur = NSTextContainer(size: NSSize(width: LARGEUR, height: .greatestFiniteMagnitude))
    conteneur.lineFragmentPadding = 0
    stockage.addLayoutManager(disposition)
    disposition.addTextContainer(conteneur)
    return (disposition, conteneur)
}

@MainActor
func rendreSwift(_ a: AttributedString) {
    _ = ImageRenderer(content: Text(a).frame(width: LARGEUR, alignment: .leading)).nsImage
}

MainActor.assumeIsolated {
    print(cale("chemin", 38) + cale("à froid", 12) + cale("à chaud", 12))

    // A1 — une Text SwiftUI par verset.
    let chainesSwift = versets.map(swiftChaine)
    let toutSwift = chainesSwift.reduce(into: AttributedString()) { $0 += $1 + AttributedString("\n") }
    let a1 = chrono(3, froid: { chainesSwift.forEach(rendreSwift) }, chaud: { chainesSwift.forEach(rendreSwift) })
    let a2 = chrono(3, froid: { rendreSwift(toutSwift) }, chaud: { rendreSwift(toutSwift) })

    // B — une vue de texte par verset. À chaud, on remesure les mêmes vues :
    // c'est ce que fait un défilement qui redemande leur taille.
    var champs: [NSTextField] = []
    let b = chrono(10) {
        champs = versets.map { v in
            let c = NSTextField(labelWithAttributedString: nsChaine(v))
            c.preferredMaxLayoutWidth = LARGEUR
            c.lineBreakMode = .byWordWrapping
            _ = c.sizeThatFits(NSSize(width: LARGEUR, height: .greatestFiniteMagnitude))
            return c
        }
    } chaud: {
        for c in champs { _ = c.sizeThatFits(NSSize(width: LARGEUR, height: .greatestFiniteMagnitude)) }
    }

    // C — une seule vue. À chaud, `ensureLayout` sur un conteneur déjà disposé
    // ne recalcule rien : c'est exactement ce que gagne le défilement.
    var pose: (NSLayoutManager, NSTextContainer)?
    let c = chrono(10) {
        pose = poserTextKit(toutLeChapitre())
        pose!.0.ensureLayout(for: pose!.1)
    } chaud: {
        pose!.0.ensureLayout(for: pose!.1)
        _ = pose!.0.usedRect(for: pose!.1)
    }

    for (nom, m) in [("A1 — SwiftUI Text, par verset", a1), ("A2 — SwiftUI Text, d'un tenant", a2),
                     ("B  — TextKit, par verset", b), ("C  — TextKit, d'un tenant", c)] {
        print(cale(nom, 38) + String(format: "%8.2f ms %8.3f ms", m.0, m.1))
    }

    print(String(format: "\n  B / C à froid : %.1f×   — le coût du choix d'architecture, à moteur égal", b.0 / max(c.0, 0.0001)))
    print(String(format: "  par verset, à froid : B %.3f ms   C %.3f ms", b.0 / Double(versets.count), c.0 / Double(versets.count)))
    print("\n  Repère : 16,7 ms est le budget d'une image à 60 Hz.")
}

